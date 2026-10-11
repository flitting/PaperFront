# v0.8.0 release validation / 发布验证

Validation date: 2026-10-11 (Australia/Sydney). This is a Preview/prerelease of the base player build. The normal player startup checks below passed; the broader source regression suite and the separate developer diagnostics did **not** all pass. This record describes the observed scope and does not claim complete gameplay, campaign, performance or Windows hardware acceptance.

The public GitHub release is rebuilt by GitHub Actions from the tagged source. Its archive hashes can differ from the local build because the build information and source revision differ. Verify downloads against the **SHA256SUMS attached to that release**. The hashes below identify the runtime binaries tested locally, rather than promising identical CI archive bytes.

## Build and package checks

- Godot: `4.6.2.stable.official.71f334935`, with matching Linux and Windows x86_64 release templates.
- Linux native extension: rebuilt with GCC 13.3.0; libstdc++ and libgcc are linked statically. Its dynamic dependencies are glibc/libm and the ELF loader. The engine requires glibc 2.28, while the extension requires **glibc 2.38**, which determines the minimum for this package. The tested host is Ubuntu 24.04.
- Windows native extension: rebuilt with MinGW-w64 GCC 13.2.0 POSIX. The extension imports only `KERNEL32.dll` and `msvcrt.dll`; no separate libstdc++, libgcc or winpthread DLL is required. The portable launcher has version resources `0.8.0.0`.
- `Linux Shipping` and `Windows Portable` exports completed without Godot script/engine errors. Their shipping include/exclude filters are aligned.
- Each embedded PCK contains 5,347 entries. Directory and import/remap audits found no developer documents, tests, tools, historical artifacts, reference images or retired speech banks.
- Both packages contain the runtime, matching native sidecar, English-first bilingual startup instructions, current credits, engine/font/Godot C++/GNU runtime/MakeHuman/audio notices and current asset provenance. They contain no editor, test suite, generated user data or historical validation reports.
- Both archives were extracted and every listed `FILES.sha256` entry was checked. The Windows test path includes spaces and Chinese characters.

Rebuild with:

```sh
python3 tools/build_release.py --version 0.8.0 --output artifacts/release_20261011
```

This command builds and audits packages. It does not itself perform the runtime tests below. Required tools and release workflow are described in the main README.

## Runtime results

| Check | Result | Actual scope |
| --- | --- | --- |
| Linux source, headless `--verify-demo` | 41/41 passed, exit 0 | Real main/audio/settings/native resources, native lifetime call, speech and music assets, normal HUD startup, settings persistence, match setup, controlled win/loss/draw settlement and return flows |
| Linux exported runtime, headless `--verify-demo` | 41/41 passed, exit 0 | Same checks against the embedded PCK and distributed native sidecar |
| Linux exported runtime, real GPU `--verify-demo` | 41/41 passed, exit 0; no script/engine errors or warnings | Intel Arc (MTL), Vulkan 1.4.318, Forward+, X11, 960×540; real rendering during the same normal main/menu/match/settlement flows |
| Windows final portable launcher under Wine 11, `--verify-portable` | 12/12 passed, exit 0 | Extracted Chinese/space path, launch from `/tmp`, local `user_data` confinement, settings/save/cache/temporary paths and runtime license export |
| Windows exported runtime under Wine 11, headless `--verify-demo` | 41/41 passed, exit 0 | Embedded resources, native extension and the same main/audio/settings/match/settlement checks |

Wine ran with a separate prefix and private Xvfb display. Its bounded runs timed out zero times and left no Wine processes. The Windows runtime's exported engine notices matched the notices included in the packages. Audio used the Dummy driver: PCM resources and playback routing/state were checked, while physical speaker output was not listened to. Wine headless checks do not establish native Windows graphics, driver, performance or hardware compatibility.

The settlement checks remove buildings through real simulation routines to exercise the result UI. They are disclosed fixtures, rather than evidence of winning an economic/combat match through ordinary play. Campaign completion, all navigation/transport scenarios and sustained performance on target hardware were not covered by this release smoke run.

## Unpassed checks and known validation limits

