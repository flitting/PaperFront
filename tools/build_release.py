#!/usr/bin/env python3
"""Build player-only Linux and portable Windows releases with Godot 4.6.2.

Requires the Godot release templates, CMake, GCC, MinGW-w64 POSIX, Python 3,
ImageMagick and Pillow. No game/editor/test binaries are downloaded by this tool.
Smoke-test the resulting archives separately; successful packaging is not a
claim of Windows hardware compatibility or completed play/performance testing.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
EXPECTED_GODOT = "4.6.2"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command: list[str], log: Path, env: dict[str, str], *, godot=False) -> None:
    print("Running:", " ".join(map(str, command)), flush=True)
    with log.open("w", encoding="utf-8") as handle:
        result = subprocess.run(command, cwd=PROJECT, env=env, stdout=handle,
                                stderr=subprocess.STDOUT, text=True)
    content = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode or (godot and re.search(r"SCRIPT ERROR:|^ERROR:", content, re.M)):
        print(content[-16000:])
        raise RuntimeError(f"Build failed; inspect {log}")


def copy_file(source: Path, target: Path) -> None:
    if not source.is_file() or source.is_symlink():
        raise ValueError(f"Required release input missing: {source}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    target.chmod(0o644)


def json_file(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def native_info(path: Path, env: dict[str, str]) -> dict:
    info = {"sha256": sha256(path), "bytes": path.stat().st_size}
    if path.suffix == ".so":
        versions = subprocess.check_output(["readelf", "--version-info", str(path)], text=True)
        glibc = sorted(set(re.findall(r"GLIBC_([0-9.]+)", versions)),
                       key=lambda version: tuple(map(int, version.split("."))))
        info["required_glibc"] = glibc[-1] if glibc else None
        info["dynamic_dependencies"] = subprocess.check_output(["ldd", str(path)], text=True)
    else:
        imports = subprocess.check_output(["x86_64-w64-mingw32-objdump", "-p", str(path)],
                                          text=True, env=env)
        info["dll_imports"] = re.findall(r"DLL Name:\s+(\S+)", imports)
        forbidden = {"libstdc++-6.dll", "libgcc_s_seh-1.dll", "libwinpthread-1.dll"}
        if forbidden.intersection(map(str.lower, info["dll_imports"])):
            raise ValueError("Windows native extension still requires compiler runtime DLLs")
    return info


def notices(stage: Path, engine_licenses: Path, env: dict[str, str], windows: bool) -> None:
    common = [
        (engine_licenses / "GODOT_LICENSE.txt", "GODOT_LICENSE.txt"),
        (engine_licenses / "GODOT_THIRD_PARTY.json", "GODOT_THIRD_PARTY.json"),
        (PROJECT / "assets/LICENSE.md", "PROJECT_ASSETS.md"),
        (PROJECT / "assets/fonts/LICENSE.txt", "FONT_LICENSE.txt"),
        (PROJECT / "assets/native/GODOT_CPP_LICENSE.md", "GODOT_CPP_LICENSE.md"),
        (PROJECT / "assets/creator_hand/MAKEHUMAN_LICENSE.md", "MAKEHUMAN_CC0.md"),
        (PROJECT / "assets/creator_hand/MAKEHUMAN_LICENSE_ASSETS.md", "CC0_1.0_UNIVERSAL.txt"),
        (PROJECT / "tools/source_assets/makehuman/LICENSE.md", "MAKEHUMAN_LICENSE_SCOPE.md"),
    ]
    if not windows:
        common.append((PROJECT / "assets/native/GNU_RUNTIME_LICENSES.txt", "GNU_RUNTIME_LICENSES.txt"))
    for source, target in common:
        copy_file(source, stage / "LICENSES" / target)
    for directory, target in [("assets/audio/licenses", "AUDIO"),
                              ("assets/audio/english/licenses", "ENGLISH_SPEECH")]:
        for source in sorted((PROJECT / directory).glob("*")):
            if source.is_file(): copy_file(source, stage / "LICENSES" / target / source.name)
    if windows:
        compiler = Path(shutil.which("x86_64-w64-mingw32-g++-posix", path=env["PATH"]) or "")
        prefix = compiler.parent.parent
        notice_parts = []
        for name in ("gcc-mingw-w64-base", "mingw-w64-common"):
            source = prefix / "share/doc" / name / "copyright"
            if not source.is_file(): source = Path("/usr/share/doc") / name / "copyright"
            if not source.is_file(): raise ValueError(f"Missing MinGW runtime notice: {source}")
            notice_parts.append(f"{name}\n{'=' * len(name)}\n{source.read_text()}\n")
        (stage / "LICENSES/WINDOWS_NATIVE_TOOLCHAIN_LICENSES.txt").write_text(
            "Exact MinGW toolchain notices for statically linked libgcc/libstdc++/winpthread.\n\n" +
            "\n".join(notice_parts), encoding="utf-8")
    copy_file(PROJECT / "docs/demo_credits.md", stage / "CREDITS.md")
    provenance = stage / "PROVENANCE"
    for source, name in [
        ("assets/audio/README_demo_original.md", "ORIGINAL_AUDIO.md"),
        ("assets/audio/revision_v8/README.md", "CURRENT_AUDIO.md"),
        ("assets/audio/english/README.md", "ENGLISH_SPEECH.md"),
        ("assets/audio/english/provenance.json", "english_speech.json"),
        ("assets/creator_hand/source_provenance.json", "creator_hand.json"),
    ]:
        copy_file(PROJECT / source, provenance / name)
    for source in sorted((PROJECT / "assets/audio/revision_v8").rglob("*.json")):
        copy_file(source, provenance / "audio" / source.relative_to(PROJECT / "assets/audio/revision_v8"))


def startup(stage: Path, version: str, windows: bool, glibc: str | None) -> None:
    if windows:
        text = f"""Paper Front v{version} — Windows x86_64

