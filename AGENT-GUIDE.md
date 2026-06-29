# Agent guide — iA Writer Attribution MCP

You are an AI assistant. Someone handed you this package and wants you to (a)
understand it, (b) explain it to them, and (c) help them set it up. This file is
your brief. Read it fully before acting.

---

## 1. What this is, in one paragraph

iA Writer (a Mac Markdown editor) has an **Authorship** feature: when on, it
tracks *who wrote each span* of a document in a trailing "Markdown Annotations"
block — `@name` for a human, `&name` for AI, `*name` for a reference. The problem:
if an AI assistant edits such a file with normal file-write tools, it overwrites
that block and destroys the authorship record. This package solves that. It is an
**MCP server** that, instead of writing the file directly, hands the new text to
**iA Writer's own `write` URL command**, which diffs it against the file and tags
only the changed spans as `&AI` — preserving the human-authored ranges and
recomputing the block (SHA + ranges) correctly.

So: the user gets AI edits that are *honestly attributed* inside iA Writer,
across any MCP client.

## 2. Architecture (know this before you explain or debug)

```
MCP client (Claude Code / Claude Desktop / editor)
   │  stdio (JSON-RPC), six tools
   ▼
server.py        ← thin Python wrapper (FastMCP). PEP 723 single-file script,
   │               run by `uv run --script` (uv auto-installs `mcp`, Python ≥3.10)
   │  subprocess: bash ia-attribute.sh …
   ▼
ia-attribute.sh  ← THE ENGINE and single source of truth. Does the real work:
   │               • maps on-disk path → iA "Location: relpath" (locations.conf)
   │               • sources the auth token (secrets/ia-writer.env)
   │               • builds & fires the ia-writer:// URL
   │               • verifies the patch landed (shasum change + &AI line present)
   │  open -g "ia-writer://x-callback-url/write?…"
   ▼
iA Writer.app    ← diffs your text vs the file, tags changed spans &AI, rewrites
                   the annotation block itself
```

**Design intent:** the server adds *nothing* clever. All verified logic lives in
the `.sh`. The server only: exposes structured tools, passes prose as a real
argument (not shell-piped), and gives non-CLI clients (Claude Desktop) a way in.
When debugging, suspect configuration/environment first, not the server code.

## 3. The tools

- **`check_attribution(file_path)`** → `{status, should_attribute}`.
  `status` is `authored` (has a block) / `in-location` (no block yet, but in a
  registered iA Location) / `plain` (neither). Call this BEFORE editing any `.md`.
  Only route through the MCP when `should_attribute` is true.
- **`apply_ai_edit(file_path, new_prose, author="AI")`** → patch an existing file.
  **`new_prose` must be the COMPLETE new document body** (the whole file with the
  change), **without** the trailing annotation block. iA diffs full text; a
  fragment would look like a mass deletion. Returns `{success, exit_code,
  message, hint}`.
- **`append_ai_content(file_path, content, author="AI", location="end", padding="paragraph")`**
  → add a CHUNK (mode=add). Send ONLY the new content, not the whole body; iA
  appends (or prepends, `location="beginning"`) it and tags just the added span
  `&AI`. Use for accretive work; avoids the whole-document resend that `apply_ai_edit`
  requires. The mental model: **`apply_ai_edit` = edit-in-place (whole body);
  `append_ai_content` = grow (chunk only).**
