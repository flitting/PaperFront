# Paper Front v0.8.0 — Playable preview

Paper Front is a paper-craft 3D real-time strategy game with four factions,
base construction, infantry squads, and land, air and naval combat. This release
includes the current game, English and Simplified Chinese UI and voice options,
and standalone Linux and portable Windows x86_64 packages.

- **Linux:** extract the whole `.tar.gz`, then run `./start.sh`.
- **Windows:** extract the whole `.zip` into a writable folder, then run `PaperFront.exe`.
- Keep all included runtime files together. No Godot editor installation is needed.
- Vulkan-capable graphics and current drivers are required. Linux requires glibc 2.38 or newer.
- Check `SHA256SUMS` for download integrity and `START_HERE.txt` for platform instructions.
- Watch `paper-front-trailer.mp4` for a short showcase rendered from the game.

These are initial preview packages. Windows is cross-compiled on Linux; Wine
checks do not establish compatibility with every Windows GPU and driver.
Gameplay balance and performance remain under development.

Local Linux normal-flow validation passed 41 checks both headless and with
Vulkan graphics; Windows Wine validation passed 12 portable checks and 41
normal-flow checks. The broad historical regression suite is not fully passing.
Developer showcase and menu-input diagnostics also have unresolved failures.
Read [the validation record](https://github.com/flitting/PaperFront/blob/main/docs/release_validation.md)
and the attached `build-validation.md` for the exact local and CI scopes.

## 中文

纸境战线是一款纸艺风格 3D 即时战略游戏，包含四个阵营、基地建设、
步兵小队与陆海空作战。本次发布提供当前游戏、中英文界面及语音选项，
以及可独立运行的 Linux 和 Windows x86_64 基础版本。

- **Linux：**完整解压 `.tar.gz` 后运行 `./start.sh`。
- **Windows：**将 `.zip` 完整解压到可写文件夹，运行 `PaperFront.exe`。
- 无需安装 Godot，请完整保留所有运行文件。
- 需要支持 Vulkan 的显卡及驱动；Linux 需要 glibc 2.38 或更新版本。
- 下载后可通过 `SHA256SUMS` 校验，平台使用方法见 `START_HERE.txt`。
- 宣传视频 `paper-front-trailer.mp4` 使用游戏内渲染画面制作。

这是基础试玩预览包。Windows 版在 Linux 上交叉编译，Wine 检查不能代表
全部 Windows 显卡和驱动兼容性。游戏平衡和性能仍在持续完善。

本地 Linux 的无窗口及 Vulkan 正常主流程各通过 41 项检查；Windows
Wine 通过 12 项便携检查及 41 项主流程检查。完整历史回归尚未全部通过，
开发展示及菜单输入诊断也有待解决的失败项，具体范围见
[验证记录](https://github.com/flitting/PaperFront/blob/main/docs/release_validation.md)
及随 Release 附带的 `build-validation.md`。
