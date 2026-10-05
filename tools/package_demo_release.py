#!/usr/bin/env python3
"""Package a caller-validated Linux Demo. Never export, run, or claim play testing."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import tarfile
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
MARKER = ".paper-front-demo-package"
FORMAT = "paper-front-demo-package-v1\n"
NAME_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\Z")
PACK_MAGIC = b"GDPC"


class PublicationRecoveryError(OSError):
    """Rollback was incomplete; the temporary directory must be retained."""


def require_file(path: Path) -> Path:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Required regular file is missing (symlinks rejected): {path}")
    return path


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with require_file(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def read_exact(handle, count: int) -> bytes:
    data = handle.read(count)
    if len(data) != count:
        raise ValueError("Truncated PCK or ELF data")
    return data


def check_elf(path: Path) -> None:
    with require_file(path).open("rb") as handle:
        header = read_exact(handle, 64)
    if header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != 62:
        raise ValueError(f"Expected Linux x86_64 ELF: {path}")


def pck_start(handle, length: int) -> tuple[int, int]:
    """Read standalone/trailer/ELF-section locations used by Godot 4.6.2."""
    handle.seek(0)
    header = read_exact(handle, min(length, 64))
    if header[:4] == PACK_MAGIC:
        return 0, length
    if length >= 12:
        handle.seek(length - 12)
        tail = read_exact(handle, 12)
        if tail[8:] == PACK_MAGIC:
            start = length - 12 - struct.unpack_from("<Q", tail)[0]
            if start < 0:
                raise ValueError("Invalid embedded PCK trailer")
            handle.seek(start)
            if read_exact(handle, 4) == PACK_MAGIC:
                return start, length - 12
    # Linux exports may locate their PCK in a named ELF section without a trailer.
    if header[:6] == b"\x7fELF\x02\x01" and len(header) == 64:
        table = struct.unpack_from("<Q", header, 40)[0]
        entry_size, count, names_index = struct.unpack_from("<HHH", header, 58)
        if entry_size >= 64 and count and names_index < count and table + entry_size * count <= length:
            handle.seek(table + names_index * entry_size)
            names_header = read_exact(handle, 64)
            names_offset, names_size = struct.unpack_from("<QQ", names_header, 24)
            if names_size > 1024 * 1024 or names_offset + names_size > length:
                raise ValueError("Invalid ELF section name table")
            handle.seek(names_offset)
            names = read_exact(handle, names_size)
            for index in range(count):
                handle.seek(table + index * entry_size)
                section = read_exact(handle, 64)
                name_index = struct.unpack_from("<I", section)[0]
                name = names[name_index:].split(b"\0", 1)[0]
                if name == b"pck":
                    offset, size = struct.unpack_from("<QQ", section, 24)
                    for padding in range(8):
                        if offset + padding + 4 > length:
                            break
                        handle.seek(offset + padding)
                        if read_exact(handle, 4) == PACK_MAGIC:
                            return offset + padding, min(length, offset + size)
    raise ValueError("No readable embedded/standalone PCK found; supply --pck if external")


def pck_entries(path: Path) -> tuple[dict, list[dict]]:
    """Parse unencrypted full v2/v3 directories, without starting Godot."""
    length = require_file(path).stat().st_size
    with path.open("rb") as handle:
        start, end = pck_start(handle, length)
        handle.seek(start)
        header = read_exact(handle, 40)
        version, major, minor, patch, flags = struct.unpack_from("<IIIII", header, 4)
        if version not in (2, 3) or flags & ~2:
            raise ValueError("Only unencrypted, non-sparse full Godot PCK v2/v3 can be audited")
        base = struct.unpack_from("<Q", header, 24)[0]
        if version == 3 or flags & 2:
            base += start
        directory = start + (struct.unpack_from("<Q", header, 32)[0] if version == 3 else 96)
        if not start + 40 <= directory < end:
            raise ValueError("PCK directory is outside the pack")
        handle.seek(directory)
        count = struct.unpack("<I", read_exact(handle, 4))[0]
        if count > 1000000:
            raise ValueError("Implausible PCK file count")
        entries, seen = [], set()
        for _ in range(count):
            name_length = struct.unpack("<I", read_exact(handle, 4))[0]
            if not 0 < name_length <= 65536:
                raise ValueError("Invalid PCK path length")
            name = read_exact(handle, name_length).rstrip(b"\0").decode("utf-8")
            normalized = name.removeprefix("res://")
            if "\0" in name or "\\" in name or normalized.startswith("/") or ".." in PurePosixPath(normalized).parts or normalized in seen:
                raise ValueError(f"Unsafe or duplicate PCK path: {name!r}")
            seen.add(normalized)
            offset, size = struct.unpack("<QQ", read_exact(handle, 16))
            md5 = read_exact(handle, 16).hex()
            file_flags = struct.unpack("<I", read_exact(handle, 4))[0]
            if file_flags or base + offset < start or base + offset + size > end or handle.tell() > end:
                raise ValueError(f"Encrypted, patch, or out-of-bounds PCK entry: {name}")
            entries.append({"path": normalized, "offset": base + offset, "bytes": size, "md5": md5})
    return {"pack_format": version, "engine_version": f"{major}.{minor}.{patch}", "entries": count}, entries


def denied_resource_names() -> tuple[set[str], set[str]]:
    voices = {p.name.lower() for p in (PROJECT / "assets/audio/voices").glob("*") if p.suffix.lower() in {".wav", ".ogg", ".mp3"}}
    manifest = PROJECT / "assets/audio/voices/manifest.json"
    if manifest.is_file():
        for clip in json.loads(manifest.read_text(encoding="utf-8")).get("clips", []):
            if clip.get("path"):
                voices.add(PurePosixPath(clip["path"]).name.lower())
    references = set()
    for directory in (PROJECT / "docs", PROJECT / "assets/map_design_v6"):
        for item in directory.rglob("*"):
            if item.is_file() and item.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".svg", ".glb", ".wav", ".mp3", ".ogg"}:
                references.add(item.name.lower())
    return voices, references


def audit_pck(path: Path) -> dict:
    summary, entries = pck_entries(path)
    voices, references = denied_resource_names()
    forbidden = []
    with path.open("rb") as handle:
        for entry in entries:
            name = entry["path"].lower()
            basename = PurePosixPath(name).name
            reason = None
            if name.startswith("assets/audio/voices/") and basename != "manifest.json":
                reason = "old speech audio/import/remap"
            elif name.startswith(("docs/", "tests/", "tools/", "artifacts/", "assets/map_design_v6/")):
                reason = "developer evidence/reference resource"
            elif (name.startswith("data/golden_visual") and name.endswith(".json")) or name in {
                "data/faction_expansion.json", "data/faction_expansion_contours.json"
            }:
                reason = "developer fixture or merged source data"
            elif name.startswith(".godot/imported/"):
                if any(basename.startswith(voice + "-") or basename.startswith(voice + ".") for voice in voices):
                    reason = "old speech imported payload"
                elif any(basename.startswith(reference + "-") for reference in references):
                    reason = "reference/developer image imported payload"
            # Import/remap metadata can retain a forbidden export mapping even
            # when no direct source path is listed in the PCK directory.
            if not reason and name.endswith((".import", ".remap")):
                if entry["bytes"] > 1024 * 1024:
                    raise ValueError(f"Unexpectedly large import mapping: {name}")
                handle.seek(entry["offset"])
                mapping = read_exact(handle, entry["bytes"]).decode("utf-8", errors="replace").lower()
                if "res://assets/audio/voices/" in mapping or any("/" + voice + "-" in mapping for voice in voices):
                    reason = "export mapping points to old speech audio"
            if reason:
                forbidden.append({"path": entry["path"], "reason": reason})
    summary.update({"sha256": digest(path), "forbidden_entries": forbidden,
                    "scope": "PCK directory and import/remap mappings; not gameplay or performance validation"})
    return summary


def copy_file(source: Path, target: Path, executable: bool = False) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(require_file(source), target)
    target.chmod(0o755 if executable else 0o644)


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    path.chmod(0o644)


def original_records(stage: Path) -> None:
    copy_file(PROJECT / "assets/audio/README_demo_original.md", stage / "PROVENANCE/README_demo_original.md")
    for category, field in (("music", "tracks"), ("radio", "clips")):
        source = PROJECT / f"assets/audio/{category}/manifest.json"
        data = json.loads(require_file(source).read_text(encoding="utf-8"))
        if data.get("license") != {"music": "CC0-1.0", "radio": "GPL-3.0-or-later"}[category] or not data.get(field):
            raise ValueError(f"Original audio license/entries missing: {source}")
        generator = PROJECT / data["generator"]
        if digest(generator) != data.get("generator_sha256"):
            raise ValueError(f"Audio generator changed since provenance was written: {generator}")
        for entry in data[field]:
            asset = PROJECT / entry["path"].removeprefix("res://")
            if digest(asset) != entry.get("sha256"):
                raise ValueError(f"Original audio differs from provenance: {asset}")
        copy_file(source, stage / f"PROVENANCE/audio_{category}_manifest.json")
    # Conservative GPL radio distribution includes its complete corresponding
    # source alongside the independently licensed engine and game assets.
    kit = PROJECT / "tools/source_assets/espeak-ng"
    records = json.loads(require_file(kit / "source_kit_manifest.json").read_text(encoding="utf-8"))
    downloads = json.loads(require_file(kit / "source_download_manifest.json").read_text(encoding="utf-8"))
    for entry in [downloads["dsc"], *downloads["archives"]]:
        source = require_file(kit / entry["file"])
        if digest(source) != entry["sha256"] or source.stat().st_size != entry["bytes"]:
            raise ValueError(f"Corresponding source archive changed: {source}")
    for key in ("generator", "generated_audio_manifest"):
        entry = records[key]
        if digest(kit / entry["file"]) != entry["sha256"]:
            raise ValueError(f"Corresponding source record changed: {key}")
    if digest(kit / records["generator"]["file"]) != digest(PROJECT / "tools/generate_demo_radio.py"):
        raise ValueError("Radio corresponding generator differs from the current generator")
    if digest(kit / records["generated_audio_manifest"]["file"]) != digest(PROJECT / "assets/audio/radio/manifest.json"):
        raise ValueError("Radio corresponding manifest differs from the current PCM manifest")
    for source in sorted(kit.rglob("*")):
        if source.is_file() and source.name != ".gdignore":
            copy_file(source, stage / "SOURCE/espeak-ng" / source.relative_to(kit))
    for source in sorted((PROJECT / "assets/audio/licenses").glob("*.txt")):
        copy_file(source, stage / "LICENSES" / source.name)
    # Preserve source records for effects without distributing old supplier speech metadata.
    effects_manifest = json.loads((PROJECT / "assets/audio/voices/manifest.json").read_text(encoding="utf-8"))
    effects = []
    for effect in effects_manifest.get("effects", []):
        if effect.get("license") != "CC0-1.0":
            raise ValueError("An effect has no explicit original CC0 record")
        effects.append({**effect, "sha256": digest(PROJECT / effect["path"].removeprefix("res://"))})
    generated_files = [{"path": p.relative_to(PROJECT).as_posix(), "sha256": digest(p)}
                       for p in sorted((PROJECT / "assets/audio").glob("*.wav"))]
    write_json(stage / "PROVENANCE/original_effects.json", {
        "license": "CC0-1.0", "source_record": "LICENSES/PROJECT_ASSETS.md",
        "generators": [{"path": str(p.relative_to(PROJECT)), "sha256": digest(p)} for p in
                       (PROJECT / "tools/generate_audio.py", PROJECT / "tools/generate_unit_voices.py")],
        "project_effects": generated_files, "aviation_effects": effects,
        "note": "Generator source stays in the project; no online speech audio is included."})


def start_here(binary: str) -> str:
    return f"""纸境战线 · Paper Front Demo / Linux x86_64