1. The optional developer `--showcase` fixture resets and fills the same world with a staged army. On the actual GPU it produced a screenshot and exited 0, but emitted **537 native Dictionary missing-key errors** (including `root`, `art_root` and pose fields). It is **not** counted as a passed check. The normal `--verify-demo` GPU flow did not emit those errors. The cause of this developer-fixture failure is not resolved in v0.8.0.
2. The separate `--menu-smoke` synthetic input diagnostic did not fully pass on the actual desktop. At 1600×900 all four faction cards and the confirmation dialog passed; one of twelve popup cycles failed to open/select on its first selection attempt. A 960×540 run had additional injected-coordinate failures. Focus/scaling assumptions are possible causes, but have not been established; this diagnostic is **not** counted as passed. The normal main/menu flow checks above passed using actual control signals.
3. The broader source regression run was not fully green: multiple scenario, UI and native-equivalence assertions remain unpassed, and their causes have not all been diagnosed. Focused rechecks pass for the corrected AI planner fixture (106/106), developer tools (636/636), current fleet HUD (67/67), Wiki catalog (25,799/25,799) and localization (386/386); that does not establish a passing full suite. The final release notes report the broader regression outcome separately. No failed check is represented as a passing full-suite result.

The Wiki production-facility helper was also corrected to identify amphibious units' actual factory/shipyard names and carrier flight decks. Both platform runtimes were re-exported after this change.

One smoke harness issue was corrected before the successful tests: JSON numeric voice variants (`1.0`) were normalized to integers when constructing metadata keys, matching the actual audio loader's `1` keys. This corrects the validator comparison and does not alter audio or combat behavior.

## Local tested runtime identities

| File | SHA-256 |
| --- | --- |
| Linux `PaperFront.x86_64` | `b79535547e9fd3e6ea67af00cefd6459f9c6d3b1ddf6615b3eff85dc04437af3` |
| Linux `libpaper_front_kernels.so` | `ad58d2ad16b63aad8197126831d8b0dbe19b4f667046bdf16f591fca9c27bcfb` |
| Windows `bin/PaperFrontRuntime.exe` | `6d51a61d6f19dbfff62d58d435297b6e685da5c410b45ea873d8356537632d7d` |
| Windows `bin/paper_front_kernels.dll` | `d1d386157d4092664095940ccf53aaba465fdda191221b769d329eecb8505c06` |
| Windows final `PaperFront.exe` launcher | `e61abe30c385e06add8e38a5080283ba7c461a5cdd26a2d01cccd59f6d88eb29` |

## 中文说明

2026年10月11日验证了两个基础玩家运行包。Linux 源码无界面、导出无界面及 Intel Arc 实际 Vulkan 图形环境下的正常主流程分别通过 41/41 项；Windows 在独立 Wine 11 环境中通过便携路径/存取检查 12/12 项及无界面主流程 41/41 项。两个平台的原生扩展均重新编译，导出无脚本/引擎错误，PCK 每包 5,347 项且没有开发文档、旧报告、测试、参考图或退役语音。运行包含当前许可、来源记录与中英文启动说明。Linux 需要 glibc 2.38 或以上；Windows 无需另装 Godot 或 GNU 编译器运行库。

这是基础试玩 Preview 预发布版本，**不是全量回归全部通过的声明**。广泛源码测试仍存在多项场景、UI 和原生实现一致性断言未通过，原因尚未逐项诊断；修正后的专项检查通过：AI 规划 106/106、开发工具 636/636、现役海军 HUD 67/67、百科目录 25,799/25,799、中英文界面 386/386，但不能据此宣称完整回归通过；独立 `--showcase` 开发展示夹具产生 537 条原生 Dictionary 缺键错误；实际桌面的 `--menu-smoke` 注入输入诊断也未全通过。这些项目均明确记为未通过，原因及精确范围见上文和发布说明。正常 GPU 主流程 41 项未出现上述原生错误。未进行 Windows 实机/图形驱动验收、目标硬件持续性能验收、完整战役通关或实体音频试听。

GitHub Actions 会从标签源码重新构建正式下载包，其 ZIP/TAR 哈希可能与本地不同。请始终使用该次 GitHub Release 附带的 **SHA256SUMS** 校验下载；上表是本地实际接受 smoke 检查的运行时文件哈希。
