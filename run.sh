#!/usr/bin/env sh
# Canonical project launcher: always run the current source tree.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GODOT_BIN=${PAPER_FRONT_GODOT:-godot}
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    printf '%s\n' '未找到 Godot。请安装 Godot 4.6.2，或通过 PAPER_FRONT_GODOT 指定可执行程序。' >&2
    exit 1
fi
# Import on first use and whenever project resources change. A previous
# exported binary or stale audio import can never shadow current sources.
IMPORT_STAMP="$PROJECT_DIR/.godot/paper_front_imported.stamp"
IMPORT_NEEDED=1
if [ -f "$IMPORT_STAMP" ]; then
    if [ -z "$(find "$PROJECT_DIR/assets" "$PROJECT_DIR/scripts" "$PROJECT_DIR/data" -type f -newer "$IMPORT_STAMP" -print -quit)" ] && [ ! "$PROJECT_DIR/project.godot" -nt "$IMPORT_STAMP" ]; then
        IMPORT_NEEDED=0
    fi
fi
if [ "$IMPORT_NEEDED" = 1 ]; then
    "$GODOT_BIN" --headless --editor --import --path "$PROJECT_DIR"
    touch "$IMPORT_STAMP"
fi
exec "$GODOT_BIN" --path "$PROJECT_DIR" "$@"
