# 640 地图整体验收与交付结果

> 后续更新：用户要求恢复完整模型细节并修复景深，已撤回本报告对应构建的显示降面与材质取舍。以下为优化任务关闭时的历史实测，不能表示最新视觉恢复版的帧率；当前改动见 [视觉恢复记录](visual_fidelity_restoration.md)。

日期：2026-10-03，Australia/Sydney。构建为 Godot 4.6.2 Linux x86_64 Release（Linux 预设保留 development 功能，便于本地验证）。

**规定的 1920×1080 基准通过：常态最低秒级和 P99 换算均达到 60 FPS；八方 120 秒持续混战两项均达到 30 FPS。原生全屏单独报告，没有将其 P99 低于 30 的结果混入基准通过结论。**

用户于本轮明确接受当前八方混战表现，要求本轮结束视为优化任务完成。本报告为最终交付记录，原生全屏尾帧及其他测量边界照实保留；历史记录中的“待完成”不再代表当前任务状态。

运行身份：`87ce08ce7b594051bc4b2fddc11744dcee2465068b4e2d72395c1be5755ae0fa`。

## 实际发行包成绩

所有项目均为 **100% 内部 3D 渲染**，输出与内部像素相同；关闭 VSync，预热 8 秒，GPU 测试串行执行。设备：Intel Core Ultra 9 185H / Intel Arc Graphics MTL，Vulkan Forward+。音频逻辑执行，输出总线静音。

| 场景 | 输出及内部像素 | 采样 | 平均 FPS | 最低 1 秒 FPS | P99 ms / 换算 FPS | 最大帧 ms |
|---|---|---:|---:|---:|---:|---:|
| 常态（均衡档） | 1920×1080 | 30.0 s | 86.46 | 81.62 | 14.868 / 67.26 | 20.797 |
| 八方混战（性能档） | 1920×1080 | 120.0 s | 42.24 | 38.79 | 33.156 / 30.16 | 81.708 |
| 原生全屏八方（性能档，对照） | 3072×1920 | 30.0 s | 34.06 | 33.62 | 35.104 / 28.49 | 39.880 |

`1000 / P99` 是本项目的尾帧指标，不是所有软件通用的“1% low”。长测 P99 距 33.333 ms 预算约 0.18 ms，余量较小；最大单帧仍有尖峰，不声称所有帧都超过目标，也不推广为任意硬件/镜头/规模的保证。

原始报告：[常态](../artifacts/performance_640/phase19/normal_30s.json)、[八方长测](../artifacts/performance_640/phase19/stress_120s.json)、[全屏](../artifacts/performance_640/phase19/fullscreen_30s.json)。三个报告来自同一个实际导出程序。

## 负载与玩法边界

- 常态始终 96 单位（88 地面 / 8 飞机）、24 建筑，双方最低各 44 地面 / 4 飞机 / 12 建筑。
- 八方始终 800 单位、160 建筑，每方最低 80 地面 / 20 飞机 / 20 建筑。Rivet、Kestrel、Iron、Sky 四种完整模板各由两个独立所有者使用；包含新导入的 Iron、Sky。
- 长测实际补充 13,424 个阵亡单位和 4 座建筑，发生 67,161 次开火、623 次补给完成、693 次返航事件。幸存者不回血，死亡单位以新 ID 补充。
- 30 Hz 模拟保持不变，常态/长测/全屏模拟与墙钟比约为 0.99993 / 1.00021 / 0.99983。
- 八方采用固定战斗命令和测试预备队，未声称运行八套完整经济战略 AI；实际建造/生产/采矿/返航规则仍执行。正常对局也不使用测试预备队。

## 优化内容与视觉

原生内核处理高频查询、单位状态机、移动、维修及显示数据；保持更新顺序与规则，并提供脚本对照路径。固定模拟 tick 与渲染提交受控重叠。模型/批次缓存减少重复建立和字典访问；初始化 MultiMesh 的 CPU 缓存，避免上传方式切换时同步 GPU 回读。修复了派生缓存的外部删除失效和测试脚本错误未影响退出码的问题。

640 地形附带三种精确预制资源，使用源码/地图指纹验证；失效时重新生成。远树冠及单位 LOD 保留来源校验。远景树干仅在性能/均衡/原生档的 90/110/140 米以外省去细线几何，树干/树根其余三角形与保守剔除边界保留。近中景不变；固定图像约 0.0657% 像素变化，平均每通道差 0.00396/255，明确不是完全无损。性能档已有粒子、尸体和材质预算继续保留，其范围见优化记录。

最终原生显示与同一场景的全脚本参考图像逐像素一致：[最终对照](../artifacts/performance_640/phase19/visual_comparison.json)。已审查原生全屏、树干 LOD 和战斗截图。算法/缓存对照不意味着删掉所有画质档间差异。

## 启动与交互

实际发行包在新用户数据目录中测得；没有清除操作系统文件缓存，因此不称为磁盘冷启动。

