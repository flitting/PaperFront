#!/usr/bin/env python3
"""Package the exported Windows runtime and portable launcher; no runtime tests."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tempfile
import zipfile

from package_demo_release import PROJECT, audit_pck, copy_file, digest, pck_entries, read_exact, write_json

MARKER = ".paper-front-windows-portable-package"


def check_pe64(path: Path) -> dict:
    with path.open("rb") as handle:
        header = handle.read(64)
        if len(header) != 64 or header[:2] != b"MZ":
            raise ValueError(f"Expected Windows PE file: {path}")
        handle.seek(struct.unpack_from("<I", header, 60)[0])
        pe = handle.read(26)
    if len(pe) != 26 or pe[:4] != b"PE\0\0" or struct.unpack_from("<H", pe, 4)[0] != 0x8664 or struct.unpack_from("<H", pe, 24)[0] != 0x20B:
        raise ValueError(f"Expected Windows x86_64 PE32+: {path}")
    return {"path": path.name, "bytes": path.stat().st_size, "sha256": digest(path), "format": "PE32+ x86_64"}


def inactive_radio_paths() -> list[str]:
    manifest = json.loads((PROJECT / "assets/audio/revision_v8/radio/manifest.json").read_text(encoding="utf-8"))
    active = {entry["file"].removeprefix("res://") for entry in manifest["clips"]}
    return [path.relative_to(PROJECT).as_posix() for path in sorted((PROJECT / "assets/audio/revision_v8/radio").glob("*.wav"))
            if path.relative_to(PROJECT).as_posix() not in active]


def audit_windows_pck(path: Path) -> dict:
    audit = audit_pck(path)
    _, entries = pck_entries(path)
    inactive = inactive_radio_paths()
    basenames = [PurePosixPath(name).name for name in inactive]
    with path.open("rb") as handle:
        for entry in entries:
            name = entry["path"].lower()
            basename = PurePosixPath(name).name
            reason = None
            if any(name == retired or name.startswith(retired + ".") for retired in inactive):
                reason = "inactive v8 radio source/import/remap"
            elif name.startswith(".godot/imported/") and any(basename.startswith(retired + "-") or basename.startswith(retired + ".") for retired in basenames):
                reason = "inactive v8 radio imported payload"
            elif name.endswith((".import", ".remap")):
                if entry["bytes"] > 1024 * 1024:
                    raise ValueError(f"Unexpectedly large import mapping: {name}")
                handle.seek(entry["offset"])
                mapping = read_exact(handle, entry["bytes"]).decode("utf-8", errors="replace").lower()
                if any("res://" + retired in mapping for retired in inactive) or any("/" + retired + "-" in mapping for retired in basenames):
                    reason = "export mapping points to inactive v8 radio"
            if reason:
                audit["forbidden_entries"].append({"path": entry["path"], "reason": reason})
    audit["inactive_v8_radio_sources"] = inactive
    return audit


def readme() -> str:
    return """纸境战线 · Paper Front — Windows x64 免安装版

先完整解压 ZIP，再双击根目录 PaperFront.exe。无需安装 Godot 或编译器。
请保持 bin/ 与启动程序在同一个解压目录内，勿直接启动 bin/ 内部运行程序。
需要 Windows 10/11 64 位，以及支持 Vulkan 的显卡和驱动。
请解压到你可写入的目录，例如桌面、文档或 D:\\Games；不要放到 Program Files。

所有游戏存档、设置、派生缓存和游戏日志保存在本目录的 user_data/。
F5 保存、F9 读取：user_data/skirmish_v1.pfront。
设置：user_data/settings.cfg。
地形缓存：user_data/terrain_mesh_cache_v1/。
图形缓存：user_data/shader_cache/；临时文件：user_data/tmp/。
日志：user_data/logs/。
删除 user_data/ 即可重置本份游戏，程序下次启动会重新创建；先退出游戏再删除。
删除整个解压目录即可删除本份游戏及其游戏数据。移动整个目录会同时带走存档。
ZIP 不包含开发者存档。独立解压的副本使用各自的数据目录。

左键选择/拖框，右键移动/攻击；WASD 平移，滚轮缩放。
Z + 左键攻击移动，X 停止，空格定位；P 暂停，Esc 打开菜单。
选中总部建造，选中生产建筑生产。U 卸载，L 飞机降落，B 返回机场。
初次游玩可选择「战役 · 无字桥补给线」。