Extract the whole ZIP into a writable folder, then run PaperFront.exe.
Keep bin/PaperFrontRuntime.exe and bin/paper_front_kernels.dll together.
Godot and compiler runtimes do not need separate installation. Settings, saves,
logs and generated caches stay in user_data beside the launcher. Keep that folder
when upgrading if you want to retain your progress. Do not run from inside the ZIP.

The default renderer is Vulkan Forward+. A Windows machine with Vulkan-capable
graphics and current GPU drivers is required. This release was cross-compiled
on Linux; the release validation report states the exact Windows/Wine test scope.

Windows 中文说明
将整个 ZIP 解压到可写目录，双击 PaperFront.exe。请完整保留 bin 目录。
无需另装 Godot 或编译器运行库。设置、存档、日志和缓存保存在同目录
user_data 文件夹中，升级时可保留。不要直接在压缩包内部运行。
默认渲染器是 Vulkan Forward+，需要支持 Vulkan 的显卡与相应驱动。
本版本在 Linux 上交叉编译，Windows/Wine 的测试范围见发布验证报告。
"""
    else:
        text = f"""Paper Front v{version} — Linux x86_64

Extract the entire archive, open a terminal in its folder, then run ./start.sh.
If the executable permission was lost: chmod +x start.sh PaperFront.x86_64
Keep libpaper_front_kernels.so beside PaperFront.x86_64.
The embedded game data, Godot runtime and native extension are included.

This GCC build requires glibc {glibc} or newer (Ubuntu 24.04 is the tested host),
a desktop session and Vulkan-capable graphics with current drivers. The default
renderer is Vulkan Forward+. Settings and saves use Godot's standard user data
folder: ~/.local/share/godot/app_userdata/纸境战线 · Paper Front/ (XDG_DATA_HOME may override).

