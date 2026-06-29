> **NOTE:** OPTIONAL — a Claude Code skill that routes `.md` edits through the same
> `ia-attribute.sh` engine *without* the MCP server. It is NOT needed for the MCP
> setup. The paths below (`.tools/ia-attribute.sh`, the `Notes` Location example,
> `$CLAUDE_JOB_DIR`) are illustrative — **adapt them to your install folder**
> before using. To install: copy this file to `.claude/skills/ia-writer-attribution/SKILL.md`
> in your project (or `~/.claude/skills/…` for global), and point the commands at
> wherever you placed `ia-attribute.sh`. For an MCP-only setup, ignore this file.

---
name: ia-writer-attribution
description: >
  Use whenever you are about to MODIFY a Markdown (.md) file that belongs to iA Writer — either
  it carries an authorship block at its end (a trailing `---` / `...` block with an
  `Annotations:` line and `@author` / `&author` ranges), OR it lives in a folder that is an iA
  Writer Location (listed in ia-attribute.locations.conf, e.g. a "Notes" folder). For such files,
  edits MUST be applied through the `ia-attribute.sh` tool so the changed spans are marked as AI
  (`&AI`) in the annotation block — NOT with the Edit/Write tools, which would corrupt the block
  and lose attribution.

  Trigger on any intent to edit/rewrite/fix/revise/clean-up the prose of a .md file: before the
  first Edit/Write to any .md, run `ia-attribute.sh --check`. If it reports `authored` or
  `in-location` (exit 0), this skill governs how the edit is applied. Also trigger whenever the
  user says things like "edit this in iA", "keep authorship", "mark your changes as AI", or
  references iA Writer — even for a file outside a Location.
---

# iA Writer AI-Attribution

When you edit a Markdown file that iA Writer tracks for authorship, route the edit through
iA Writer's own `write` command so your changes are attributed to **&AI** in the file's
[Markdown Annotations](https://github.com/iainc/Markdown-Annotations) block. Editing the file
directly with Edit/Write would silently overwrite the annotation block and destroy authorship.

## When this skill applies

Don't eyeball it — ask the tool, with the **absolute** path:

```bash
.tools/ia-attribute.sh --check --file "<absolute path to the .md>"
```

| Output | Exit | Meaning | Action |
|--------|------|---------|--------|
| `authored`    | 0 | File has an annotation block already | Route the edit through the tool (this skill) |
| `in-location` | 0 | No block yet, but the file is in an iA Location | Route the edit through the tool (this skill) |
| `plain`       | 1 | Neither | Edit normally with Edit/Write — **unless** the user explicitly asked to mark edits as AI / use iA |

A fresh note you wrote yourself often has **no block yet** (iA only writes one once a doc has
AI/non-owner content) — that's why `in-location` matters: it catches those. The first AI edit
creates the block, marking only the AI span `&AI` and leaving your text as owner-default (you).

An authored file's tail looks like (delimited by `---` … `...`):

```
The actual document prose…

---
Annotations: 0,1234 SHA-256 ab12cd34…
@you <you@example.com>: 0,800 1100,40
&AI: 800,300
...
```

`@name` = human-written, `&name` = AI-written, `*name` = reference; ranges are
`start,length` in grapheme clusters.

## How to apply an edit (authored files only)

The tool delegates to iA: you hand it the **entire new document prose**, iA diffs it against
the file, keeps existing `@human` ranges, and tags only the changed spans as `&AI`.

1. **Read** the file to get its current contents.
2. **Construct the full new prose** — the complete document body with your edit applied.
   - Send the **whole** document, not a fragment: iA patches by diffing full text.
   - **Exclude** the trailing annotation block. (The tool strips it defensively, but don't
     rely on that — send prose only.)
3. **Pipe it to the tool** (do NOT use Edit/Write on this file):

   ```bash
   printf '%s' "$NEW_PROSE" | .tools/ia-attribute.sh --file "<absolute path to the .md>"
   ```

   For multi-line bodies, write the new prose to a temp file under `$CLAUDE_JOB_DIR/tmp/`
   (or `/tmp`) and pipe it in:

   ```bash
   .tools/ia-attribute.sh --file "<abs path>" < "$CLAUDE_JOB_DIR/tmp/new-body.md"
   ```

4. **Confirm** the tool prints `ok: patched and attributed to &AI` and exits 0. Then re-read
   the file to show the user the updated annotation block.

The author label defaults to `AI` (→ `&AI`). Override with `--author "Name"` if asked.

## Iterative review — show only the current round's AI changes

The typical loop: you draft → AI edits → you review the `&AI` spans → you give feedback → AI
edits again. From the **second** round on, you usually want to see *only the latest* round's
AI changes, not an accumulation of every prior round.

Before applying a **new** round of edits, **accept the previous round** by clearing
attribution:

```bash
.tools/ia-attribute.sh --clear --file "<absolute path to the .md>"
```

This re-writes the current prose with no author, resetting every span to owner-default and
dropping all `&AI` (and `@human`) marks — the text is unchanged, only the colouring is reset.
Then apply the new round's edits as usual; the resulting `&AI` ranges are exactly the changes
from *this* round.

Guidance:
- Do the clear **after** the user has reviewed/approved the prior round and is asking for more
  changes — not silently mid-round. If unsure whether they're done reviewing, ask.
- `--clear` is a **no-op** if there's no AI attribution (prints `nothing to clear`).
- It clears *all* authorship, not just AI. That's intended ("accept everything so far"); since
  only `&AI` is visually flagged, your own text looks the same either way.

## Other engine modes (besides patch)

The same engine supports more than in-place patching — prefer the one that matches
the intent:

- **Append/prepend a chunk** (don't resend the whole doc):
  `printf '%s' "$CHUNK" | <engine> --add [--prepend] --file "<abs path>"`
- **Create a new AI-authored file** (won't overwrite):
  `printf '%s' "$BODY" | <engine> --create --file "<abs path>"`
- **Open a doc for review** (no edit): `<engine> --open --file "<abs path>"`

Use `--add` instead of patch when you only mean to *append* content — it's cheaper
and avoids reconstructing the entire document.

## Hard rules

- **Never** apply an Edit/Write directly to an authored file — it bypasses attribution and
  corrupts the annotation block. The only sanctioned edit path is the tool.
- **Send the complete prose.** A partial body would make iA think the rest was deleted.
- **Don't fabricate the annotation block yourself.** Let iA recompute the SHA + ranges; the
  grapheme-cluster math and hashing must match iA exactly.

## When the tool fails (non-zero exit)

The tool verifies the patch landed. It fails (and changes nothing) if:

- **iA Writer isn't running** → exit 2. Launch it (`open -a "iA Writer"`) and retry.
- **The file isn't in a configured iA Location** → it can't resolve the path. The file's
  folder must be added as a Location in iA Writer *and* listed in
  `.tools/ia-attribute.locations.conf` (`LocationName=/abs/dir`).
- **File changed but no `&AI` appears** → exit 3. Authorship may be off for that document in
  iA Writer.

If it fails, **report it to the user — do not silently fall back to Edit/Write**, which would
lose authorship. Let the user decide.

Full reference (URL scheme, the `&`-prefix gotcha, token handling): see
`reference/ia-writer-cli.md` in this repository.
