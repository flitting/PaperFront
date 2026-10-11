#!/usr/bin/env bash
# Install the exact official engine and templates used by the release build.
set -euo pipefail
paper_godot_root="${1:?Usage: install_ci_godot.sh INSTALL_DIRECTORY}"
mkdir -p "$paper_godot_root"
paper_godot_root=$(cd "$paper_godot_root" && pwd)
paper_godot_url=https://github.com/godotengine/godot-builds/releases/download/4.6.2-stable
curl --fail --location --retry 3 "$paper_godot_url/Godot_v4.6.2-stable_linux.x86_64.zip" -o "$paper_godot_root/engine.zip"
curl --fail --location --retry 3 "$paper_godot_url/Godot_v4.6.2-stable_export_templates.tpz" -o "$paper_godot_root/templates.tpz"
(
    cd "$paper_godot_root"
    # SHA-256 digests published with these exact official release assets.
    printf '%s\n' \
      '30e6b6d141f0cd5bebd629ad1d0ef1324e60091bb20662d026b402ba58c59937  engine.zip' \
      '942366dc4e27e7686a99da4d3cfb1b8ae8d3eb9444f6d8217eef16245b599ef2  templates.tpz' | sha256sum --check
    unzip -q engine.zip
    unzip -q templates.tpz
    mv Godot_v4.6.2-stable_linux.x86_64 godot
    chmod +x godot
)
paper_template_path="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.2.stable"
mkdir -p "$paper_template_path"
cp "$paper_godot_root/templates/"* "$paper_template_path/"
"$paper_godot_root/godot" --version
