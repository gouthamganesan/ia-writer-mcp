#!/usr/bin/env bash
# ia-attribute.sh — apply an edit to an iA Writer document so the changed
# spans are attributed to AI in iA's Markdown Annotations block.
#
# It does NOT hand-edit the annotation block. It hands the full new prose to
# iA Writer's own `write` URL command with mode=patch&author=&AI; iA diffs the
# text, keeps existing @human ranges, and tags only the delta as &AI.
#
# Usage:
#   ia-attribute.sh --check  --file <path>            # 'authored'|'in-location' (0) | 'plain' (1)
#   ia-attribute.sh          --file <path> < newtext  # patch: read full new prose from stdin
#   ia-attribute.sh --author "AI" --file <path> < newtext
#   ia-attribute.sh --clear  --file <path>            # accept/clear ALL authorship -> owner default
#   ia-attribute.sh --add    --file <path> < chunk    # append a CHUNK, attributed &AI (mode=add)
#   ia-attribute.sh --add --prepend --file <path> < chunk   # insert chunk at the beginning
#   ia-attribute.sh --add --padding line|sentence|paragraph --file <path> < chunk
#   ia-attribute.sh --create --file <path> < body     # create a NEW AI-authored file (won't overwrite)
#   ia-attribute.sh --open [--new-window] --file <path>     # open the doc in iA Writer (no token needed)
#
# patch: the new prose is read from stdin. A trailing annotation block
# accidentally left in stdin is stripped automatically (iA owns the block).
#
# add: reads only the NEW content (a chunk) from stdin and appends it via
# mode=add, attributing the added span to &AI. Sends just the chunk, not the
# whole document. --prepend inserts at the beginning; --padding controls spacing
# (default paragraph). Existing @human / &AI ranges are preserved and re-offset.
#
# create: reads the WHOLE body of a new file from stdin and writes it via
# mode=create with the AI author, so the whole document is attributed &AI. iA's
# create never overwrites; this tool fails fast if the file already exists.
#
# open: opens the document in iA Writer (interface command, no auth-token). Use it
# to surface a doc for review. Does not modify the file.
#
# clear: re-writes the document's current prose via mode=replace with no author,
# which resets every span to owner-default and drops all &AI (and @human) marks.
# Use it between review iterations so the NEXT round of AI edits is the only
# thing flagged &AI. No-op if the file has no AI attribution.
#
# Secret: reads IA_WRITER_AUTH_TOKEN from (in order) $IA_WRITER_ENV, or
# <script-dir>/secrets/ia-writer.env. The token is never printed.
#
# Locations: maps an on-disk path to an iA "Location: relative/path" library
# path using <script-dir>/ia-attribute.locations.conf (LINES: Name=/abs/dir).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'ia-attribute: %s\n' "$1" >&2; exit "${2:-1}"; }

AUTHOR_LABEL="AI"
TARGET=""
MODE="patch"          # patch | check | clear | add | create | open
ADD_LOCATION="end"    # end | beginning   (mode=add)
ADD_PADDING="paragraph"  # line | sentence | paragraph (mode=add)
NEW_WINDOW="false"    # mode=open

while [ $# -gt 0 ]; do
  case "$1" in
    --file)    TARGET="${2:?--file needs a path}"; shift 2 ;;
    --author)  AUTHOR_LABEL="${2:?--author needs a value}"; shift 2 ;;
    --check)   MODE="check"; shift ;;
    --clear)   MODE="clear"; shift ;;
    --add)     MODE="add"; shift ;;
    --create)  MODE="create"; shift ;;
    --open)    MODE="open"; shift ;;
    --prepend) ADD_LOCATION="beginning"; shift ;;
    --padding) ADD_PADDING="${2:?--padding needs a value}"; shift 2 ;;
    --new-window) NEW_WINDOW="true"; shift ;;
    -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$TARGET" ] || die "missing --file <path>"
# Resolve to an absolute path. The parent directory must exist; the file itself
# need not (create makes a new one).
TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)" \
  || die "directory not found: $(dirname "$TARGET")"
ABS_TARGET="$TARGET_DIR/$(basename "$TARGET")"
# Mode-aware existence check: create requires the file NOT exist; all other modes
# require it to exist.
if [ "$MODE" = "create" ]; then
  [ -e "$ABS_TARGET" ] && die "file already exists (create won't overwrite): $ABS_TARGET"
else
  [ -f "$ABS_TARGET" ] || die "file not found: $ABS_TARGET"
fi

case "$ADD_PADDING" in line|sentence|paragraph) ;; *) die "--padding must be line|sentence|paragraph" ;; esac

# --- helpers ------------------------------------------------------------------
# A file is "authored" if its tail contains an iA annotation block:
#   <blank>\n---\nAnnotations: <range> SHA-256 <hash>\n...\n...
has_annotation_block() {
  tail -n 25 "$1" | grep -qE '^Annotations: [0-9]' && tail -n 25 "$1" | grep -qE '^(---|\.\.\.)$'
}

