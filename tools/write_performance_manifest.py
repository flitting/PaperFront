#!/usr/bin/env python3
"""Record the exact runtime source/assets before an isolated performance build."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATED = ROOT / 'data/performance_build_manifest.json'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def capture():
    paths = [ROOT / p for p in ('project.godot', 'main.tscn', 'export_presets.cfg', 'native/CMakeLists.txt', 'native/build_profile.json', 'native/DEPENDENCY_VERSION.txt', 'native/vendor/binding_generator.py', 'native/patches/container-assignment.patch')]
    for folder in ('scripts', 'data', 'assets', 'native/src'):
        paths.extend(p for p in (ROOT / folder).rglob('*') if p.is_file() and p != GENERATED and not p.name.endswith('.uid') and p.name != '.gdignore')
    files = {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}
    identity = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return {'format': 1, 'runtime_identity': identity, 'files': files}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verify', action='store_true', help='Verify sources are unchanged after export; do not write files.')
    args = parser.parse_args()
    current = capture()
    if args.verify:
        expected = json.loads(args.output.read_text())
        if current != expected:
            raise SystemExit('Runtime sources changed during export; discard this build and export again.')
    else:
        content = json.dumps(current, indent=2) + '\n'
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
        GENERATED.write_text(content)
    print('Runtime identity:', current['runtime_identity'])

if __name__ == '__main__':
    main()
