# Native performance kernels

Paper Front keeps its authoritative game state in [simulation.gd](../scripts/simulation.gd). The project-authored `PaperFrontKernels` GDExtension accelerates unit updates, movement, spatial queries, collision geometry and rendering submission. It does not replace the game rules, reduce entity counts or slow the simulation clock to raise reported frame rate.

The extension uses vendored, MIT-licensed **godot-cpp**, pinned to commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (Godot 4.5 API, used with Godot 4.6.2). No binding download is required. Godot itself is not modified. Notices are in [assets/native/GODOT_CPP_LICENSE.md](../assets/native/GODOT_CPP_LICENSE.md).

## Build Linux x86_64

Requires CMake 3.17+, Make, a C++17 compiler and Python 3. From the repository root:

```sh
./tools/build_native.sh
```

Output: `assets/native/libpaper_front_kernels.so`. Build files go to `native/build/`. The standard release build statically links GCC's libstdc++/libgcc while leaving glibc dynamic. The v0.8.0 build requires glibc 2.38 or newer; the build manifest records the requirement detected from the actual library.

## Cross-build Windows x86_64 on Linux

Install a MinGW-w64 POSIX x86_64 toolchain, or set `PAPER_FRONT_MINGW_BIN` to its `bin` directory:

```sh
./tools/build_native_windows.sh
./tools/build_portable_launcher.sh
```

The extension output is `assets/native/paper_front_kernels.dll`; its build directory is `native/build-windows/`. MinGW's relevant C++/gcc/pthread runtimes are linked statically. The release tool checks DLL imports so players need no loose compiler-runtime DLLs. Building the portable launcher icon also requires ImageMagick and Python Pillow.

To export and package both player builds with the matching Godot 4.6.2 export templates:

```sh
python3 tools/build_release.py --version 0.8.0 --output artifacts/release_20261011
```

Linux packages keep the `.so` beside `PaperFront.x86_64`; Windows packages keep the `.dll` beside `bin/PaperFrontRuntime.exe`. Do not distribute the executable alone. [Release notes](../docs/release_notes.md) state actual validation scope; a successful cross-build is not Windows hardware play testing.

## Reference paths and validation

GDScript reference paths remain available for focused comparisons:

| Environment variable | Comparison path |
|---|---|
| `PAPER_FRONT_DISABLE_NATIVE=1` | Disable native kernels in simulation and world presentation |
| `PAPER_FRONT_SCRIPT_UNITS=1` | Script unit state-machine dispatch |
| `PAPER_FRONT_SCRIPT_GEOMETRY=1` | Script collision/geometry queries |
| `PAPER_FRONT_SCRIPT_MOVEMENT=1` | Script ground movement |
| `PAPER_FRONT_SCRIPT_WORLD=1` | Script world iteration |
| `PAPER_FRONT_SCRIPT_BATCHES=1` | Script render batches |
| `PAPER_FRONT_BATCH_SETTERS=1` | Per-instance setters instead of whole-buffer uploads |
| `PAPER_FRONT_RENDER_NODES=1` | Hidden render-node hierarchy instead of lightweight pose meshes |

These are diagnostic controls, not separate gameplay modes. Compiler flags deliberately exclude fast-math and fused contraction to preserve ordering and target-distance ties. Rendering uses the current authored model/material/animation and distance tiers; historical simplified native pose benchmarks do not describe the current visual configuration.

Run `PAPER_FRONT_GODOT=godot ./tools/test.sh` after rebuilding. Relevant checks include native nearest-target and lifetime tests, whole-tick/save-load equivalence, geometry, movement, world synchronization, render batches, model provenance and support repair. The runner treats script/engine errors and resource leaks as failures even when Godot exits with status zero.

The binding generator has a local [container assignment patch](patches/container-assignment.patch). It fixes release/self-assignment of Dictionary references; the patch and patched source must travel with rebuilds. `native_lifetime_tests.gd` checks this behavior.

For performance measurements, run only one GPU benchmark at a time and do not compile or run CPU-heavy tests concurrently. Record the actual build, resolution, quality, scene, unit counts, simulation time and wall-clock frame timing. Historical reports are evidence for their own builds rather than guarantees for the current release.

## 中文

规则状态仍由 GDScript 的 `WarSimulation` 管理，C++ 内核负责高频更新、移动、空间查询、碰撞和批量提交；不会通过减少单位、降低规则更新频率或放慢时钟伪造性能。

Linux 使用 `./tools/build_native.sh`；在 Linux 上交叉编译 Windows 使用 `./tools/build_native_windows.sh`。两平台完整打包命令见上文，需要与 Godot 4.6.2 匹配的导出模板。发布必须保留相邻原生库、许可与来源，构建通过不代表 Windows 实机验收。

重建后运行对应回归和原生/脚本等价测试；环境变量仅供对照诊断。GPU 性能测试单独执行，记录完整场景与画质条件。当前发行验证范围统一见发布说明。
