# Windows x64 免安装发行包

本轮从 Linux 构建 Godot 4.6.2 的 Windows release 程序，并用 MinGW-w64 编译项目原生扩展。正式包使用 `Windows Portable` preset；只加入 `portable` 特征，不加入 `development`。

解压后双击根目录 `PaperFront.exe`。它是便携启动入口，内含项目图标，按普通用户权限运行；真正的 Godot 程序及游戏资源位于 `bin/PaperFrontRuntime.exe`，原生扩展位于同目录 `paper_front_kernels.dll`。不要直接启动内部 runtime。

启动入口在引擎初始化之前设置子进程的数据、缓存和临时目录；不会修改系统环境变量。对应 `application/config/use_custom_user_dir.portable` 和 `custom_user_dir_name.portable` 使 `user://` 指向本份解压目录的 `user_data/`。Linux 源码与编辑器继续使用原有用户数据路径。

```text
PaperFront-v7-windows-x86_64-portable/
├── PaperFront.exe
├── bin/
│   ├── PaperFrontRuntime.exe    # 内嵌游戏资源
│   └── paper_front_kernels.dll
├── user_data/                  # 出厂只有说明；运行后生成数据
├── README.txt
├── CREDITS.md
├── BUILD.sha256
├── LICENSES/
├── PROVENANCE/
├── VALIDATION/
└── SOURCE/espeak-ng/            # 中文合成应答的对应源材料
```

游戏存档为 `user_data/skirmish_v1.pfront`（F5 保存、F9 读取）；设置为 `user_data/settings.cfg`。地形缓存、图形缓存、日志与临时文件也在 `user_data/` 下。退出游戏后删除 `user_data/` 可重置本份游戏；删除整个解压目录可移除这份游戏和游戏数据。移动整个目录会一同带走存档。独立解压的副本相互隔离，不附带开发者存档。

需要 Windows 10/11 x64、支持 Vulkan 的显卡及驱动，并将游戏解压到当前用户可写入的目录。无需安装 Godot、编译器或额外 MinGW 运行库。

构建入口为 `tools/build_native_windows.sh`、`tools/build_portable_launcher.sh`、Godot 的 `Windows Portable` preset，封装入口为 `tools/package_windows_portable.py`。本机免 root 的 MinGW 工具链位于 `artifacts/toolchains/mingw-w64/usr/bin`；可通过 `PAPER_FRONT_MINGW_BIN` 指定它。打包器检查 Windows PE 架构、PCK 中排除的开发资源及旧语音、构建记录与实际二进制 SHA，然后创建干净数据目录和 ZIP。

本轮的确切二进制、模板、源文件和工具链记录在 `artifacts/windows_portable/` 及包内 `PROVENANCE/`。实际 Windows 二进制的 Wine 验证范围在包内 `VALIDATION/`；它不等同于 Windows 实机、真实显卡性能、物理音频或完整游玩验收。

曾使用旧 Wine 的模板预检产生异常调试窗口，已终止本轮所有残留进程。后续验证改为 WineHQ 11 的独立 Xvfb 显示、禁止调试器弹窗、有限执行时长和最终进程清理，避免干扰用户桌面。