验证范围见 VALIDATION/，组件许可见 LICENSES/，素材来源见 PROVENANCE/。
当前活动音频、指挥官播报的数量、供应商与许可说明见 PROVENANCE/audio_v8_README.md；制作工具见 SOURCE/。
历史机械语音与 eSpeak 源包不在本包中；供应商生成音频不声明为原创 CC0。
BUILD.sha256 记录出厂文件校验；运行产生的 user_data 文件不在校验清单内。
"""


def audio_records(stage: Path) -> dict:
    """Validate and describe the current manifest selection, including manual removals."""
    summary = {}
    for category, field in (("radio", "clips"), ("system", "clips"), ("sfx", "effects"), ("music", "tracks")):
        source = PROJECT / f"assets/audio/revision_v8/{category}/manifest.json"
        manifest = json.loads(source.read_text(encoding="utf-8"))
        entries = manifest.get(field, [])
        if not entries:
            raise ValueError(f"Empty current audio manifest: {source}")
        seen = set()
        for entry in entries:
            name = entry.get("file", "")
            if not name.startswith(f"res://assets/audio/revision_v8/{category}/") or ".." in PurePosixPath(name).parts or name in seen:
                raise ValueError(f"Invalid or duplicate current audio path: {name}")
            seen.add(name)
            asset = PROJECT / name.removeprefix("res://")
            provenance = entry.get("provenance", {})
            if digest(asset) != entry.get("sha256") or not provenance.get("type"):
                raise ValueError(f"Current audio differs from provenance or has no actual source: {asset}")
            if provenance["type"] == "original_dsp":
                if provenance.get("license") != "CC0-1.0":
                    raise ValueError(f"Original DSP license is missing: {asset}")
            elif not provenance.get("provider") or not provenance.get("model"):
                raise ValueError(f"Generated audio provider/model is missing: {asset}")
        target = f"PROVENANCE/audio_v8_{category}_manifest.json"
        copy_file(source, stage / target)
        summary[category] = {
            "count": len(entries), "manifest": target, "manifest_sha256": digest(source),
            "license_notice": manifest.get("license", "See individual entry provenance."),
            "source_types": dict(sorted(Counter(entry["provenance"]["type"] for entry in entries).items())),
            "models": dict(sorted(Counter(entry["provenance"].get("model", "original local DSP") for entry in entries).items())),
        }
    commander_source = PROJECT / "assets/audio/commander/manifest.json"
    commander = json.loads(commander_source.read_text(encoding="utf-8"))
    if not commander.get("clips") or not commander.get("provenance") or not commander.get("speaker"):
        raise ValueError("Commander audio manifest has no clips/source/speaker")
    seen = set()
    for entry in commander["clips"]:
        name = entry.get("file", "")
        if not name.startswith("res://assets/audio/commander/") or ".." in PurePosixPath(name).parts or name in seen:
            raise ValueError(f"Invalid or duplicate commander audio path: {name}")
        seen.add(name)
        if not entry.get("action") or not entry.get("text") or digest(PROJECT / name.removeprefix("res://")) != entry.get("sha256"):
            raise ValueError(f"Commander audio differs from provenance or has no action/text: {name}")
    copy_file(commander_source, stage / "PROVENANCE/audio_commander_manifest.json")
    copy_file(PROJECT / "tools/generate_commander_audio.py", stage / "SOURCE/commander/generate_commander_audio.py")
    summary["commander"] = {
        "count": len(commander["clips"]), "manifest": "PROVENANCE/audio_commander_manifest.json",
        "manifest_sha256": digest(commander_source), "speaker": commander["speaker"],
        "license_notice": commander["provenance"],
        "generator_sha256": digest(PROJECT / "tools/generate_commander_audio.py"),
    }
    write_json(stage / "PROVENANCE/audio_v8_selection.json", summary)
    total = sum(record["count"] for record in summary.values())
    lines = ["# 本包当前活动音频与来源", "",
             f"以随包实际 manifest 为准，共 {total} 项：{summary['radio']['count']} 条单位语音、"
             f"{summary['system']['count']} 条系统语音、{summary['sfx']['count']} 个音效、{summary['music']['count']} 首音乐，"
             f"另有 {summary['commander']['count']} 条指挥官播报。",
             "数量按当前人工筛选后的活动清单计算；未列入清单的历史文件不算作活动音频。", "",
             "语音、供应商声效和配乐不是人类实录，不声明为项目原创 CC0；供应商及已有来源说明按清单原文保留。"
             "原创本地 DSP 声效明确按 CC0-1.0 提供。每项实际来源、模型、请求/原始数据与成品 SHA 均保留在清单中。", ""]
    for category, record in summary.items():
        lines.extend([f"- {category}: {record['count']}；`{record['manifest']}`。", f"  {record['license_notice']}"])
    lines.extend(["", "SOURCE/audio_v8/ 与 SOURCE/commander/ 保留制作工具；游戏离线播放已生成音频，不需要 API 或合成器。",
                  "指挥官播报使用当前独立 Microsoft Edge / edge-tts 来源清单；与已退役的历史单位语音银行分开记录，不声明为 CC0。",
                  "历史机械语音、旧在线语音及 eSpeak 对应源包不随本包分发。",
                  "保留的旧原创 CC0 音乐与顶层音效另见 audio_music_manifest.json 和 original_effects.json；旧音乐不属于当前音乐播放清单。", ""])
    (stage / "PROVENANCE/audio_v8_README.md").write_text("\n".join(lines), encoding="utf-8")
    for name in ("generate_revision_v8_audio.py", "revision_v8_dialogue.py", "revision_audio_20261007.py"):
        copy_file(PROJECT / "tools" / name, stage / "SOURCE/audio_v8" / name)
    # Original CC0 assets remain in the export; retain their exact source records.
    source = PROJECT / "assets/audio/music/manifest.json"
    original_music = json.loads(source.read_text(encoding="utf-8"))
    if original_music.get("license") != "CC0-1.0" or not original_music.get("tracks"):
        raise ValueError(f"Original music license/entries missing: {source}")
    if digest(PROJECT / original_music["generator"]) != original_music.get("generator_sha256"):
        raise ValueError("Original music generator differs from provenance")
    for entry in original_music["tracks"]:
        if digest(PROJECT / entry["path"].removeprefix("res://")) != entry.get("sha256"):
            raise ValueError(f"Original music differs from provenance: {entry['path']}")
    copy_file(source, stage / "PROVENANCE/audio_music_manifest.json")
    write_json(stage / "PROVENANCE/original_effects.json", {
        "license": "CC0-1.0", "source_record": "LICENSES/PROJECT_ASSETS.md",
        "generators": [{"path": str(path.relative_to(PROJECT)), "sha256": digest(path)} for path in
                       (PROJECT / "tools/generate_audio.py", PROJECT / "tools/generate_unit_voices.py")],
        "project_effects": [{"path": path.relative_to(PROJECT).as_posix(), "sha256": digest(path)}
                            for path in sorted((PROJECT / "assets/audio").glob("*.wav"))],
        "note": "Original top-level CC0 effects only; current provider-generated audio has separate v8 manifests.",
    })
    return summary


def credits(audio: dict) -> str:
    return f"""# 纸境战线 · Paper Front — Windows portable credits

