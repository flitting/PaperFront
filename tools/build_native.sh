#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake -S "$PROJECT_DIR/native" -B "$PROJECT_DIR/native/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$PROJECT_DIR/native/build" -j "${PAPER_FRONT_BUILD_JOBS:-4}"
