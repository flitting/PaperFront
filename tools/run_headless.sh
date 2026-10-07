#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "${PAPER_FRONT_GODOT:-godot}" --headless --audio-driver Dummy --path "$PROJECT_DIR" res://headless.tscn -- "$@"
