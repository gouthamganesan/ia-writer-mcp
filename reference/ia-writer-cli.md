# iA Writer CLI — AI authorship attribution (deep reference)

The engine `ia-attribute.sh` makes an AI assistant's edits to iA Writer documents
show up as **AI-authored** (`&AI`) in the file's
[Markdown Annotations](https://github.com/iainc/Markdown-Annotations) block, by
delegating the edit to iA Writer's own `write` URL command (`mode=patch`). In this
package everything lives together in your install folder: `ia-attribute.sh`,
`secrets/ia-writer.env`, and `ia-attribute.locations.conf` sit side by side.

## MCP server (for Claude Desktop & other MCP clients)
`server.py` wraps this same `ia-attribute.sh` engine as an MCP server (single-file
Python, PEP 723, run via `uv run --script`). It exposes six stdio tools —
`check_attribution`, `apply_ai_edit` (patch), `append_ai_content` (add),
`create_ai_document` (create), `open_in_ia` (open), `clear_attribution` (replace)
— mapping 1:1 to the script's modes. The `.sh` stays the single source of truth; the server shells out
to it and self-locates the script relative to its own path. Wired into **Claude
Code** via repo-root `.mcp.json` (or `claude mcp add`) and **Claude Desktop** via
`~/Library/Application Support/Claude/claude_desktop_config.json`
(`command: /opt/homebrew/bin/uv`, optionally with `http_proxy`/`https_proxy` env
so the first-run dependency download works behind a proxy). Inside Claude Code the
skill + CLI already suffice — the MCP exists mainly so Claude Desktop (which can't
run the bash skill) gets the same capability.

## How it works
You write in iA Writer with **Authorship on**, so your files carry a trailing
annotation block (`@you …`). When the assistant edits such a file, the tool hands
the **full new prose** to iA via `ia-writer://x-callback-url/write?…&mode=patch&author=&AI`.
iA diffs it against the file, keeps the untouched `@human` ranges, and tags only
the changed spans `&AI`, recomputing the SHA + ranges itself. We never hand-edit
the annotation block.

## iA Writer URL command facts (iA Writer for Mac)
- **Bundle id** `pro.writer.mac`; **URL schemes** `ia-writer://`, `iawriter://`.
- **Invoke fire-and-forget** with `open -g "ia-writer://x-callback-url/write?…"`.
  Capturing the `x-success` return from a CLI would need a registered URL handler
  — **not needed**: we verify by re-reading the file (shasum change + presence of
  the `&AI` line).
- **`write` params:** `auth-token` (required), `path` (Library Path), `text` (full
  body), `mode` (`create|replace|add|patch`), `author`.
- **`mode=patch`** diffs `text` vs file and attributes the delta to `author`.

### The critical gotcha — the `&` prefix IS the AI marker
- `author=AI`  → iA treats it as a **human** author; human-default text is left
  **unmarked** (no annotation written). This silently produces *no* attribution.
- `author=&AI` (the `&` percent-encoded as `%26`) → marks the delta as **AI** →
  `&AI: start,len`.
- So: to mark AI content you MUST pass `author=&<label>`. The tool prepends the `&`
  for you.
- Prefixes in the block: `@` = human, `&` = AI, `*` = reference.

### The document owner is implicit (non-obvious)
The document **owner** — your live iA identity (derived from your macOS account) —
is left **unmarked** in the annotation block; iA lists only *non-owner*
contributors. So your own writing never gets an `@` line: it is the invisible
default. A literal `@Name` line only appears for a *named human distinct from the
owner*. (This is why a demo that forces an `@you` span via `author=@you` can create
a second author record that shares your name — the normal tool never does this; it
only ever writes `&AI`.)

### Path mapping (Library Path)
- Form: `<LocationName>: <relative/path.md>` (e.g. `Notes: drafts/foo.md`). A plain
  `/foo.md` targets iA's default library.
- The folder must be added as a **Location** in iA Writer (sidebar) for the path to
  resolve.
- The tool maps an on-disk absolute path → Library Path via
  `ia-attribute.locations.conf` (`LocationName=/abs/dir`, longest prefix wins).

### Size
- The docs state a 4,000-char limit on `text`, but it is **not enforced via
  `open`**: a 56 KB body was written byte-for-byte with no truncation. Large
  documents are fine.

## Secret handling
- Auth token lives in `secrets/ia-writer.env` as `IA_WRITER_AUTH_TOKEN=…`. This
  file is gitignored. Create it yourself (e.g. via a silent `read -rs`); **never
  `cat`/`echo`/`read` it or run `set -x`** — the token must never enter a
  transcript. The tool sources it and interpolates it straight into the `open` URL
  (which prints nothing).
- Token source order: `$IA_WRITER_ENV` → `<script-dir>/secrets/ia-writer.env`.
- Get/rotate the token in iA Writer: Settings → General → URL Commands → Manage.

## Usage
```bash
# should AI edits to this file be attributed? (absolute path)
./ia-attribute.sh --check --file "<abs path>"
#   authored    (0) -> has an annotation block
#   in-location (0) -> no block yet, but in a configured iA Location (catches fresh notes)
#   plain       (1) -> neither; edit normally

# patch: apply an edit (pipe the FULL new prose; annotation block stripped automatically)
printf '%s' "$NEW_PROSE" | ./ia-attribute.sh --file "<abs path>"
./ia-attribute.sh --file "<abs path>" --author "AI" < new-body.md

# add: append/prepend just a CHUNK (mode=add), attributed &AI
printf '%s' "$CHUNK" | ./ia-attribute.sh --add --file "<abs path>"
printf '%s' "$CHUNK" | ./ia-attribute.sh --add --prepend --padding paragraph --file "<abs path>"

# create: a NEW AI-authored file (won't overwrite; fails if it exists)
printf '%s' "$BODY" | ./ia-attribute.sh --create --file "<abs path>"

# open: surface the doc in iA for review (no token needed; file untouched)
./ia-attribute.sh --open [--new-window] --file "<abs path>"

# accept/clear ALL authorship -> owner default (between review iterations)
./ia-attribute.sh --clear --file "<abs path>"
```
Exit codes: `0` ok · `2` iA didn't modify/create the file (not running / not in a
Location / bad token) · `3` changed but no `&AI` (Authorship off for that doc).

### patch vs add (when to use which)
- **patch** (`apply_ai_edit`): in-place edits/rewrites. You reconstruct and send
  the WHOLE body; iA diffs it. Right when changes are scattered through the doc.
- **add** (`append_ai_content`): accretive writing. You send ONLY the new chunk;
  iA appends/prepends it. Cheaper, avoids the whole-body resend and the ~1 MB
  `ARG_MAX` ceiling, and is the natural fit for "add a section / a journal entry".

### clear (`--clear`) — for the iterative review loop
Re-writes the doc's current prose via `mode=replace` with **no author**, which
resets every span to owner-default and drops all `&AI` / `@human` marks (prose
unchanged). Use it between rounds so the next round's AI edits are the only thing
flagged `&AI`. No-op if there's no AI attribution (`nothing to clear`).

## Gotchas / limits
- iA Writer must be **running** and the document's folder must be a **Location**.
- Authorship must be **enabled** in iA for the delta to be tagged (else the file
  changes but no `&AI` line appears → exit 3).
- patch sends the **whole** document; callers must reconstruct the entire body, not
  a fragment.
- New text passed via an env var inside the tool → practical ceiling is `ARG_MAX`
  (~1 MB on macOS); fine for prose, not for multi-MB files.
