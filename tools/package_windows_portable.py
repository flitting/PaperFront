#!/usr/bin/env python3
"""Package the exported Windows runtime and portable launcher; no runtime tests."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import struct
import tempfile
import zipfile

from package_demo_release import PROJECT, audit_pck, copy_file, digest, original_records, write_json

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
SOURCE/espeak-ng/ 是随中文合成应答附带的对应源资料，运行时不需要安装它。
BUILD.sha256 记录出厂文件校验；运行产生的 user_data 文件不在校验清单内。
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
    parser.add_argument("--name", default="PaperFront-v7-windows-x86_64-portable")
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
    audit = audit_pck(runtime)
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
        original_records(stage)
        credits = (PROJECT / "docs/demo_credits.md").read_text(encoding="utf-8")
        credits = credits.replace("GCC 13 toolchain", "MinGW-w64 cross toolchain (see build record)")
        credits = credits.replace("LICENSES/GNU_RUNTIME_LICENSES.txt", "LICENSES/WINDOWS_NATIVE_TOOLCHAIN_LICENSES.txt")
        credits = credits.replace("PROVENANCE/compiler_runtime_source.json", "PROVENANCE/windows_native_build.json")
        credits = credits.replace("原生扩展通过 GCC 13 编译并静态链接 libstdc++ / libgcc，附带本机对应工具链的完整版权与运行库例外文本。", "Windows 原生扩展通过 MinGW-w64 交叉编译，附带对应 GNU 运行库例外与 MinGW-w64 / winpthreads 版权文本；确切版本、链接方式与文件 SHA 见构建记录。")
        (stage / "CREDITS.md").write_text(credits, encoding="utf-8")
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