Linux 中文说明
完整解压后在文件夹内运行 ./start.sh。若执行权限丢失，请运行：
chmod +x start.sh PaperFront.x86_64
请保留同目录下的 libpaper_front_kernels.so。运行包已包含游戏数据、
Godot 运行时和原生扩展。此构建需要 glibc {glibc} 或更高版本、桌面会话、
支持 Vulkan 的显卡及驱动；测试主机为 Ubuntu 24.04。
设置与存档在 ~/.local/share/godot/app_userdata/纸境战线 · Paper Front/ 下
（可被 XDG_DATA_HOME 覆盖）。
"""
        (stage / "start.sh").write_text(
            '#!/bin/sh\nset -eu\ncd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec ./PaperFront.x86_64 "$@"\n', encoding="utf-8")
        (stage / "start.sh").chmod(0o755)
    text += "\nEnglish and Chinese UI are available in Settings. / 可在设置中切换中英文。\nCredits and third party notices: CREDITS.md and LICENSES/.\n\nRepository: https://github.com/flitting/PaperFront\n"
    (stage / "START_HERE.txt").write_text(text, encoding="utf-8")


def archive(stage: Path, output: Path, windows: bool) -> Path:
    files = sorted(path for path in stage.rglob("*") if path.is_file())
    if any(path.is_symlink() for path in stage.rglob("*")):
        raise ValueError("Release staging must not contain symlinks")
    manifest = {str(path.relative_to(stage)): sha256(path) for path in files
                if path.name != "FILES.sha256"}
    (stage / "FILES.sha256").write_text("".join(f"{digest}  {name}\n" for name, digest in manifest.items()), encoding="utf-8")
    files = sorted(path for path in stage.rglob("*") if path.is_file())
    suffix = ".zip" if windows else ".tar.gz"
    target = output / (stage.name + suffix)
    temporary = target.with_suffix(target.suffix + ".tmp")
    if windows:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
            for path in files: bundle.write(path, str(Path(stage.name) / path.relative_to(stage)))
        with zipfile.ZipFile(temporary) as bundle:
            if bundle.testzip() is not None: raise ValueError("ZIP integrity check failed")
    else:
        with temporary.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as bundle:
                for path in files:
                    info = bundle.gettarinfo(str(path), str(Path(stage.name) / path.relative_to(stage)))
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    with path.open("rb") as handle: bundle.addfile(info, handle)
    temporary.replace(target)
    print(f"Created {target} ({target.stat().st_size:,} bytes)", flush=True)
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.8.0")
    parser.add_argument("--output", type=Path, default=PROJECT / "artifacts/release_20261011")
    parser.add_argument("--skip-native", action="store_true", help="Use caller-rebuilt native extensions")
    parser.add_argument("--skip-import", action="store_true", help="Use an already imported project (for coordinated local builds)")
    parser.add_argument("--package-only", action="store_true", help="Archive already prepared staging folders")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version): raise ValueError("Use a numeric semantic version")
    output = args.output.resolve()
    if output == PROJECT or output in PROJECT.parents:
        raise ValueError("Release output must be a separate directory, not the project or an ancestor")
    output.mkdir(parents=True, exist_ok=True)
    # A clean CI checkout has no ignored artifacts/.gdignore from local runs.
    # Keep generated launch icons, archives and extracted validation data out
    # of Godot's importer before the first build creates any such files.
    (output / ".gdignore").touch()
    logs = output / "logs"
    logs.mkdir(exist_ok=True)
    env = os.environ.copy()
    local_mingw = PROJECT / "artifacts/toolchains/mingw-w64/usr/bin"
    mingw = env.get("PAPER_FRONT_MINGW_BIN", str(local_mingw) if local_mingw.is_dir() else "")
    if mingw:
        env["PAPER_FRONT_MINGW_BIN"] = mingw
        env["PATH"] = mingw + os.pathsep + env["PATH"]
    stages = [(output / f"PaperFront-v{args.version}-linux-x86_64", False),
              (output / f"PaperFront-v{args.version}-windows-x86_64", True)]
    if not args.package_only:
        godot = env.get("PAPER_FRONT_GODOT", "godot")
        engine = subprocess.check_output([godot, "--version"], text=True).strip()
        if not engine.startswith(EXPECTED_GODOT + "."):
            raise ValueError(f"Expected Godot {EXPECTED_GODOT}, received {engine}")
        preset = (PROJECT / "export_presets.cfg").read_text()
        if f'application/product_version="{args.version}.0"' not in preset:
            raise ValueError("Windows export version does not match; update export_presets.cfg first")
        launcher_resource = (PROJECT / "tools/portable_windows_launcher.rc").read_text()
        if f'"ProductVersion", "{args.version}.0\\0"' not in launcher_resource:
            raise ValueError("Windows launcher version does not match; update portable_windows_launcher.rc first")
        if not args.skip_native:
            run([str(PROJECT / "tools/build_native.sh")], logs / "native-linux.log", env)
            run([str(PROJECT / "tools/build_native_windows.sh")], logs / "native-windows.log", env)
        if not args.skip_import:
            run([godot, "--headless", "--path", str(PROJECT), "--editor", "--import"], logs / "import.log", env, godot=True)
        licenses = output / "engine-licenses"
        run([godot, "--headless", "--path", str(PROJECT), "--script", "res://tools/export_licenses.gd", "--", "--output", str(licenses)], logs / "engine-licenses.log", env, godot=True)
        spec = importlib.util.spec_from_file_location("release_pck_audit", PROJECT / "tools/package_demo_release.py")
        audit_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(audit_module)
        git_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT, text=True).strip()
        inputs = [PROJECT / "project.godot", PROJECT / "export_presets.cfg",
                  PROJECT / "native/CMakeLists.txt", PROJECT / "native/build_profile.json",
                  PROJECT / "tools/build_native.sh", PROJECT / "tools/build_native_windows.sh",
                  PROJECT / "tools/build_portable_launcher.sh", PROJECT / "tools/portable_windows_launcher.c",
                  PROJECT / "tools/portable_windows_launcher.rc", PROJECT / "tools/portable_windows_launcher.manifest",
                  Path(__file__).resolve()]
        inputs += sorted((PROJECT / "native/src").glob("*"))
        inputs += sorted((PROJECT / "scripts").rglob("*.gd"))
        inputs += sorted((PROJECT / "data").rglob("*.json"))
        source_hashes = {str(path.relative_to(PROJECT)): sha256(path) for path in inputs if path.is_file()}
        for stage, windows in stages:
            stage.mkdir(exist_ok=True)
            if any(stage.iterdir()): raise ValueError(f"Refusing nonempty staging folder: {stage}")
            binary = stage / ("bin/PaperFrontRuntime.exe" if windows else "PaperFront.x86_64")
            binary.parent.mkdir(parents=True, exist_ok=True)
            run([godot, "--headless", "--path", str(PROJECT), "--export-release", "Windows Portable" if windows else "Linux Shipping", str(binary)], logs / ("export-windows.log" if windows else "export-linux.log"), env, godot=True)
            binary.chmod(0o755)
            if windows:
                env["PAPER_FRONT_PORTABLE_BUILD_DIR"] = str(output / "launcher-build")
                env["PAPER_FRONT_LAUNCHER_BUILD_REPORT"] = str(output / "launcher-build.json")
                run([str(PROJECT / "tools/build_portable_launcher.sh"), str(stage / "PaperFront.exe")], logs / "launcher.log", env)
            native = binary.parent / ("paper_front_kernels.dll" if windows else "libpaper_front_kernels.so")
            if sha256(native) != sha256(PROJECT / "assets/native" / native.name):
                raise ValueError("Exported native sidecar differs from rebuilt source library")
            info = native_info(native, env)
            audit = audit_module.audit_pck(binary)
            if audit["forbidden_entries"]:
                json_file(output / ("pck-windows-failed.json" if windows else "pck-linux-failed.json"), audit)
                raise ValueError("PCK contains developer or retired resources")
            json_file(output / ("pck-windows.json" if windows else "pck-linux.json"), audit)
            notices(stage, licenses, env, windows)
            startup(stage, args.version, windows, info.get("required_glibc"))
            # Console wrapper is an export convenience, not another player entrypoint.
            for wrapper in stage.glob("*.sh"):
                if wrapper.name != "start.sh": wrapper.unlink()
            build_info = {
                "version": args.version, "godot": engine, "git_head_before_release_commit": git_head,
                "source_hashes": source_hashes, "platform": "windows-x86_64" if windows else "linux-x86_64",
                "native": info, "runtime": {"sha256": sha256(binary), "bytes": binary.stat().st_size},
                "pck": audit, "scope": "Player runtime only; no editor, test suite, historical reports or expansion source bundle.",
                "validation": "See build-validation.md attached to the GitHub release. Packaging alone does not validate gameplay or Windows hardware.",
            }
            if windows:
                launcher = json.loads((output / "launcher-build.json").read_text())["executable"]
                build_info["launcher"] = {key: launcher[key] for key in ("sha256", "bytes", "imports")}
                build_info["launcher"]["resource_version"] = args.version + ".0"
            json_file(stage / "BUILD_INFO.json", build_info)
    packages = [archive(stage, output, windows) for stage, windows in stages]
    (output / "SHA256SUMS").write_text("".join(f"{sha256(path)}  {path.name}\n" for path in packages), encoding="utf-8")
    print((output / "SHA256SUMS").read_text(), end="")


if __name__ == "__main__":
    main()
