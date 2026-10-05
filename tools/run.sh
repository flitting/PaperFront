#!/usr/bin/env sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Compatibility entry; the root launcher is the only source of launch policy.
exec "$PROJECT_DIR/run.sh" "$@"