项目原创纸模、美术、台词和本地 DSP 音效采用 `LICENSES/PROJECT_ASSETS.md` 的 CC0 1.0 授权。
当前活动音频为 {audio['radio']['count']} 条单位语音、{audio['system']['count']} 条系统语音、{audio['sfx']['count']} 个音效、{audio['music']['count']} 首音乐。
另有 {audio['commander']['count']} 条当前指挥官播报，来源为 Microsoft Edge / edge-tts（`{audio['commander']['speaker']}`），保留其独立来源清单，不声明为 CC0。
v8 单位及系统语音来自 Microsoft MAI、xAI Grok 与 Qwen；供应商声效来自 Seed Audio，当前配乐来自 Google Lyria，均保留实际来源，不声明 CC0 或人类实录。
逐项供应商、模型、许可说明与文件 SHA 见 `PROVENANCE/audio_v8_*_manifest.json`；当前数量和来源类型见 `PROVENANCE/audio_v8_selection.json`。
历史机械语音与 eSpeak 源包不随本包分发。保留的旧原创 CC0 音乐来源记录不代表当前音乐播放清单。

| Component | Source / credit | License/source record |
| --- | --- | --- |
| Godot Engine | Godot Engine contributors; Juan Linietsky and Ariel Manzur | `LICENSES/GODOT_LICENSE.txt` (MIT); `LICENSES/GODOT_THIRD_PARTY.json` |
| Native Godot C++ bindings | godot-cpp contributors; project-authored numeric kernels | `LICENSES/GODOT_CPP_LICENSE.md` (MIT); `PROVENANCE/windows_native_build.json` |
| Windows native extension and launcher runtime portions | GNU compiler runtime and MinGW-w64 contributors | `LICENSES/WINDOWS_NATIVE_TOOLCHAIN_LICENSES.txt`; exact versions and link flags in `PROVENANCE/windows_native_build.json` and `PROVENANCE/portable_launcher_build.json` |
| Noto Sans CJK font | Google Corporation; Noto CJK project | `LICENSES/FONT_LICENSE.txt` (SIL OFL 1.1) |
| Creator Hand graphical mesh | MakeHuman Community CC0 graphical basemesh, extracted and re-rigged by this project | `LICENSES/MAKEHUMAN_CC0.md`, `LICENSES/MAKEHUMAN_LICENSE_SCOPE.md`; `PROVENANCE/creator_hand_source.json` |
| Original project assets and local DSP | Project generation/model code | `LICENSES/PROJECT_ASSETS.md`, `LICENSES/CC0_1.0_UNIVERSAL.txt`; `PROVENANCE/original_effects.json` |
| Current generated speech, effects and music | Actual providers and models in the v8 manifests | `PROVENANCE/audio_v8_README.md`; `SOURCE/audio_v8/` contains the project creation tools |
| Current commander announcements | Microsoft Edge online speech via edge-tts; locally processed with WORLD | `PROVENANCE/audio_commander_manifest.json`; `SOURCE/commander/generate_commander_audio.py`; provider output, no CC0 claim |

