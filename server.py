#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.2.0"]
# ///
"""
iA Writer attribution MCP server.

Exposes the verified `ia-attribute.sh` engine as three MCP tools so any MCP
client (Claude Code, Claude Desktop, MCP-capable editors) can make its edits to
iA Writer documents show up as AI-authored (`&AI`) in the file's Markdown
Annotations block.

This is a thin wrapper: all the real work — talking to iA Writer over its
`ia-writer://` URL command, resolving the on-disk path to an iA Location,
sourcing the auth token, and verifying the patch landed — lives in
`ia-attribute.sh`, which stays the single source of truth. This server adds
structured tool arguments (so prose is passed as a real argument instead of
piped through a shell) and a portable interface for clients that can't run a
bash skill directly.

Run standalone for a quick sanity check:
    uv run --script server.py     # starts the stdio server (Ctrl-C to stop)

Where it finds the engine (`ia-attribute.sh`), in order:
  1. $IA_ATTRIBUTE_SCRIPT  (explicit absolute path override)
  2. the same directory as this file        (standalone package layout)
  3. this file's parent directory            (legacy layout: engine one level up)

Constraints inherited from the engine (none of which this server removes):
  - macOS only; iA Writer must be running with Authorship enabled.
  - The target file's folder must be a registered iA Writer Location AND listed
    in ia-attribute.locations.conf (next to ia-attribute.sh).
  - Auth token must exist in secrets/ia-writer.env (next to ia-attribute.sh).
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP


def _find_engine() -> Path:
    """Locate ia-attribute.sh. See module docstring for the search order."""
    override = os.environ.get("IA_ATTRIBUTE_SCRIPT")
    if override:
        return Path(override).expanduser().resolve()
    here = Path(__file__).resolve().parent
    same_dir = here / "ia-attribute.sh"
    if same_dir.exists():
        return same_dir
    return here.parent / "ia-attribute.sh"  # legacy layout: engine one level up


SCRIPT = _find_engine()

mcp = FastMCP("ia-writer-attribution")


def _abs(file_path: str) -> str:
    """Expand ~ and resolve to an absolute path (the engine requires absolute)."""
    return str(Path(file_path).expanduser().resolve())


def _run(args: list[str], stdin: str | None = None) -> subprocess.CompletedProcess:
    """Invoke ia-attribute.sh with the given args, optionally feeding stdin."""
    if not SCRIPT.exists():
        raise FileNotFoundError(
            f"engine not found: {SCRIPT} "
            f"(set IA_ATTRIBUTE_SCRIPT or place ia-attribute.sh next to server.py)"
        )
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        input=stdin,
        capture_output=True,
        text=True,
    )


@mcp.tool()
def check_attribution(file_path: str) -> dict:
    """Decide whether edits to a Markdown file must be routed through iA Writer
    attribution. ALWAYS call this before editing any .md file that might belong
    to iA Writer.

    Returns a `status`:
      - "authored"    — the file already has an iA annotation block.
      - "in-location" — no block yet, but the file lives in a registered iA
                        Location (a fresh note iA will start tracking).
      - "plain"       — neither; edit it normally with your editor's file tools.

    When status is "authored" or "in-location", you MUST apply edits via
    `apply_ai_edit` (NOT a direct file write) or you will corrupt the annotation
    block and lose authorship.

    Args:
        file_path: Absolute path to the .md file (~ is expanded).
    """
    proc = _run(["--check", "--file", _abs(file_path)])
    status = proc.stdout.strip()
    if status in ("authored", "in-location", "plain"):
        return {
            "status": status,
            "should_attribute": status in ("authored", "in-location"),
        }
    return {
        "status": "error",
        "should_attribute": False,
        "error": (proc.stderr or proc.stdout).strip(),
    }


@mcp.tool()
def apply_ai_edit(file_path: str, new_prose: str, author: str = "AI") -> dict:
    """Apply an edit to an iA Writer document so the changed spans are attributed
    to AI (`&AI`) in the file's annotation block.

    Pass the COMPLETE new document body in `new_prose` — the entire file with
    your edit applied, NOT a fragment. iA Writer diffs it against the current
    file, keeps existing human ranges untouched, and tags only the changed spans.
    Sending a partial body would make iA think the rest was deleted.

    Do NOT include the trailing annotation block in `new_prose` (the `---` /
    `...` block with the `Annotations:` line); the engine strips it defensively,
    but you should send prose only. iA recomputes the block itself.

    Use this INSTEAD of a direct file write whenever `check_attribution` returns
    "authored" or "in-location".

    Args:
        file_path: Absolute path to the .md file (~ is expanded).
        new_prose: The full new document body (no annotation block).
        author: Authorship label; defaults to "AI" (→ `&AI`).
    """
    proc = _run(["--file", _abs(file_path), "--author", author], stdin=new_prose)
    msg = (proc.stdout or proc.stderr).strip()
    return {
        "success": proc.returncode == 0,
        "exit_code": proc.returncode,
        "message": msg,
        "hint": _hint_for(proc.returncode),
    }


@mcp.tool()
def clear_attribution(file_path: str) -> dict:
    """Accept all current edits by clearing ALL authorship on the file, resetting
    every span to owner-default (drops all `&AI` and human marks; the prose is
    unchanged).

    Use this in the iterative review loop: after the user has reviewed and
    approved a round of AI edits and is asking for more, clear first so the NEXT
    round's `&AI` spans show only that round's changes — not an accumulation.
    No-op if there is no AI attribution to clear.

    Args:
        file_path: Absolute path to the .md file (~ is expanded).
    """
    proc = _run(["--clear", "--file", _abs(file_path)])
    msg = (proc.stdout or proc.stderr).strip()
    return {
        "success": proc.returncode == 0,
        "exit_code": proc.returncode,
        "message": msg,
        "hint": _hint_for(proc.returncode),
    }


def _hint_for(code: int) -> str | None:
    """Human-actionable hint for a non-zero engine exit code."""
    return {
        2: "iA Writer didn't modify the file. Is iA running, is the file's "
           "folder a registered iA Location, and is the auth token valid?",
        3: "File changed but no AI attribution appeared. Enable Authorship for "
           "this document in iA Writer.",
    }.get(code)


if __name__ == "__main__":
    mcp.run()
