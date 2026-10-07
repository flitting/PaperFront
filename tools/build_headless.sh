#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:-"$PROJECT_DIR/artifacts/headless/PaperFrontHeadless.x86_64"}
mkdir -p "$(dirname -- "$OUTPUT")"
"${PAPER_FRONT_GODOT:-godot}" --headless --path "$PROJECT_DIR" --export-release "Linux Headless" "$OUTPUT"
printf 'Built logic-only executable: %s\n' "$OUTPUT"
