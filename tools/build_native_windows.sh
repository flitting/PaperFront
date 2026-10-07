#!/usr/bin/env sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Optional path to a MinGW toolchain unpacked without root (its usr/bin directory).
if [ -n "${PAPER_FRONT_MINGW_BIN:-}" ]; then
    PATH="$PAPER_FRONT_MINGW_BIN:$PATH"
    export PATH
fi

if ! command -v x86_64-w64-mingw32-g++-posix >/dev/null 2>&1; then
    echo "Install g++-mingw-w64-x86-64-posix or set PAPER_FRONT_MINGW_BIN to its bin directory." >&2
    exit 1
fi

# MinGW emits .obj files, which Godot otherwise mistakes for 3D model assets.
# Mark the directory before CMake creates its first compiler-check object.
mkdir -p "$PROJECT_DIR/native/build-windows"
touch "$PROJECT_DIR/native/build-windows/.gdignore"

cmake -S "$PROJECT_DIR/native" -B "$PROJECT_DIR/native/build-windows" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$PROJECT_DIR/native/cmake/mingw-w64-x86_64.cmake" \
    -DGODOTCPP_USE_STATIC_CPP=ON
cmake --build "$PROJECT_DIR/native/build-windows" -j "${PAPER_FRONT_BUILD_JOBS:-4}"