字体许可中 Debian 包装代码的 GPL 声明不改变字体自身 OFL 许可；本包不附该包装代码。MakeHuman 应用代码未包含，仅使用其 CC0 图形网格。
本包不附参考图片、开发截图、开发存档或旧语音银行。构建记录与验收范围见 `PROVENANCE/`、`VALIDATION/`。
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging-dir", required=True, type=Path)
    parser.add_argument("--licenses-dir", required=True, type=Path)
    parser.add_argument("--native-build", required=True, type=Path)
    parser.add_argument("--launcher-build", required=True, type=Path)
    parser.add_argument("--runtime-build", required=True, type=Path)
    parser.add_argument("--validation-report", action="append", default=[], type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--name", default="PaperFront-windows-x86_64-portable")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.name) or args.name in {".", ".."}:
        raise ValueError("Unsafe package name")
    source = args.staging_dir.resolve()
    runtime = source / "bin/PaperFrontRuntime.exe"
    launcher = source / "PaperFront.exe"
    library = source / "bin/paper_front_kernels.dll"
    inputs = [check_pe64(path) for path in (launcher, runtime, library)]
    native_build = json.loads(args.native_build.read_text(encoding="utf-8"))
    launcher_build = json.loads(args.launcher_build.read_text(encoding="utf-8"))
    runtime_build = json.loads(args.runtime_build.read_text(encoding="utf-8"))
    if native_build.get("dll_sha256") != digest(library):
        raise ValueError("Native build record does not match the staged DLL")
    if launcher_build.get("executable", {}).get("sha256") != digest(launcher):
        raise ValueError("Launcher build record does not match the staged EXE")
    if runtime_build.get("runtime", {}).get("sha256") != digest(runtime):
        raise ValueError("Runtime build record does not match the staged EXE")
    audit = audit_windows_pck(runtime)
    if audit["forbidden_entries"]:
        raise ValueError(f"Forbidden resources in PCK: {audit['forbidden_entries']}")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    destination, archive = output / args.name, output / f"{args.name}.zip"
    checksum = archive.with_suffix(".zip.sha256")
    if any(path.exists() for path in (destination, archive, checksum)):
        raise ValueError("Output already exists; choose a new package name or output directory")
    with tempfile.TemporaryDirectory(prefix=".windows-portable-", dir=output) as temporary:
        stage = Path(temporary) / args.name
        stage.mkdir()
        copy_file(launcher, stage / launcher.name)
        runtime_files = sorted((source / "bin").iterdir())
        for path in runtime_files:
            if path.is_symlink() or not path.is_file() or (path != runtime and path.suffix.lower() != ".dll"):
                raise ValueError(f"Unexpected runtime file: {path}")
            record = check_pe64(path)
            if path not in (runtime, library):
                inputs.append(record)
            copy_file(path, stage / "bin" / path.name)
        license_dir = args.licenses_dir.resolve()
        for name in ("GODOT_LICENSE.txt", "GODOT_THIRD_PARTY.json", "WINDOWS_NATIVE_TOOLCHAIN_LICENSES.txt"):
            copy_file(license_dir / name, stage / "LICENSES" / name)
        for relative, name in (
            ("assets/LICENSE.md", "PROJECT_ASSETS.md"),
            ("assets/fonts/LICENSE.txt", "FONT_LICENSE.txt"),
            ("assets/native/GODOT_CPP_LICENSE.md", "GODOT_CPP_LICENSE.md"),
            ("assets/creator_hand/MAKEHUMAN_LICENSE.md", "MAKEHUMAN_CC0.md"),
            ("assets/creator_hand/MAKEHUMAN_LICENSE_ASSETS.md", "CC0_1.0_UNIVERSAL.txt"),
            ("tools/source_assets/makehuman/LICENSE.md", "MAKEHUMAN_LICENSE_SCOPE.md"),
        ):
            copy_file(PROJECT / relative, stage / "LICENSES" / name)
        for relative, name in (
            ("assets/creator_hand/README.md", "creator_hand_README.md"),
            ("assets/creator_hand/source_provenance.json", "creator_hand_source.json"),
        ):
            copy_file(PROJECT / relative, stage / "PROVENANCE" / name)
        audio = audio_records(stage)
        (stage / "CREDITS.md").write_text(credits(audio), encoding="utf-8")
        (stage / "README.txt").write_text(readme(), encoding="utf-8-sig")
        (stage / MARKER).write_text("paper-front-windows-portable-v1\n", encoding="utf-8")
        data = stage / "user_data"
        data.mkdir()
        (data / "README.txt").write_text("存档、设置、缓存和日志会在此生成。游戏退出后删除此目录可重置本份游戏。\n", encoding="utf-8-sig")
        copy_file(args.native_build, stage / "PROVENANCE/windows_native_build.json")
        copy_file(args.launcher_build, stage / "PROVENANCE/portable_launcher_build.json")
        copy_file(args.runtime_build, stage / "PROVENANCE/windows_runtime_build.json")
        write_json(stage / "PROVENANCE/pck_audit.json", audit)
        reports = []
        for index, report in enumerate(args.validation_report, 1):
            target = f"VALIDATION/{index:02d}_{report.name}"
            copy_file(report, stage / target)
            reports.append({"path": target, "sha256": digest(report)})
        write_json(stage / "PROVENANCE/package_inputs.json", {
            "format": 1, "platform": "Windows x86_64", "runtime_inputs": inputs,
            "portable_user_data": "user_data/ relative to PaperFront.exe; launcher configures environment before engine initialization",
            "reports": reports, "scope": "Packaging, PE/PCK checks; runtime evidence is in supplied validation reports",
        })
        (stage / "BUILD.sha256").write_text("".join(
            f"{digest(path)}  {path.relative_to(stage).as_posix()}\n"
            for path in sorted(stage.rglob("*")) if path.is_file()
        ), encoding="utf-8")
        packed = Path(temporary) / "bundle.zip"
        with zipfile.ZipFile(packed, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in sorted(stage.rglob("*")):
                relative = f"{args.name}/{path.relative_to(stage).as_posix()}"
                if path.is_dir():
                    bundle.writestr(relative + "/", b"")
                elif path.is_file():
                    bundle.write(path, relative)
        with zipfile.ZipFile(packed) as bundle:
            if bundle.testzip() is not None:
                raise ValueError("ZIP CRC verification failed")
        archive_digest = digest(packed)
        stage.rename(destination)
        packed.rename(archive)
        checksum.write_text(f"{archive_digest}  {archive.name}\n", encoding="utf-8")
    print(json.dumps({"directory": str(destination), "zip": str(archive), "bytes": archive.stat().st_size,
                      "sha256": archive_digest, "pck_entries": audit["entries"], "forbidden_entries": 0}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
