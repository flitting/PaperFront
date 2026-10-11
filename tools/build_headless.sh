#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:-"$PROJECT_DIR/artifacts/headless/PaperFrontHeadless.x86_64"}
mkdir -p "$(dirname -- "$OUTPUT")"
python3 "$PROJECT_DIR/tools/headless_export_manifest.py"
paper_headless_build_log=$(mktemp /tmp/paper-headless-build.XXXXXX)
trap 'rm -f "$paper_headless_build_log"' EXIT
paper_headless_status=0
"${PAPER_FRONT_GODOT:-godot}" --headless --path "$PROJECT_DIR" --export-release "Linux Headless" "$OUTPUT" >"$paper_headless_build_log" 2>&1 || paper_headless_status=$?
cat "$paper_headless_build_log"
if [ "$paper_headless_status" -ne 0 ] || grep -Eq 'SCRIPT ERROR:|^ERROR:' "$paper_headless_build_log"; then exit 1; fi
"$OUTPUT" --headless --audio-driver Dummy -- --help >"$paper_headless_build_log" 2>&1 || paper_headless_status=$?
cat "$paper_headless_build_log"
if [ "$paper_headless_status" -ne 0 ] || grep -Eq 'SCRIPT ERROR:|^ERROR:' "$paper_headless_build_log"; then exit 1; fi
python3 "$PROJECT_DIR/tools/headless_export_manifest.py" --binary "$OUTPUT"
printf 'Built logic-only executable: %s\n' "$OUTPUT"