- **`create_ai_document(file_path, content, author="AI")`** → create a NEW file
  whose entire body is `&AI` (mode=create). Fails fast if the file already exists
  (iA's create never overwrites). For AI-first drafting.
- **`open_in_ia(file_path, new_window=False)`** → open a doc in iA for review
  (interface command; no edit, no token). Handy to surface the `&AI` spans after
  an edit.
- **`clear_attribution(file_path)`** → resets ALL authorship to owner-default
  (drops `&AI`/`@human` marks; prose unchanged). Used between review rounds so the
  next round's `&AI` shows only the latest changes. No-op if nothing is attributed.

Engine exit codes surfaced as `exit_code`: `0` ok · `2` iA didn't modify the file
(not running / not a Location / bad token) · `3` changed but no `&AI` (Authorship
off for that doc).

## 4. The one non-obvious gotcha (the `&`-prefix)

In iA's URL command, `author=AI` is treated as a **human** named "AI" → default
text is left **unmarked** (silent no-op). To mark content as AI you must pass
`author=&AI` (the `&` percent-encoded). `ia-attribute.sh` prepends the `&` for
you — so callers pass a plain label like `AI`, and the engine handles the prefix.
Don't "fix" this by stripping the `&`; it's load-bearing.

## 5. Constraints — state these plainly to the user; the MCP removes NONE of them

- **macOS only**, and **iA Writer must be running**.
- **Authorship must be enabled** for the document (else edits land but nothing is
  tagged → `exit_code: 3`).
- The file's folder must be a registered iA **Location** AND listed in
  `ia-attribute.locations.conf` (label must match iA exactly).
- An **auth token** must exist in `secrets/ia-writer.env`.
- `uv` must be installed.

## 6. How to explain it to the user (suggested framing)

Lead with the *why*, not the plumbing: "iA Writer can track which parts of a doc
you wrote vs. an AI. Normally an AI editing the file wipes that out. This makes
the AI's edits go *through* iA so its changes are honestly marked `&AI` and your
writing stays marked as yours — in Claude Desktop, Claude Code, or any MCP
editor." Then, only if they want depth, walk the architecture in §2. Be honest
about the trade-off: inside Claude Code a shell script + skill already does this;
the MCP's real value is **Claude Desktop and other clients that can't run a
script**, plus passing large text as a clean argument.

## 7. How to help them set up

Walk them through **SETUP.md** step by step. The steps most likely to trip them:

1. **uv path** — configs need the *absolute* path (`which uv`). GUI apps (Claude
   Desktop) don't inherit the shell `PATH`, so a bare `uv` will fail there.
2. **Two-place Location registration** — the folder must be added in iA Writer's
   sidebar *and* in `ia-attribute.locations.conf`, with **matching labels**. This
   is the #1 cause of `exit_code: 2`.
3. **Authorship toggle** — easy to forget; without it they get `exit_code: 3`.
4. **First `uv run`** — must succeed once (downloads `mcp`) before a GUI client
   can launch the server offline; behind a proxy, set `http_proxy`/`https_proxy`.
5. **Secret** — they create `secrets/ia-writer.env` from the `.example`. Never
   read it back to them or echo it; the tooling reads it silently.
6. **Install the skill (Claude Code users)** — so Claude Code routes `.md` edits
   through the tool *automatically*, copy `skill/SKILL.md` to
   `~/.claude/skills/ia-writer-attribution/SKILL.md` (global; or a project
   `.claude/skills/…` for per-project). **Then edit the COPY** to replace its
   example engine paths (e.g. `.tools/ia-attribute.sh`) with the absolute
   `<INSTALL_DIR>/ia-attribute.sh`, and repoint its reference link. Without this
   copy step the skill never activates — shipping it in the repo is not enough.
   Tell them to restart Claude Code so it loads. Skip for Desktop-only setups.

Verify with the live test in SETUP.md §7: `check_attribution` then a small
`apply_ai_edit`, then look for the `&AI` colour in iA Writer.

## 8. Where to read more

- **`reference/ia-writer-cli.md`** — the deep reference: full URL scheme, params,
  the `&`-prefix details, path/Location mapping, token handling, size limits.
- **`skill/SKILL.md`** — a Claude Code skill that auto-detects iA files and routes
  edits through the same engine *without* the MCP. To make it activate it must be
  COPIED to `~/.claude/skills/ia-writer-attribution/SKILL.md` (or a project
  `.claude/skills/…`) and its engine paths adapted — see §7 step 6. Useful only
  inside Claude Code; ignore for an MCP-only / Desktop-only setup.
- **`server.py`** / **`ia-attribute.sh`** — both are short and commented; read the
  source when a behaviour is unclear.

## 9. Safety rules for you, the agent

- **Never** apply a direct file write to a file where `check_attribution` says
  `authored`/`in-location` — it corrupts the block. Use `apply_ai_edit`.
- **Never** print, echo, or read back the contents of `secrets/ia-writer.env`.
- On a non-zero `exit_code`, **report it** with the `hint`; do not silently fall
  back to a direct write (that would lose attribution). Let the user decide.
- Always send the **whole** document body to `apply_ai_edit`, never a fragment.
