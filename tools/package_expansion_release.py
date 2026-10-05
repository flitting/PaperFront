#!/usr/bin/env python3
"""Package an already exported Linux build; never export or claim validation."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import os
from pathlib import Path
import re
import shutil
import struct
import tarfile
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
MARKER = ".paper-front-package"
FORMAT = "paper-front-revision-v6-package-v1\n"
ACCEPTED_FORMATS = {FORMAT, "paper-front-expansion-v5-package-v1\n"}
EVIDENCE_SUFFIXES = {".log", ".result", ".json", ".png", ".txt", ".md", ".sha256"}
HISTORICAL_NAMES = {
    "PERFORMANCE_RESULTS.md", "VALIDATION.txt", "FACTION_VALIDATION.md",
    "FACTION_REVISION.md", "BUILDING_REPAIR.md", "NAVIGATION_VALIDATION.md",
    "UI_UPDATE_TESTS.md", "WIKI_VALIDATION.md", "VISUAL_RESTORATION.md",
    "BEVY_ECS_ASSESSMENT.md", "EXPANSION_FACTIONS.md", "FACTION_CATALOG.md",
    "NATIVE_README.md", "performance_reports", "revision_reports",
    "visual_checks", "manifest.json",
}


def require_file(path: Path) -> Path:
    if not path.is_file():
        raise ValueError(f"缺少必要文件：{path}")
    return path


def check_linux_binary(path: Path) -> None:
    with require_file(path).open("rb") as handle:
        header = handle.read(64)
    if (len(header) < 64 or header[:6] != b"\x7fELF\x02\x01"
            or struct.unpack_from("<H", header, 18)[0] != 62):
        raise ValueError(f"需要 Linux x86_64 ELF 二进制：{path}")


def copy_file(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(require_file(source), target)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize_copied_markdown(stage: Path) -> None:
    """Make only bundled Markdown links portable; leave source reports intact."""
    reference_aliases = {
        "/tmp/codex-clipboard-c04107fd-65c5-4fd6-9bc4-fba50a1db328.png":
            "docs/revision_v6/hand_reference_walk.png",
        "/tmp/codex-clipboard-30d02f46-209d-4c0b-a077-980a8ca9145f.png":
            "docs/revision_v6/hand_reference_attack.png",
    }
    for document in sorted(stage.rglob("*.md")):
        def replace(match: re.Match[str]) -> str:
            original = match.group(1)
            target = original[1:-1] if original.startswith("<") and original.endswith(">") else original
            suffix = ""
            if "#" in target:
                target, anchor = target.split("#", 1)
                suffix = "#" + anchor
            line = re.search(r":\d+$", target)
            if line:
                suffix = line.group() + suffix
                target = target[:line.start()]
            if target in reference_aliases:
                bundled = stage / reference_aliases[target]
            else:
                absolute = Path(target)
                if not absolute.is_absolute():
                    return match.group(0)
                try:
                    relative = absolute.relative_to(PROJECT)
                except ValueError:
                    return match.group(0)
                bundled = stage / relative
            if not bundled.is_file():
                return match.group(0)
            portable = os.path.relpath(bundled, document.parent).replace(os.sep, "/") + suffix
            if any(character.isspace() for character in portable):
                portable = "<" + portable + ">"
            return "](" + portable + ")"
        text = document.read_text(encoding="utf-8")
        document.write_text(re.sub(r"\]\((<[^>\n]+>|[^)\n]+)\)", replace, text), encoding="utf-8")


def start_here(binary: str, dry_run: bool) -> str:
    status = "【仅供打包流程测试，不能作为游戏发行版】\n\n" if dry_run else ""
    return status + f"""纸境战线 · 2026-10-05 模型、交互与地图重建验收

Linux x86_64 / Godot 4.6.2。解压后进入本目录，运行：
  ./{binary}
程序必须与本目录的原生 .so 库一起保留。游玩无需另装 Godot。

入口的「开始战局」进入遭遇战；六种新320地图支持玩家与1—3名AI，
可选择各方阵营和难度。经典地图固定两方。「战役 · 无字桥补给线」
是唯一的正典单关教程入口，按左上任务提示建设、采矿、修桥和反攻。