运行 / Launch: ./start.sh
也可直接执行 / Direct launch: ./{binary}
解压后保留整个目录；无需安装 Godot。此构建需要 glibc 2.38 或更新版本、支持 Vulkan 的显卡与驱动。
Keep this folder together. Godot is bundled. This build requires glibc 2.38+ and a Vulkan-capable GPU/driver.

先选择「战役 · 无字桥补给线」学习供电、采矿、建造与运输。
「开始战局」选择地图、阵营与 AI；「设置」调整声音和画面。
Use the campaign tutorial first, or Start Battle for a skirmish. UI and subtitles are Chinese.
Settings contains master, music, effects and response volume controls.

左键选择/拖框；右键移动/攻击。WASD 平移镜头，滚轮缩放。
Z + 左键攻击移动，X 停止，空格定位所选单位。
Select with left click/drag; right click moves/attacks. WASD pans; wheel zooms.
Z then left click: attack-move. X: stop. Space: focus selection.
选中总部建造，选中兵营/工厂/机场/船坞生产。完成建筑后再次点卡片放置。
Select HQ to build; select production buildings to train units. Click completed cards to place.
装载菜单选择乘员；卸载菜单选择地点。U 指定卸载点，L 指定运输机降落，B 返回机场。
Load selects passengers; Unload selects a location. U: unload. L: plane landing. B: return to airfield.
P 暂停/继续。F5 保存，F9 读取；Esc 菜单不暂停，可返回主菜单；胜败界面可重开。
P pauses/resumes. F5 saves; F9 loads. Esc opens the menu without pausing. Results offers restart/home.

