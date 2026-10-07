#!/usr/bin/env sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${PAPER_FRONT_MINGW_BIN:-}" ]; then
    PATH="$PAPER_FRONT_MINGW_BIN:$PATH"
    export PATH
fi

COMPILER=${PAPER_FRONT_MINGW_CC:-x86_64-w64-mingw32-gcc-posix}
RESOURCE_COMPILER=${PAPER_FRONT_MINGW_WINDRES:-x86_64-w64-mingw32-windres}
if ! command -v "$COMPILER" >/dev/null 2>&1 ||
   ! command -v "$RESOURCE_COMPILER" >/dev/null 2>&1; then
    echo "Install gcc-mingw-w64-x86-64-posix and binutils-mingw-w64-x86-64, or set PAPER_FRONT_MINGW_BIN." >&2
    exit 1
fi

OUTPUT=${1:-"$PROJECT_DIR/artifacts/windows_portable/staging/PaperFront.exe"}
BUILD_DIR="$PROJECT_DIR/artifacts/windows_portable/launcher-build"
mkdir -p "$BUILD_DIR" "$(dirname -- "$OUTPUT")"
convert -background none -density 192 "$PROJECT_DIR/assets/icon.svg" \
    -resize 256x256 "$BUILD_DIR/icon-256.png"
python3 - "$BUILD_DIR/icon-256.png" "$PROJECT_DIR/assets/icon.ico" <<'PY'
from PIL import Image
import sys
with Image.open(sys.argv[1]) as source:
    source.convert('RGBA').save(sys.argv[2], format='ICO',
        sizes=[(16,16), (24,24), (32,32), (48,48), (64,64), (128,128), (256,256)])
PY
"$RESOURCE_COMPILER" -I "$PROJECT_DIR/tools" -I "$PROJECT_DIR/assets" \
    --preprocessor="$(command -v "$COMPILER")" \
    --preprocessor-arg=-E --preprocessor-arg=-xc --preprocessor-arg=-DRC_INVOKED \
    "$PROJECT_DIR/tools/portable_windows_launcher.rc" "$BUILD_DIR/launcher.res.o"
"$COMPILER" -std=c11 -O2 -Wall -Wextra -Werror -municode -mwindows \
    -static -s "$PROJECT_DIR/tools/portable_windows_launcher.c" \
    "$BUILD_DIR/launcher.res.o" -o "$OUTPUT"
python3 - "$PROJECT_DIR" "$OUTPUT" "$(command -v "$COMPILER")" \
    "$(command -v "$RESOURCE_COMPILER")" <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import subprocess
import sys

root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]).resolve()
compiler, resource_compiler = sys.argv[3:5]
objdump = str(pathlib.Path(resource_compiler).with_name('x86_64-w64-mingw32-objdump'))
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
imports = re.findall(r'DLL Name:\s+(\S+)', subprocess.check_output(
    [objdump, '-p', str(output)], text=True))
sources = {}
for name in ('portable_windows_launcher.c', 'portable_windows_launcher.rc',
             'portable_windows_launcher.manifest', 'build_portable_launcher.sh'):
    source = root / 'tools' / name
    sources['tools/' + name] = digest(source)
sources['assets/icon.svg'] = digest(root / 'assets/icon.svg')
sources['assets/icon.ico'] = digest(root / 'assets/icon.ico')
report = {
    'built_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'sources_sha256': sources,
    'compiler': {
        'path': compiler,
        'version': subprocess.check_output([compiler, '--version'], text=True).splitlines()[0],
        'target': subprocess.check_output([compiler, '-dumpmachine'], text=True).strip(),
    },
    'resource_compiler': resource_compiler,
    'compile_and_link_flags': ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                               '-municode', '-mwindows', '-static', '-s'],
    'executable': {'path': str(output), 'sha256': digest(output),
                   'bytes': output.stat().st_size, 'imports': imports},
    'portable_contract': {
        'entrypoint': 'PaperFront.exe',
        'child_runtime': 'bin/PaperFrontRuntime.exe',
        'child_working_directory': '<extracted folder>',
        'child_environment': {
            'APPDATA': '<extracted folder>',
            'LOCALAPPDATA': '<extracted folder>/user_data/cache',
            'TEMP': '<extracted folder>/user_data/tmp',
            'TMP': '<extracted folder>/user_data/tmp',
            'PAPER_FRONT_PORTABLE_ROOT': '<extracted folder>',
        },
        'godot_feature': 'portable',
        'project_settings': {
            'application/config/use_custom_user_dir.portable': True,
            'application/config/custom_user_dir_name.portable': 'user_data',
            'debug/file_logging/enable_file_logging.portable': False,
        },
        'user_data': '<extracted folder>/user_data',
        'log_file_argument': '--log-file <extracted folder>/user_data/logs/godot.log',
        'argument_forwarding': 'Original UTF-16 argument string appended unchanged',
        'system_environment_modified': False,
    },
    'engine_references': [
        'https://github.com/godotengine/godot/blob/4.6.2-stable/platform/windows/os_windows.cpp',
        'https://github.com/godotengine/godot/blob/4.6.2-stable/core/os/os.cpp',
        'https://github.com/godotengine/godot/blob/4.6.2-stable/main/main.cpp',
        'https://docs.godotengine.org/en/4.6/tutorials/ui/creating_applications.html',
    ],
}
report_path = root / 'artifacts/windows_portable/portable_launcher_build.json'
report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
PY
echo "Built portable Windows launcher: $OUTPUT"