| 检查 | 结果 |
|---|---:|
| 640 对局准备总时间 | 6.558 s |
| 地图生成 | 1.492 s |
| 导航初始化 | 3.828 s |
| 预制地形加载与世界地形构建 | 1.091 s |
| 卡片资源预热 | 26.53 ms |
| 首次总部模型同步 | 19.72 ms |
| 测试夹具一次加入完整 96 单位/24 建筑后的模型同步 | 204.72 ms |
| 首次合法开火 CPU / 完成绘制 | 1.19 / 11.17 ms |
| 树冠点选 P95 / 最大（100 次） | 2.666 / 3.065 ms |
| 镜头平移/缩放 CPU P95 | 1.912 ms |
| 镜头操作到完成绘制 P95 / 最大 | 19.081 / 20.481 ms |

树冠重复点选目标一致，全屏切换后的输入坐标往返检查通过。上述交互检查冻结战斗规则，不能当作游戏 FPS；首次批量装入模型仍有一次性成本。明细：[发行包交互检查](../artifacts/performance_640/phase19/interaction_export.json)。

## 验证与证据审计

| 要求 | 证据及范围 | 结论 |
|---|---|---|
| 常态 60 / 八方 30、真实模拟与配额 | 同包三份帧率 JSON；八方主验收采用 120 秒 | 基准通过；原生全屏为单独对照 |
| CPU 尾帧 | 固定 800 单位、900 tick 纯 CPU：均值 10.031 ms、P99 13.287 ms，低于 20 ms 预算；不当作 FPS | 通过 |
| 缓存、机场、伤亡、规则调整、存读档 | 串行及线程逐 tick 对照分别 6,002 项；维修、几何、飞机和夹具测试 | 通过 |
| 运输、施工、修桥、经济与战斗 | 完整回归含运输/工程输入、脚手架接手、桥断路与实际采矿/建造/开火并行推进，以及存读恢复 | 通过；非八套完整策略 AI 验证 |
| 模型池、批次、相机、拾取 | 缓存 11,528 项、显示 7,681 项、真实后端批次 887 项、屋顶点选 54 项及实际交互检查 | 通过 |
| 离线资源与四阵营 | 单位 LOD 来源 2,630 项，树冠/阴影与景物检查；导出 56 单位/56 建筑、112 Wiki 条目 | 通过 |
| 统一回归 | `tools/test.sh`，现在遇到脚本/引擎错误或泄漏即失败；最终日志无该类错误 | 通过 |
| Linux 发行与复现 | 当前源/规则/资源清单，实际 release 程序、原生侧库及同包测量 | 通过；文件校验与运行方法见交付目录 |
| Bevy/ECS 文档 | 最终 CPU/GPU 数据、理论情景与未实测边界 | 文档完成；未执行迁移 |

完整证据：[统一回归](../artifacts/performance_640/phase19/regression.log)、[CPU](../artifacts/performance_640/phase19/cpu_final_900.json)、[阵营导出](../artifacts/performance_640/phase19/export_factions.log)、[Wiki 导出](../artifacts/performance_640/phase19/export_wiki.log)、[运行清单](../artifacts/performance_640/phase19/build_repair/manifest.json)。更早阶段的失败、改动和对照保留在 [优化记录](performance_640_optimization_notes.md)。

[交付审计](../artifacts/performance_640/phase19/completion_audit.json) 已核对同一运行身份、阵营/配额、真实时间推进、日志、交互与图像对照，以及正式目录程序/侧库和实测构建的逐文件 SHA-256 一致性。

## 运行与复现

交付程序位于 `artifacts/linux/PaperFront.x86_64`，必须与 `libpaper_front_kernels.so` 同目录；无需安装 Godot。

完整发行压缩包为 `artifacts/PaperFront-linux-x86_64.tar.gz`，相邻 `.sha256` 可校验下载/复制结果；包内 `BUILD.sha256` 校验实际已测的程序与侧库。旧发行目录与旧压缩包保存在 `artifacts/performance_640/original_linux_release/`。源码、资源、测试和原生依赖快照为 `artifacts/performance_640/phase19/source_final.tar.gz`，附独立校验文件；不包含临时构建目录和历史性能产物。Bevy 可行性及收益边界见 [迁移评估](bevy_ecs_migration_assessment.md)。

```sh
cd /home/gc/workspace/paper_war/artifacts/linux
./PaperFront.x86_64
./PaperFront.x86_64 --disable-vsync -- --performance-case normal --quality balanced --render-scale 1.0 --seconds 30 --performance-output /tmp/paperfront-normal.json
./PaperFront.x86_64 --disable-vsync -- --performance-case stress --quality performance --render-scale 1.0 --seconds 120 --performance-output /tmp/paperfront-stress.json
./PaperFront.x86_64 --disable-vsync -- --performance-case stress --performance-fullscreen --quality performance --render-scale 1.0 --seconds 30 --performance-output /tmp/paperfront-fullscreen.json
./PaperFront.x86_64 --disable-vsync -- --verify-interactions --interaction-output /tmp/paperfront-interactions.json
```

一次只运行一个 GPU 测量，不同时编译或运行其他重负载测试。窗口分辨率由测试设置，全屏测试实时读取当前屏幕大小。`PAPER_FRONT_DISABLE_NATIVE=1`、`PAPER_FRONT_RENDER_OVERLAP=0` 等对照开关见 native/README.md；不将对照模式当作默认成绩。