选中总部或兵营、工厂、机场、船坞唤起对应建造栏。未解锁项目隐藏，
先建设电站、精炼厂、兵营和车辆工厂；常规与防御各有一条队列。
工程兵的分基地部署在独立操作按钮。船坞直接建在有足够通航空间的海上。
右键移动或攻击，Z攻击移动，X停止。
右下装载/卸载菜单分别指定乘员或卸载地点，已载客后仍可补员。
运输载具接受地面步兵，含工兵与反甲兵。运输机L后左键降落；
U后左键指定合法地面/岸边卸载点；B主动回机场维修补给后停机，
移动命令重新起飞。自动弹尽返航保留原任务。容量与价格请看Wiki。
天翼创世之手每名玩家同时限一只（包含生产预留），死亡后可重造。

F5保存、F9读取。旧存档保留当时的规则和地图快照；查看本版新数值、
新地图及新增单位请开新局。读取旧档后再开新局，会重新加载当前规则。

当前功能、验收状态与实际测量条件：README.md、
docs/revision_v6_validation.md。地图AI设计与实际对照保存在docs/map_design_v6，
参考图保存在assets/map_design_v6。HISTORICAL_REPORTS.md标明继承的旧报告；
旧性能报告不能作为本版帧率结果。本脚本打包完成不等于运行验收通过。
BUILD.sha256记录包内文件哈希，可在本目录运行 sha256sum -c BUILD.sha256。
引擎、字体、素材与原生绑定许可均在本目录随附。
"""


def prepare(source: Path, stage: Path, binary: str, licenses: Path,
            manifest: Path | None, dry_run: bool) -> None:
    shutil.copytree(source, stage)
    historical = sorted(name for name in HISTORICAL_NAMES if (stage / name).exists())
    if (manifest is not None and (source / "manifest.json").is_file()
            and sha256(require_file(manifest)) == sha256(source / "manifest.json")):
        historical = [name for name in historical if name != "manifest.json"]
    if historical:
        history = stage / "historical_export"
        history.mkdir(exist_ok=True)
        for name in historical:
            shutil.move(str(stage / name), history / name)
        historical = ["historical_export/" + name for name in historical]
    native_libraries = sorted((PROJECT / "assets/native").glob("*.so"))
    if not native_libraries:
        raise ValueError("assets/native 中没有可分发的 .so 原生库")
    for library in native_libraries:
        exported_library = require_file(source / library.name)
        if sha256(exported_library) != sha256(library):
            raise ValueError(f"已验收导出的原生库与当前源库不同：{library.name}")
        copy_file(exported_library, stage / library.name)
        (stage / library.name).chmod(0o755)
    (stage / binary).chmod(0o755)
    for source_license, target in [
        (PROJECT / "assets/LICENSE.md", "ASSET_LICENSE.md"),
        (PROJECT / "assets/fonts/LICENSE.txt", "FONT_LICENSE.txt"),
        (PROJECT / "assets/native/GODOT_CPP_LICENSE.md", "GODOT_CPP_LICENSE.md"),
        (licenses / "GODOT_LICENSE.txt", "GODOT_LICENSE.txt"),
        (licenses / "GODOT_THIRD_PARTY.json", "GODOT_THIRD_PARTY.json"),
    ]:
        copy_file(source_license, stage / target)
    copy_file(PROJECT / "README.md", stage / "README.md")
    require_file(PROJECT / "docs/expansion_v5_validation.md")
    for document in sorted((PROJECT / "docs").rglob("*.md")):
        copy_file(document, stage / document.relative_to(PROJECT))
    # Preserve the requested design-before-build workflow and references as
    # reviewable files, outside the embedded game PCK.
    for reference_dir in [PROJECT / "docs/map_design_v6", PROJECT / "docs/revision_v6", PROJECT / "assets/map_design_v6", PROJECT / "assets/creator_hand"]:
        if reference_dir.is_dir():
            for reference in sorted(reference_dir.rglob("*")):
                if reference.is_file() and reference.suffix in EVIDENCE_SUFFIXES:
                    copy_file(reference, stage / reference.relative_to(PROJECT))
    # Source archives and developer save files are not release evidence.
    for evidence_dir in [PROJECT / "artifacts/expansion_v5", PROJECT / "artifacts/expansion_v6", PROJECT / "artifacts/creator_hand", PROJECT / "artifacts/map_design_v6"]:
        if not evidence_dir.is_dir():
            continue
        for evidence in sorted(evidence_dir.rglob("*")):
            if evidence.is_file() and evidence.suffix in EVIDENCE_SUFFIXES:
                copy_file(evidence, stage / evidence.relative_to(PROJECT))
    if manifest is not None:
        copy_file(manifest, stage / "manifest.json")
    (stage / "START_HERE.txt").write_text(start_here(binary, dry_run), encoding="utf-8")
    historical.extend(name for name in ["docs/expansion_v5_validation.md", "artifacts/expansion_v5/"]
                      if (stage / name).exists())
    inherited = "\n".join(f"- `{name}`" for name in historical) or "本次输入没有列出的历史附件。"
    (stage / "HISTORICAL_REPORTS.md").write_text(
        "# 历史附件\n\n以下文件/目录来自先前发行或此前的工程报告，属于历史参考证据；"
        "它们不证明本次扩展已经通过运行或性能验收。当前结论请看"
        " `docs/revision_v6_validation.md`。\n\n" + inherited + "\n\n"
        "本轮地图原最终NO PASS的24张失败像素在归档指令到达前已被覆盖，"
        "仅原报告文字与36个SHA可追溯。`map_repair_first_capture_actual`是第一次新修图，"
        "不能作为旧失败像素；最后候选图与独立PASS报告分别绑定当前SHA。"
        "本轮早期回归、Source probe与导出配置失败尝试原日志保留；最终验收"
        "按文档中的成功运行和明确修复后的记录判断。\n",
        encoding="utf-8",
    )
    normalize_copied_markdown(stage)
    (stage / MARKER).write_text(FORMAT, encoding="utf-8")
    (stage / "BUILD.sha256").unlink(missing_ok=True)
    lines = [f"{sha256(path)}  {path.relative_to(stage).as_posix()}\n"
             for path in sorted(stage.rglob("*")) if path.is_file()]
    (stage / "BUILD.sha256").write_text("".join(lines), encoding="utf-8")


def archive(stage: Path, target: Path, name: str) -> None:
    # Fixed tar/gzip metadata makes repeated packaging byte-identical for the
    # same input bytes, independent of copy times, ownership or temp paths.
    with target.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as bundle:
            for path in [stage, *sorted(stage.rglob("*"))]:
                info = bundle.gettarinfo(str(path), arcname=name if path == stage else
                                         f"{name}/{path.relative_to(stage).as_posix()}")
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.pax_headers = {}
                if path.is_file():
                    with path.open("rb") as handle:
                        bundle.addfile(info, handle)
                else:
                    bundle.addfile(info)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary-dir", type=Path, required=True, help="已经导出并验收的 binary 目录")
    parser.add_argument("--binary", default="PaperFront.x86_64")
    parser.add_argument("--output-dir", type=Path, default=PROJECT / "artifacts")
    parser.add_argument("--name", default="PaperFront-linux-x86_64")
    parser.add_argument("--licenses-dir", type=Path, default=PROJECT / "artifacts/linux")
    parser.add_argument("--manifest", type=Path, help="由主任务生成的当前 manifest；不会运行 manifest 工具")
    parser.add_argument("--dry-run", action="store_true", help="完整验证打包流程，输出 DRY_RUN 名称并标明不可交付")
    args = parser.parse_args()
    try:
        source, output = args.binary_dir.resolve(), args.output_dir.resolve()
        if not source.is_dir():
            raise ValueError(f"导出目录不存在：{source}")
        if output == source or source in output.parents:
            raise ValueError("输出目录不能位于输入导出目录内")
        for name in [args.name, args.binary]:
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
                raise ValueError(f"需要单个文件/目录名称：{name}")
        check_linux_binary(source / args.binary)
        name = "DRY_RUN-" + args.name if args.dry_run else args.name
        output.mkdir(parents=True, exist_ok=True)
        destination, tar_path = output / name, output / f"{name}.tar.gz"
        if destination.exists() and (not (destination / MARKER).is_file()
                                     or (destination / MARKER).read_text() not in ACCEPTED_FORMATS):
            raise ValueError(f"输出目录不是本工具生成的包，请选择另一 --name：{destination}")
        with tempfile.TemporaryDirectory(prefix=".paper-front-package-", dir=output) as temporary:
            stage, packed = Path(temporary) / name, Path(temporary) / "bundle.tar.gz"
            prepare(source, stage, args.binary, args.licenses_dir.resolve(), args.manifest,
                    args.dry_run)
            archive(stage, packed, name)
            if destination.exists():
                shutil.rmtree(destination)
            os.replace(stage, destination)
            os.replace(packed, tar_path)
        print(f"打包流程完成：{tar_path}\nSHA-256: {sha256(tar_path)}")
        print("DRY_RUN：不是游戏发行版。" if args.dry_run else "仅完成复制、校验与归档；运行验收状态以当前文档为准。")
        return 0
    except (OSError, ValueError) as error:
        parser.exit(1, f"打包失败：{error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
