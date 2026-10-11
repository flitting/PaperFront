#!/usr/bin/env python3
"""Freeze the real logic dependency closure for the dedicated-server preset.

Godot's scene-only export does not recursively include this project's GDScript
dependencies reliably. Lazy render-only load() calls intentionally stay out.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def code_masks(source: str) -> tuple[str, str]:
    """Return comment-free text and text with strings/comments masked equally."""
    comments = list(source)
    code = list(source)
    i = 0
    while i < len(source):
        if source[i] == "#":
            end = source.find("\n", i)
            end = len(source) if end < 0 else end
            for pos in range(i, end): comments[pos] = code[pos] = " "
            i = end
        elif source[i] in "\"'":
            quote = source[i]
            delimiter = quote * 3 if source.startswith(quote * 3, i) else quote
            end = i + len(delimiter)
            while end < len(source):
                if source[end] == "\\": end += 2
                elif source.startswith(delimiter, end):
                    end += len(delimiter)
                    break
                else: end += 1
            for pos in range(i, min(end, len(source))): code[pos] = " " if source[pos] != "\n" else "\n"
            i = end
        else: i += 1
    return "".join(comments), "".join(code)


def dependency_paths() -> list[str]:
    classes = {}
    for path in sorted((ROOT / "scripts").glob("*.gd")):
        _, code = code_masks(path.read_text())
        match = re.search(r"\bclass_name\s+(\w+)", code)
        if match: classes[match[1]] = path.relative_to(ROOT).as_posix()
    pending = ["scripts/headless_main.gd"]
    included = {"headless.tscn"}
    while pending:
        relative = pending.pop()
        if relative in included: continue
        path = ROOT / relative
        if not path.is_file(): raise ValueError(f"Missing logic dependency: {relative}")
        included.add(relative)
        if path.suffix != ".gd": continue
        comments, code = code_masks(path.read_text())
        for match in re.finditer(r'''\bpreload\s*\(\s*["']res://([^"']+)["']\s*\)''', comments):
            if code[match.start():match.start() + 7] == "preload": pending.append(match[1])
        identifiers = set(re.findall(r"\b\w+\b", code))
        pending.extend(relative for name, relative in classes.items() if name in identifiers)
    return sorted(included)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    paths = dependency_paths()
    preset_path = ROOT / "export_presets.cfg"
    text = preset_path.read_text()
    match = re.search(r'(\[preset\.\d+\]\n)(?:(?!\n\[).)*?name="Linux Headless"(?:(?!\n\[).)*', text, re.S)
    if not match: raise ValueError("Linux Headless export preset was not found")
    section = match[0]
    selected = "export_files=PackedStringArray(" + ", ".join(json.dumps("res://" + p) for p in paths) + ")"
    replacement, count = re.subn(r"export_files=PackedStringArray\([^\n]*\)", selected, section)
    if count != 1: raise ValueError("Headless preset needs exactly one export_files setting")
    updated = text[:match.start()] + replacement + text[match.end():]
    if updated != text: preset_path.write_text(updated)
    tracked = paths + ["data/rules.json", "scripts/faction_trait_text.json", "project.godot", "export_presets.cfg"]
    report = {"schema_version":1, "entrypoint":"headless.tscn", "selected_resources":paths,
              "source_sha256":{p:hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in tracked},
              "lazy_render_dependencies_included":False}
    if args.binary:
        binary = args.binary.resolve()
        report["binary"] = {"path":str(binary), "bytes":binary.stat().st_size, "sha256":hashlib.sha256(binary.read_bytes()).hexdigest()}
    directory = ROOT / "artifacts/headless"
    directory.mkdir(exist_ok=True, parents=True)
    (directory / "build_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Headless logic closure: {len(paths)} resources")


if __name__ == "__main__": main()
