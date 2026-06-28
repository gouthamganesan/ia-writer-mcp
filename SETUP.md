# Setup — iA Writer Attribution MCP server

Time: ~10 minutes. macOS only. Do the steps in order.

## 0. Prerequisites

- **iA Writer for Mac**, installed and able to run.
- **`uv`** — the Python runner that handles everything else.
  ```bash
  command -v uv || brew install uv      # or: curl -LsSf https://astral.sh/uv/install.sh | sh
  which uv                              # note this path — you'll need it later
  ```
  You do **not** need to install Python or `mcp` yourself; `uv` does that on first run.

## 1. Put this folder somewhere permanent

Pick a stable home (it must not move after you wire up the configs). Copy the
contents of this repo there, e.g.:

```bash
mkdir -p ~/.tools/ia-writer-mcp
cp -R ./ ~/.tools/ia-writer-mcp/      # run from the repo root
cd ~/.tools/ia-writer-mcp
```

From now on, **`<INSTALL_DIR>` = the absolute path to this folder** (e.g.
`/Users/you/.tools/ia-writer-mcp`). Get it with `pwd`.

## 2. Add your iA Writer auth token

```bash
cp secrets/ia-writer.env.example secrets/ia-writer.env
```

In **iA Writer → Settings → General → URL Commands → Manage**, create/copy a
token. Paste it into `secrets/ia-writer.env`:

```
IA_WRITER_AUTH_TOKEN=your-token-here
```

This file is a secret — don't commit or share it.

## 3. Register your folders as iA Locations (two places, must match)

**(a) In iA Writer:** add the folder(s) you'll edit as **Locations** (sidebar →
add Location). Note each Location's exact label.

**(b) In this tool:** map on-disk paths to those Locations:

```bash
cp ia-attribute.locations.conf.example ia-attribute.locations.conf
```

Edit `ia-attribute.locations.conf` — one line per Location,
`LocationLabel=/absolute/on-disk/folder`. The label must match iA's sidebar
exactly. Example:

```
Notes=/Users/you/Documents/Notes
```

## 4. Enable Authorship in iA Writer

Open a document → enable **Authorship** (Edit menu / the document's authorship
toggle). Without this, edits land but nothing gets tagged `&AI`.

## 5. Sanity-check the server

```bash
uv run --script server.py
```

First run downloads the `mcp` package (needs internet; if you're behind a proxy,
prefix with `https_proxy=… http_proxy=…`). It should start and wait silently —
that means it's healthy. Press **Ctrl-C** to stop. After this first run the
download is cached, so GUI apps can launch it offline.

## 6. Wire it into your MCP client

Use the **absolute** path to `uv` (from step 0) and to `server.py`
(`<INSTALL_DIR>/server.py`). Templates are in `config-examples/`.

### Claude Code
Copy `config-examples/claude-code.mcp.json` to `.mcp.json` at the root of the
project you work in (or use `claude mcp add`), and fill in the two absolute
paths. Verify with `/mcp` (or `claude mcp list`).

### Claude Desktop
Merge the `mcpServers` block from `config-examples/claude-desktop.config.json`
into `~/Library/Application Support/Claude/claude_desktop_config.json` (keep any
existing keys). Fill in the two absolute paths. **Fully quit and reopen** Claude
Desktop. The `ia-writer` server with three tools should appear in Settings.

## 7. Live test

With iA Writer running and a test document open (in a registered Location, with
Authorship on), ask your assistant something like:

> "Use the ia-writer tools: check_attribution on `<that file>`, then make a small
> edit to it with apply_ai_edit."

Then look at the document in iA Writer — the edited span should be coloured as
`&AI`. Done.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Tools don't appear in the client | Wrong `uv` path or wrong `server.py` path in the config; check the client's MCP logs. |
| `exit_code: 2` from `apply_ai_edit` | iA Writer not running, folder not a registered Location, mismatched Location label, or bad/missing token. |
| `exit_code: 3` | File changed but no `&AI` — **Authorship is off** for that document. Enable it. |
| `engine not found` | `server.py` can't find `ia-attribute.sh`. Keep them in the same folder, or set env `IA_ATTRIBUTE_SCRIPT=/abs/path/ia-attribute.sh`. |
| First `uv run` fails to download | No internet / proxy. Set `http_proxy`/`https_proxy` for that first run (and optionally in the config `env`). |

Deep reference (URL scheme internals, the `&`-prefix AI marker, security):
`reference/ia-writer-cli.md`.