验收状态、实测条件与已知问题见 VALIDATION/。打包本身不执行游玩或性能验收。
Validation conditions and known issues are in VALIDATION/. Packaging performs no play test.
署名和许可见 CREDITS.md、LICENSES/；原创生成记录见 PROVENANCE/。
Credits/licenses: CREDITS.md and LICENSES/. Original asset records: PROVENANCE/.
完整性校验 / Integrity check: sha256sum -c BUILD.sha256
"""


def prepare(args, stage: Path, audit: dict) -> None:
    source = args.staging_dir.resolve()
    binary = require_file(source / args.binary)
    stage.mkdir()
    copy_file(binary, stage / args.binary, executable=True)
    inputs = {"binary": digest(binary), "manifest": digest(args.manifest)}
    if (source / "manifest.json").is_file() and digest(source / "manifest.json") != inputs["manifest"]:
        raise ValueError("Supplied manifest differs from staging manifest.json")
    for library in args.native_library:
        library = library.resolve()
        if library.suffix != ".so" or not NAME_PATTERN.fullmatch(library.name):
            raise ValueError(f"Expected a single safe .so filename: {library.name}")
        check_elf(library)
        staged_library = require_file(source / library.name)
        if digest(library) != digest(staged_library):
            raise ValueError(f"Native library differs from validated staging: {library.name}")
        copy_file(staged_library, stage / library.name, executable=True)
        inputs[library.name] = digest(staged_library)
    if args.pck:
        pack = args.pck.resolve()
        if pack.name != Path(args.binary).with_suffix(".pck").name:
            raise ValueError("External PCK must share the executable's filename stem for normal launch")
        staged_pack = require_file(source / pack.name)
        if digest(pack) != digest(staged_pack):
            raise ValueError("External PCK differs from staging")
        copy_file(staged_pack, stage / pack.name)
        inputs[pack.name] = digest(staged_pack)
    copy_file(args.manifest, stage / "PROVENANCE/runtime_manifest.json")
    reports = []
    for index, report in enumerate(args.validation_report, 1):
        if report.suffix.lower() not in {".md", ".txt", ".json", ".log", ".result"} or not require_file(report).stat().st_size:
            raise ValueError(f"Expected a nonempty text/JSON validation report: {report}")
        target = f"VALIDATION/{index:02d}_{report.name}"
        copy_file(report, stage / target)
        reports.append({"path": target, "sha256": digest(report)})
    licenses = args.licenses_dir.resolve()
    for origin, target in (
        (licenses / "GODOT_LICENSE.txt", "GODOT_LICENSE.txt"),
        (licenses / "GODOT_THIRD_PARTY.json", "GODOT_THIRD_PARTY.json"),
        (PROJECT / "assets/LICENSE.md", "PROJECT_ASSETS.md"),
        (PROJECT / "assets/fonts/LICENSE.txt", "FONT_LICENSE.txt"),
        (PROJECT / "assets/native/GODOT_CPP_LICENSE.md", "GODOT_CPP_LICENSE.md"),
        (PROJECT / "assets/native/GNU_RUNTIME_LICENSES.txt", "GNU_RUNTIME_LICENSES.txt"),
        (PROJECT / "assets/creator_hand/MAKEHUMAN_LICENSE.md", "MAKEHUMAN_CC0.md"),
        (PROJECT / "assets/creator_hand/MAKEHUMAN_LICENSE_ASSETS.md", "CC0_1.0_UNIVERSAL.txt"),
        (PROJECT / "tools/source_assets/makehuman/LICENSE.md", "MAKEHUMAN_LICENSE_SCOPE.md"),
    ):
        copy_file(origin, stage / "LICENSES" / target)
    copy_file(PROJECT / "assets/creator_hand/README.md", stage / "PROVENANCE/creator_hand_README.md")
    copy_file(PROJECT / "assets/creator_hand/source_provenance.json", stage / "PROVENANCE/creator_hand_source.json")
    copy_file(PROJECT / "assets/native/compiler_runtime_provenance.json", stage / "PROVENANCE/compiler_runtime_source.json")
    copy_file(PROJECT / "docs/demo_credits.md", stage / "CREDITS.md")
    original_records(stage)
    (stage / "START_HERE.txt").write_text(start_here(args.binary), encoding="utf-8")
    (stage / "start.sh").write_text('#!/bin/sh\nset -eu\ncd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec "./' + args.binary + '" "$@"\n', encoding="utf-8")
    (stage / "start.sh").chmod(0o755)
    (stage / MARKER).write_text(FORMAT, encoding="utf-8")
    write_json(stage / "PROVENANCE/pck_audit.json", audit)
    write_json(stage / "PROVENANCE/package_inputs.json", {
        "format": 1, "inputs_sha256": inputs, "reports": reports,
        "validation": "Reports supplied by caller; packager did not export, execute or validate gameplay/performance.",
        "contents_policy": "Runtime whitelist plus current reports, credits, licenses and provenance; no loose source, saves, screenshots or references."})
    lines = [f"{digest(path)}  {path.relative_to(stage).as_posix()}\n"
             for path in sorted(stage.rglob("*")) if path.is_file()]
    (stage / "BUILD.sha256").write_text("".join(lines), encoding="utf-8")


def archive(stage: Path, target: Path, name: str) -> None:
    with target.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as bundle:
            for path in [stage, *sorted(stage.rglob("*"))]:
                info = bundle.gettarinfo(str(path), arcname=name if path == stage else f"{name}/{path.relative_to(stage).as_posix()}")
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.pax_headers = {}
                info.mode = 0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644
                if path.is_file():
                    with path.open("rb") as handle:
                        bundle.addfile(info, handle)
                else:
                    bundle.addfile(info)


def publish(stage: Path, packed: Path, checksum: Path, destination: Path) -> None:
    """Use same-filesystem renames, keeping old outputs available for rollback."""
    targets = [(stage, destination), (packed, destination.with_name(destination.name + ".tar.gz")),
               (checksum, destination.with_name(destination.name + ".tar.gz.sha256"))]
    backups, installed = [], []
    try:
        for index, (_, target) in enumerate(targets):
            if target.exists():
                backup = stage.parent / f"previous-{index}"
                # Register the intent before the atomic rename: Python can
                # receive an interrupt after the OS moved the only old copy.
                backups.append((backup, target))
                os.replace(target, backup)
        for source, target in targets:
            installed.append(target)
            os.replace(source, target)
    except BaseException as original_error:
        recovery_errors = []
        for target in reversed(installed):
            try:
                if target.is_dir():
                    shutil.rmtree(target)
                else:
                    target.unlink(missing_ok=True)
            except BaseException as error:
                recovery_errors.append(str(error) or type(error).__name__)
        for backup, target in reversed(backups):
            try:
                if backup.exists():
                    os.replace(backup, target)
            except BaseException as error:
                recovery_errors.append(str(error) or type(error).__name__)
        if recovery_errors:
            raise PublicationRecoveryError(
                f"Publication failed and rollback needs manual recovery; preserved backup directory: {stage.parent}; "
                + "; ".join(recovery_errors)) from original_error
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-pck", type=Path, help="Read-only PCK audit; print JSON, fail if forbidden resources exist")
    parser.add_argument("--staging-dir", "--binary-dir", type=Path)
    parser.add_argument("--binary", default="PaperFront.x86_64")
    parser.add_argument("--native-library", action="append", type=Path)
    parser.add_argument("--pck", type=Path, help="External PCK, if the binary does not embed its PCK")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--validation-report", action="append", type=Path)
    parser.add_argument("--licenses-dir", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--name", default="PaperFront-Demo-linux-x86_64")
    args = parser.parse_args()
    try:
        if args.inspect_pck:
            audit = audit_pck(args.inspect_pck)
            print(json.dumps(audit, ensure_ascii=False, indent=2))
            return 1 if audit["forbidden_entries"] else 0
        for field in ("staging_dir", "native_library", "manifest", "validation_report", "licenses_dir", "output_dir"):
            if not getattr(args, field):
                raise ValueError(f"Required packaging argument: --{field.replace('_', '-')}")
        if not NAME_PATTERN.fullmatch(args.name) or not NAME_PATTERN.fullmatch(args.binary):
            raise ValueError("--name and --binary must be single safe filenames")
        source, output = args.staging_dir.resolve(), args.output_dir.resolve()
        destination = output / args.name
        if not source.is_dir() or output == source or source in output.parents or destination == source or destination in source.parents:
            raise ValueError("Output and input staging must be separate directories")
        for protected in (PROJECT / "artifacts/linux", PROJECT / "artifacts/PaperFront-linux-x86_64"):
            if destination == protected or protected in destination.parents:
                raise ValueError("Legacy v6 release paths are protected; choose a separate Demo path")
        tar_path = output / f"{args.name}.tar.gz"
        checksum_path = output / f"{args.name}.tar.gz.sha256"
        if destination.is_symlink() or tar_path.is_symlink() or checksum_path.is_symlink():
            raise ValueError("Output symlinks are refused")
        for target in (tar_path, checksum_path):
            if target.exists() and not target.is_file():
                raise ValueError(f"Refusing to overwrite a non-file archive/checksum path: {target}")
        if destination.exists():
            marker = destination / MARKER
            if not destination.is_dir() or not marker.is_file() or marker.is_symlink() or marker.read_text(encoding="utf-8") != FORMAT:
                raise ValueError(f"Refusing to overwrite unmarked directory: {destination}")
        elif tar_path.exists() or checksum_path.exists():
            raise ValueError("Refusing to overwrite an archive without its marked Demo directory")
        check_elf(source / args.binary)
        json.loads(require_file(args.manifest).read_text(encoding="utf-8"))
        audit = audit_pck(args.pck if args.pck else source / args.binary)
        if audit["forbidden_entries"]:
            examples = ", ".join(item["path"] for item in audit["forbidden_entries"][:5])
            raise ValueError(f"PCK includes {len(audit['forbidden_entries'])} forbidden resources: {examples}")
        if len({p.name for p in args.native_library}) != len(args.native_library):
            raise ValueError("Duplicate native library filenames")
        output.mkdir(parents=True, exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix=".paper-front-demo-", dir=output))
        preserve_temporary = False
        try:
            staging, packed, checksum = temporary / args.name, temporary / "bundle.tar.gz", temporary / "bundle.sha256"
            prepare(args, staging, audit)
            archive(staging, packed, args.name)
            checksum.write_text(f"{digest(packed)}  {tar_path.name}\n", encoding="utf-8")
            publish(staging, packed, checksum, destination)
        except PublicationRecoveryError:
            preserve_temporary = True
            raise
        finally:
            if not preserve_temporary:
                shutil.rmtree(temporary)
        print(f"Package created: {destination}\nArchive: {tar_path}\nArchive checksum: {checksum_path}")
        print("Only file/PCK/manifest checks performed. Runtime acceptance remains the caller's responsibility.")
        return 0
    except (OSError, ValueError, KeyError, UnicodeError, struct.error) as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
