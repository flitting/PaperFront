# Windows portable release / Windows 免安装版

The Windows x86_64 player build uses Godot 4.6.2 and the `Windows Portable` export profile, together with a MinGW-w64-built native extension. It has the `portable` feature, without the development feature.

Extract the entire ZIP to a folder you can write to, then double-click **`PaperFront.exe`** at its root. The launcher sets the child process's data/cache/temp locations before Godot starts and forwards arguments. It does not change system-wide environment variables.

```text
PaperFront-v0.8.0-windows-x86_64/
├── PaperFront.exe
├── bin/
│   ├── PaperFrontRuntime.exe
│   └── paper_front_kernels.dll
├── START_HERE.txt
├── CREDITS.md
├── FILES.sha256
├── BUILD_INFO.json
├── LICENSES/
├── PROVENANCE/
└── user_data/                  # Created when the game runs
```

Use the root launcher so portable storage works correctly. Keep the runtime and native DLL together; launching from inside the ZIP is unsupported. Godot, a compiler and separate MinGW runtime DLLs do not need installation. The default Forward+ renderer needs Vulkan-capable graphics and current drivers; Windows 10/11 x64 is the target platform.

## Data and removal / 数据与卸载

| Data | Path inside the extracted folder |
|---|---|
| Save / 存档 | `user_data/skirmish_v1.pfront` |
| Preferences / 设置 | `user_data/settings.cfg` |
| Match reports / 对局报告 | `user_data/match_reports/` |
| Godot log / 日志 | `user_data/logs/godot.log` |
| Generated cache / 缓存 | `user_data/cache/` and other engine-generated cache folders |
| Temporary files / 临时文件 | `user_data/tmp/` |

Exit before moving or removing data. Copy the whole folder to carry saves with it. Separate extracted copies have isolated data. Preserve `user_data/` when upgrading; deleting it resets that copy's settings and saves. Deleting the entire extracted folder removes that copy of the game and its portable data.

## Building and verification / 构建与验证

From Linux:

```sh
python3 tools/build_release.py --version 0.8.0 --output artifacts/release_20261011
```

Requirements are Godot 4.6.2 with matching export templates, CMake, Python 3, the MinGW-w64 POSIX x86_64 toolchain, ImageMagick and Pillow. `PAPER_FRONT_GODOT` selects the engine; `PAPER_FRONT_MINGW_BIN` can select an unpacked toolchain. The build script calls `tools/build_native_windows.sh`, `tools/build_portable_launcher.sh` and the Windows export preset, then packages runtime files, license notices, provenance and checksums.

The native extension statically links the relevant compiler runtimes. The build checks imports so the player does not need `libstdc++-6.dll`, `libgcc_s_seh-1.dll` or `libwinpthread-1.dll` as loose files.

See [release notes](release_notes.md) for checks actually performed. Cross-compilation and Wine checks are distinct from a Windows machine's GPU/driver, audio and complete play testing; do not describe them as Windows hardware validation.

## 中文使用说明

完整解压到可写文件夹，双击根目录 **`PaperFront.exe`**；不要直接运行内部 runtime，不要只移动 EXE，也不要在压缩包内启动。需要 Windows 10/11 x64 及支持 Vulkan 的显卡和驱动，无需另装 Godot 或编译器运行库。

启动器仅为子进程设置便携目录，不改系统环境变量。存档、设置、日志、报告和缓存均留在本份解压目录的 `user_data/` 下。退出后可整体移动，升级时保留 `user_data/`；删除该目录会重置本份游戏数据，删除整个解压文件夹即可移除游戏。

构建命令与要求见上文；具体检查范围见发布说明，不能把 Linux 交叉编译或 Wine 运行等同于 Windows 实机验收。
