# iA Writer Authorship — MCP server + CLI + skill

Make an AI assistant's edits to your **iA Writer** documents show up as
**AI-authored** (`&AI`) in each file's
[Markdown Annotations](https://github.com/iainc/Markdown-Annotations) block —
automatically, through any MCP client (Claude Code, Claude Desktop, MCP-capable
editors).

When iA Writer's **Authorship** feature is on, every span of a document is tagged
by who wrote it (`@you`, `&AI`, `*reference`). If an AI edits the file directly,
that tagging is destroyed. This package routes AI edits through iA Writer's *own*
`write` command, so iA diffs the change and tags only the AI-written spans `&AI`,
leaving your own writing untouched.

> **macOS only.** Requires iA Writer for Mac, running, with Authorship enabled.

---

## Quick start — let an AI install it for you

This package is written so an AI coding assistant can install and explain it for
you end-to-end:

1. **Clone** this repo and open it in an AI session with shell + file access
   (e.g. run `claude` inside the folder):
   ```bash
   git clone https://github.com/gouthamganesan/ia-writer-authorship-mcp.git
   cd ia-writer-authorship-mcp
   ```
2. **Paste the setup prompt** from **[INSTALL-PROMPT.md](INSTALL-PROMPT.md)** into
   your assistant. It will read the package, explain it, check prerequisites,
   install it, wire it into your client(s), and walk you through a live test —
   pausing for the few things only you can provide (auth token, which folders,
   which client).

Prefer to do it by hand? Follow **[SETUP.md](SETUP.md)** (~10 minutes).

## How it works (one sentence)

`MCP client → server.py → ia-attribute.sh → open "ia-writer://…/write" → iA Writer
diffs your new text against the file and tags the changed spans &AI`.

The server is a **thin wrapper**; `ia-attribute.sh` is the single source of truth.
See **[AGENT-GUIDE.md](AGENT-GUIDE.md)** for the full architecture and the
load-bearing gotchas (the `&`-prefix marker; the document owner being implicit).

## What's in this package

```
.
├── README.md                          ← you are here (overview)
├── INSTALL-PROMPT.md                  ← the copy-paste prompt for an AI assistant
├── SETUP.md                           ← step-by-step setup for a human
├── AGENT-GUIDE.md                     ← brief for an AI agent: understand + explain + set up
├── server.py                          ← the MCP server (Python, single file, run via uv)
├── ia-attribute.sh                    ← the engine: drives iA Writer's URL command (the real work)
├── ia-attribute.locations.conf.example← template: map on-disk folders → iA Locations
├── secrets/ia-writer.env.example      ← template: your iA Writer auth token (no real token)
├── config-examples/                   ← Claude Code & Claude Desktop config templates
├── skill/SKILL.md                     ← OPTIONAL Claude Code skill (auto-routes .md edits)
└── reference/ia-writer-cli.md         ← deep reference: URL scheme, the &-prefix, token handling
```

## The three tools the server exposes

| Tool | Use |
|------|-----|
| `check_attribution(file_path)` | Before editing: is this file `authored` / `in-location` / `plain`? |
| `apply_ai_edit(file_path, new_prose, author="AI")` | Apply an edit; send the **full** new body, no annotation block. Tags changed spans `&AI`. |
| `clear_attribution(file_path)` | Accept current edits; reset all authorship between review rounds. |

## Requirements

- **macOS**, with **iA Writer for Mac** running and **Authorship enabled**.
- [`uv`](https://docs.astral.sh/uv/) installed (it manages Python ≥3.10 and the
  `mcp` dependency for you).
- An iA Writer **auth token**, and each target folder registered as an iA Writer
  **Location**.

## Three ways to use it

- **MCP server** (`server.py`) — for Claude Desktop, Claude Code, and other MCP
  clients. The portable path; see [SETUP.md](SETUP.md).
- **CLI** (`ia-attribute.sh`) — call the engine directly from any script or shell.
- **Skill** (`skill/SKILL.md`) — an optional Claude Code skill that auto-detects iA
  files and routes edits through the engine without the MCP.

## License

[MIT](LICENSE) © 2026 Goutham Ganesan.

### Acknowledgments
Built on iA Writer's URL commands and the
[Markdown Annotations](https://github.com/iainc/Markdown-Annotations) format by
[iA Inc.](https://ia.net/writer) This is an independent project and is **not
affiliated with or endorsed by iA Inc.** "iA Writer" is a trademark of its owner.

---

> ⚠️ **A small note:** this package — code and docs — was built with substantial
> AI assistance. It's been tested end-to-end on the author's machine, but please
> read the source (it's short and commented) before trusting it with your writing,
> and **[open an issue](https://github.com/gouthamganesan/ia-writer-authorship-mcp/issues)**
> if anything is wrong, unclear, or could be better. Contributions and bug reports
> are very welcome.
