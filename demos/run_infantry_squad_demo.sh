#!/usr/bin/env sh
set -eu
TASK_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "${PAPER_FRONT_GODOT:-godot}" --path "$TASK_ROOT" --script res://demos/infantry_squad_demo.gd -- "$@"