CONF="$SCRIPT_DIR/ia-attribute.locations.conf"
# Map $ABS_TARGET -> iA "Location: relpath"; sets LIB_PATH (empty if no match).
LIB_PATH=""
resolve_lib_path() {
  LIB_PATH=""
  [ -f "$CONF" ] || return 1
  local name dir rel best_len=-1
  while IFS='=' read -r name dir; do
    case "$name" in ''|'#'*) continue ;; esac
    dir="${dir%/}"
    case "$ABS_TARGET/" in
      "$dir"/*)
        if [ "${#dir}" -gt "$best_len" ]; then
          rel="${ABS_TARGET#"$dir"/}"
          LIB_PATH="$name: $rel"
          best_len="${#dir}"
        fi
        ;;
    esac
  done < "$CONF"
  [ -n "$LIB_PATH" ]
}

# --- check mode ---------------------------------------------------------------
# Reports whether AI edits to this file should be routed through iA attribution.
#   authored    (exit 0) — has an annotation block
#   in-location (exit 0) — no block yet, but lives in a configured iA Location
#   plain       (exit 1) — neither; edit normally
if [ "$MODE" = "check" ]; then
  if has_annotation_block "$ABS_TARGET"; then echo "authored"; exit 0; fi
  if resolve_lib_path; then echo "in-location"; exit 0; fi
  echo "plain"; exit 1
fi

# --- shared setup (patch + clear + add + create + open) -----------------------
enc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

# encode text with any trailing annotation block stripped (iA owns the block)
strip_and_encode() {
  NEW_TEXT="$1" python3 -c '
import os, re, urllib.parse, sys
text = os.environ["NEW_TEXT"]
text = re.sub(r"\n*\n---\nAnnotations:.*\Z", "", text, flags=re.S).rstrip("\n")
sys.stdout.write(urllib.parse.quote(text, safe=""))
'
}

# map filesystem path -> iA "Location: relpath" library path (every remaining mode)
[ -f "$CONF" ] || die "locations config not found: $CONF"
resolve_lib_path || die "no iA Location matches $ABS_TARGET (add it to $CONF and to iA Writer)"
ENC_PATH="$(enc "$LIB_PATH")"

# --- open mode ----------------------------------------------------------------
# Surface the document in iA Writer. Interface command — needs NO auth-token and
# does not modify the file.
if [ "$MODE" = "open" ]; then
  URL="ia-writer://x-callback-url/open?path=${ENC_PATH}"
  [ "$NEW_WINDOW" = "true" ] && URL="${URL}&new-window=true"
  open -g "$URL" || die "failed to invoke iA Writer (is it installed?)" 2
  echo "ok: opened in iA Writer ($LIB_PATH)"
  exit 0
fi

# resolve secret (required for all write-based modes: patch, clear, add, create)
ENV_FILE="${IA_WRITER_ENV:-$SCRIPT_DIR/secrets/ia-writer.env}"
[ -f "$ENV_FILE" ] || die "secret env not found: $ENV_FILE (set IA_WRITER_ENV)"
set -a; . "$ENV_FILE"; set +a
[ -n "${IA_WRITER_AUTH_TOKEN:-}" ] || die "IA_WRITER_AUTH_TOKEN missing in $ENV_FILE"

# --- clear mode ---------------------------------------------------------------
# Accept all current edits: re-write the existing prose via mode=replace with no
# author, resetting every span to owner-default and dropping all &AI / @human
# marks. No-op when there is no AI attribution to clear.
if [ "$MODE" = "clear" ]; then
  if ! grep -qE '^&' "$ABS_TARGET"; then
    echo "nothing to clear (no AI attribution) ($LIB_PATH)"
    exit 0
  fi
  ENC_TEXT="$(strip_and_encode "$(cat "$ABS_TARGET")")"
  [ -n "$ENC_TEXT" ] || die "file has no prose to preserve"
  open -g "ia-writer://x-callback-url/write?auth-token=${IA_WRITER_AUTH_TOKEN}&path=${ENC_PATH}&text=${ENC_TEXT}&mode=replace" \
    || die "failed to invoke iA Writer (is it installed?)"
  # wait for iA to rewrite the file without the AI author lines
  for _ in $(seq 1 40); do
    grep -qE '^&' "$ABS_TARGET" || break
    perl -e 'select(undef,undef,undef,0.25)'
  done
  if grep -qE '^&' "$ABS_TARGET"; then
    die "AI attribution still present after clear — is iA running and the file in a Location? (path: $LIB_PATH)" 2
  fi
  echo "ok: cleared AI attribution ($LIB_PATH)"
  exit 0
fi

# --- add mode -----------------------------------------------------------------
# Append (or prepend) a CHUNK of new content via mode=add, attributing the added
# span to &AUTHOR. Reads ONLY the chunk from stdin (not the whole document); iA
# inserts it and re-offsets the existing ranges.
if [ "$MODE" = "add" ]; then
  NEW_TEXT="$(cat)"
  [ -n "$NEW_TEXT" ] || die "empty chunk on stdin"
  ENC_TEXT="$(strip_and_encode "$NEW_TEXT")"
  [ -n "$ENC_TEXT" ] || die "chunk is empty after stripping annotation block"
  ENC_AUTHOR="$(enc "&$AUTHOR_LABEL")"
  PRE_SUM="$(shasum -a 256 "$ABS_TARGET" | awk '{print $1}')"
  URL="ia-writer://x-callback-url/write?auth-token=${IA_WRITER_AUTH_TOKEN}&path=${ENC_PATH}&text=${ENC_TEXT}&mode=add&add-location=${ADD_LOCATION}&add-padding=${ADD_PADDING}&author=${ENC_AUTHOR}"
  open -g "$URL" || die "failed to invoke iA Writer (is it installed?)"
  changed=0
  for _ in $(seq 1 40); do
    NOW_SUM="$(shasum -a 256 "$ABS_TARGET" | awk '{print $1}')"
    [ "$NOW_SUM" != "$PRE_SUM" ] && { changed=1; break; }
    perl -e 'select(undef,undef,undef,0.25)'
  done
  if [ "$changed" -ne 1 ]; then
    die "iA Writer did not modify the file — is iA running, the file in a Location, and the auth-token valid? (path: $LIB_PATH)" 2
  fi
  if grep -qE "^&$AUTHOR_LABEL: " "$ABS_TARGET"; then
    echo "ok: added content at $ADD_LOCATION, attributed to &$AUTHOR_LABEL  ($LIB_PATH)"
    exit 0
  else
    echo "warning: file changed but no '&$AUTHOR_LABEL' attribution found — verify authorship is enabled in iA Writer" >&2
    exit 3
  fi
fi

# --- create mode --------------------------------------------------------------
# Create a NEW file from the whole body on stdin via mode=create, attributing the
# entire document to &AUTHOR. iA's create never overwrites; we already verified
# the file does not exist.
if [ "$MODE" = "create" ]; then
  NEW_TEXT="$(cat)"
  [ -n "$NEW_TEXT" ] || die "empty body on stdin"
  ENC_TEXT="$(strip_and_encode "$NEW_TEXT")"
  [ -n "$ENC_TEXT" ] || die "body is empty after stripping annotation block"
  ENC_AUTHOR="$(enc "&$AUTHOR_LABEL")"
  URL="ia-writer://x-callback-url/write?auth-token=${IA_WRITER_AUTH_TOKEN}&path=${ENC_PATH}&text=${ENC_TEXT}&mode=create&author=${ENC_AUTHOR}"
  open -g "$URL" || die "failed to invoke iA Writer (is it installed?)"
  created=0
  for _ in $(seq 1 40); do
    [ -f "$ABS_TARGET" ] && { created=1; break; }
    perl -e 'select(undef,undef,undef,0.25)'
  done
  if [ "$created" -ne 1 ]; then
    die "iA Writer did not create the file — is iA running and the folder a Location? (path: $LIB_PATH)" 2
  fi
  if grep -qE "^&$AUTHOR_LABEL: " "$ABS_TARGET"; then
    echo "ok: created and attributed to &$AUTHOR_LABEL  ($LIB_PATH)"
    exit 0
  else
    echo "warning: file created but no '&$AUTHOR_LABEL' attribution found — verify authorship is enabled in iA Writer" >&2
    exit 3
  fi
fi

# --- patch mode ---------------------------------------------------------------
# read new prose from stdin, strip any trailing annotation block, percent-encode
# (read stdin in bash first; the python program is fed via -c so stdin stays free)
NEW_TEXT="$(cat)"
[ -n "$NEW_TEXT" ] || die "empty new text on stdin"
ENC_TEXT="$(strip_and_encode "$NEW_TEXT")"
[ -n "$ENC_TEXT" ] || die "new text is empty after stripping annotation block"

ENC_AUTHOR="$(enc "&$AUTHOR_LABEL")"   # the leading & marks AI in iA's annotations

# capture pre-state for verification
PRE_SUM="$(shasum -a 256 "$ABS_TARGET" | awk '{print $1}')"

# fire the patch (token only ever lives in this shell var + the open arg)
URL="ia-writer://x-callback-url/write?auth-token=${IA_WRITER_AUTH_TOKEN}&path=${ENC_PATH}&text=${ENC_TEXT}&mode=patch&author=${ENC_AUTHOR}"
open -g "$URL" || die "failed to invoke iA Writer (is it installed?)"

# verify: wait for the file to change, then confirm an &<author> range exists
changed=0
for _ in $(seq 1 40); do
  NOW_SUM="$(shasum -a 256 "$ABS_TARGET" | awk '{print $1}')"
  [ "$NOW_SUM" != "$PRE_SUM" ] && { changed=1; break; }
  perl -e 'select(undef,undef,undef,0.25)'
done

if [ "$changed" -ne 1 ]; then
  die "iA Writer did not modify the file — is iA running, the file in a Location, and the auth-token valid? (path: $LIB_PATH)" 2
fi

if grep -qE "^&$AUTHOR_LABEL: " "$ABS_TARGET"; then
  echo "ok: patched and attributed to &$AUTHOR_LABEL  ($LIB_PATH)"
  exit 0
else
  echo "warning: file changed but no '&$AUTHOR_LABEL' attribution found — verify authorship is enabled in iA Writer" >&2
  exit 3
fi
