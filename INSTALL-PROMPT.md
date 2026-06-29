# Copy-paste setup prompt

Clone this repo, open a terminal in it, and start an AI coding session that can
run shell commands and read/write files (e.g. **Claude Code** in this folder, or
point your assistant at this directory). Then paste the prompt below.

It tells the assistant to study the package, explain it, install it on your Mac,
and teach you how to use it — pausing for the few things only you can provide
(your iA Writer auth token, which folders to register, which client to wire).

---

```text
You are helping me set up the "iA Writer Authorship MCP" tool from this
repository (you have shell + file access to this checkout).

First, READ these files in order so you fully understand the package before
touching anything:
  1. AGENT-GUIDE.md   — your brief: what this is, the architecture, the tools,
                        the load-bearing gotchas, and how to help me set it up.
  2. README.md        — overview and requirements.
  3. SETUP.md         — the step-by-step human setup.
  4. reference/ia-writer-cli.md — deep reference (URL scheme, the &-prefix, limits).

Then do the following, one step at a time, checking in with me:

  A. EXPLAIN it to me in a few sentences — lead with *why* it exists (honest
     human-vs-AI authorship inside iA Writer), then the one-line architecture.

  B. CHECK my prerequisites and tell me what's missing: macOS, iA Writer for Mac
     installed and running with Authorship available, `uv` installed
     (`command -v uv`), and the absolute path to `uv` (`which uv`).

  C. INSTALL it: pick a stable home (I suggest ~/.tools/ia-writer-mcp), copy the
     package there, warm the dependency cache once (`uv run --script server.py`,
     which exits on EOF), and sanity-check the engine with `--check`.

  D. CONFIGURE the parts only I can decide — ASK me, don't guess:
     - my iA Writer auth token (Settings → General → URL Commands → Manage). Have
       ME paste it into secrets/ia-writer.env yourself — DO NOT read it back,
       echo it, or print it anywhere.
     - which on-disk folders are iA Writer Locations, and their exact sidebar
       labels, to fill ia-attribute.locations.conf.
     - which client(s) to wire: Claude Code (global via `claude mcp add` or a
       project .mcp.json) and/or Claude Desktop (merge into its config; back it
       up first; remind me to quit+reopen Desktop).
     - remind me to enable Authorship on the document I want to test.

  E. INSTALL THE SKILL so Claude Code uses it automatically (Claude Code users
     only; skip for Claude-Desktop-only setups). The skill makes Claude Code
     auto-route .md edits through this tool without me having to ask. Do this:
       - Create ~/.claude/skills/ia-writer-attribution/ and copy skill/SKILL.md
         into it as SKILL.md (this global location is auto-discovered; a project
         .claude/skills/… works too if I prefer per-project).
       - In that COPIED SKILL.md, replace every engine path (e.g. the
         `.tools/ia-attribute.sh` examples) with the ABSOLUTE path to the engine
         in my install dir (<INSTALL_DIR>/ia-attribute.sh), and fix the reference
         link to point at <INSTALL_DIR>/reference/ia-writer-cli.md. The skill must
         call the real installed engine.
       - Confirm with me, then tell me to restart Claude Code so the skill loads.

  F. TEST end-to-end: check_attribution on a test file, a small apply_ai_edit,
     then confirm the edited span shows as &AI in iA Writer. Report any non-zero
     exit code with its hint instead of silently falling back to a direct write.

  G. TEACH me the full toolset:
     - check_attribution  — call before editing any .md.
     - apply_ai_edit      — patch: send the WHOLE document body (no fragment, no
                            annotation block).
     - append_ai_content  — add: send ONLY a new chunk to append/prepend (great
                            for accretive notes; no whole-body resend).
     - create_ai_document — start a brand-new AI-authored file.
     - open_in_ia         — surface a doc in iA so I can review the &AI spans.
     - clear_attribution  — between review rounds, so the next round's &AI shows
                            only that round's changes.

Rules: never print/echo my auth token; never apply a direct file write to a file
that check_attribution reports as authored/in-location (it corrupts the block);
send the whole document body to apply_ai_edit (use append_ai_content when you only
mean to add a chunk); create_ai_document only for files that don't exist yet.
macOS only.
```

---

Prefer to do it by hand? Follow **[SETUP.md](SETUP.md)** instead.
