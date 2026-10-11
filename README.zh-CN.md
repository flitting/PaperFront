# 纸境战线 · Paper Front

[English](README.md)

**组建纸上军团，争夺最终定稿。**

《纸境战线》是一款发生在手工桌面模型世界中的即时战略游戏。纸板基地、剪纸步兵、装甲车队、飞机与舰队，在四套相互竞争的“正确图纸”之间展开工业战争。

[下载 v0.8.0 试玩版](https://github.com/flitting/PaperFront/releases/tag/v0.8.0) · [观看高清宣传视频](https://github.com/flitting/PaperFront/releases/download/v0.8.0/paper-front-trailer.mp4) · [文档索引](docs/README.md)

[![点击观看纸境战线高清宣传片](media/poster.jpg)](https://github.com/flitting/PaperFront/releases/download/v0.8.0/paper-front-trailer.mp4)

## 游戏内容

- 单人对抗最多三名电脑，四个可玩阵营，玩家颜色与阵营身份独立。
- 六张 320 × 320 战场：森林、沙漠、雪原、河港城市、种子城市与群岛；另有 192 × 192 的两军对称地图。
- 一关正典军团教程，涵盖经济、工程与战斗。
- 基地建设、晶矿经济、局部供电、科技、小队步兵、装甲、航空与海军、运输和驻军。
- 可破坏桥梁与障碍、工兵维修和占领、护甲穿透、溅射友伤及星级单位。
- 游戏内图鉴、真实模型预览、音频浏览器，以及结算曲线和 JSON/CSV 对局报告。
- 界面与语音均支持 English / 简体中文，可以分别选择并保存；两项默认英语。游戏和发行包音频可离线运行。

当前提供桌面单人版本；暂无真人联网、手机、网页或 macOS 发行包。数值平衡和大规模战斗性能仍在完善。

## 下载与启动

从 [GitHub Releases](https://github.com/flitting/PaperFront/releases/tag/v0.8.0) 下载并完整解压：

| 系统 | 文件 | 启动方式 |
|---|---|---|
| Linux x86_64 | `PaperFront-v0.8.0-linux-x86_64.tar.gz` | 在解压目录运行 `./start.sh` |
| Windows x86_64 | `PaperFront-v0.8.0-windows-x86_64.zip` | 双击根目录 `PaperFront.exe` |

玩家无需安装 Godot 或编译器。请保留整个目录，不要只移动主程序。Windows 须通过根目录启动器运行，以将数据保存在便携目录中。

Linux 解压后在完整发行目录中运行：

```sh
chmod +x start.sh PaperFront.x86_64
./start.sh
```

需要 64 位系统、键鼠与支持 Vulkan 的显卡和驱动；最低窗口 1100 × 700，建议使用更大的显示空间。Windows 面向 Windows 10/11 x64；Linux 需要 glibc 2.38 或更新版本。具体构建、检查范围及已知限制见 [v0.8.0 发布说明](docs/release_notes.md)与[验证记录](docs/release_validation.md)，Windows 交叉编译或 Wine 检查不代表 Windows 实机验收。性能不足时可在设置中降低画质或 3D 渲染倍率，界面仍使用原始分辨率。

## 四个阵营

| 阵营 | 特点 |
|---|---|
| 正典军团 · Canon Legion | 精锐步兵搭配廉价装甲，基础工业成型快，高级科技投入昂贵。 |
| 重锤军团 · Heavy Hammer Legion | 武装工兵现场搭建全部建筑，基地兵营可反复建造；以矿脉钻机、重坦与轰炸飞艇支撑扩张。 |
| 长钉军团 · Long Nail Legion | 铁路运输、装甲列车与耐用车辆；矿车及列车依赖己方轨道，符合条件的车辆可脱战自修复。 |
| 天翼教团 · Skywing Order | 昂贵而脆弱的高科技：EMP、激光、束流、强力航空与独特的创世之手。 |

价格、前置和能力以生产卡、图鉴及[当前规则目录](docs/faction_catalog.md)为准。

## 如何开始

1. 先玩教程，或在遭遇战中选择阵营、地图和电脑。初学陆战可选择两方的明原对称场。
2. 正典、长钉和天翼先选总部，建设电站、精炼厂和兵营；建筑订单完成后还需放到合法位置。长钉矿车需要己方铁路连通。
3. 重锤先从基地兵营训练工程兵，再选工兵放置施工现场与矿点钻机，随施工进度付款；新基地兵营用于扩张。
4. 保持供电和生产出口通畅，逐步解锁工厂、机场和科技设施。
5. 训练步兵小队与支援载具，拖框选择、右键行军或攻击，**Z 后左键**指定攻击移动。
6. 摧毁敌方所有计入生存的建筑获胜；围墙、拒马与铁路不能单独维持阵营存活。

普通战斗步兵按 2–6 人小队购买，工兵仍为单人。每名成员独立计算生命、经验、碰撞和运输座位；命令以小队为单位下达，价格与时间是整队总额，伤亡不会免费补充。

## 常用操作

| 输入 | 功能 |
|---|---|
| 左键 / 拖框；Shift | 选择 / 多选；增减选择或追加命令 |
| 右键 | 移动、攻击，以及维修、占领、登乘和驻军等情境操作 |
| Z / X / C / G | 攻击移动 / 停止 / 路径点 / 巡逻；需要目标的命令随后左键指定 |
| H / F 后左键 | 强制攻击 / 强制移动；强制攻击可伤及友方与中立物 |
| Ctrl + 1–6 / 1–6 | 保存 / 选择编队 |
| 生产设施选中时右键 | 设置集结点 |
| B | 飞机返航；矿车回厂卸矿 |
| L / U 后左键 | 运输机降落 / 运输载具前往卸载；查看己方驻军房屋时 U 撤出 |
| 放置建筑时 R / 放置铁路时 V | 旋转建筑 / 切换铁路朝向 |
| WASD / 中键拖动 / 屏幕边缘 | 平移镜头 |
| Q / E；滚轮；非放置时 R / T | 环绕；缩放；调整俯角 |
| 空格 / Home | 跳到最近交战热点 / 回基地 |
| P / Pause；F5 / F9 | 暂停；保存 / 读取 |
| Esc / 齿轮 | 取消当前操作或打开设置 |

## 存档与设置

Linux 数据默认保存在 `~/.local/share/godot/app_userdata/纸境战线 · Paper Front/`；Windows 便携包保存在启动器旁的 `user_data/`。存档为 `skirmish_v1.pfront`，偏好为 `settings.cfg`，结算报告位于 `match_reports/`。旧存档带自己的规则快照，查看最新机制请新开对局。

设置了 `XDG_DATA_HOME` 时，它会替代 Linux 路径中的 `~/.local/share`；应用目录名来自 `project.godot` 的 `application/config/name`，不能按仓库文件夹名推定。Windows 日志位于 `user_data/logs/godot.log`，缓存与临时文件也留在便携目录；升级或移动时保留整个 `user_data/`。更多存储与重置说明见 [Windows 便携版](docs/windows_portable.md)。

## 源码、构建与反馈

源码需要 **Godot 4.6.2 stable 标准版**，克隆后运行 `./run.sh`；可用 `PAPER_FRONT_GODOT` 指定引擎。项目采用 GDScript 与 C++ GDExtension，无需 C#/.NET：

```sh
git clone https://github.com/flitting/PaperFront.git
cd PaperFront
./run.sh
# 指定引擎路径时：
PAPER_FRONT_GODOT=/path/to/godot ./run.sh
```

根目录启动器始终运行当前源码并按需导入资源。在 Windows 上可用 Godot 4.6.2 打开 `project.godot`，按 F5 运行工程；导入后也可运行 `godot --path .`。Linux 随仓库提供的 `.so` 不能替代 Windows 原生库，需为对应平台构建。

原生内核需要 CMake、Make、C++17 编译器和 Python 3，通过 `./tools/build_native.sh` 重建。Windows 交叉编译另需 MinGW-w64 POSIX 工具链及启动器图标依赖，其中图标制作使用 ImageMagick 与 Pillow。发行导出需匹配的 Godot **4.6.2 导出模板**。两平台打包使用：

```sh
python3 tools/build_release.py --version 0.8.0 --output artifacts/release_20261011
PAPER_FRONT_GODOT=godot ./tools/test.sh
```

`PAPER_FRONT_MINGW_BIN` 可指定解压后的 MinGW 工具链目录。构建文件与诊断记录位于默认忽略的 `artifacts/`。完整回归不仅检查进程退出码，还会检查脚本/引擎错误与资源泄漏；实际执行范围和未通过项目见发布说明，列出命令不代表所有历史测试均通过。

无渲染对局与独立逻辑导出：

```sh
./tools/run_headless.sh --map symmetric --factions kestrel,sky --ai both \
  --ai-styles balanced --difficulty normal --duration 120 --output /tmp/paper-front-match
./tools/build_headless.sh
```

详见[无渲染运行和统计](docs/balance_preparation.md)、[AI 数值实验](docs/ai_balance_experiments.md)与[独立策略模块](docs/independent_ai_duel.md)。构建和检查细节见[工程接口](docs/architecture.md)、[原生模块](native/README.md)与[发布说明](docs/release_notes.md)。反馈问题请在 [Issues](https://github.com/flitting/PaperFront/issues) 附复现步骤、版本、系统、阵营、地图/种子和日志。

## 制作与许可

项目没有覆盖全部源码的统一许可；请分别查看[素材与依赖许可](assets/LICENSE.md)及发行包内的 `LICENSES/`、`PROVENANCE/`。原创 CC0 美术、合成语音和供应商生成音频的授权范围分别记录；中英文语音均为合成声音。用户提供的风格参考仅用于文档，不进入玩家包。

Godot 与 godot-cpp 使用 MIT，Noto CJK 字体使用 SIL OFL，创世之手基础图形网格来自 MakeHuman 的 CC0 资产。各项许可只覆盖其所指组件，素材或依赖许可不会自动给整个游戏源码授权。

## 工程结构

| 路径 | 用途 |
|---|---|
| `data/rules.json` | 经济、阵营、单位、建筑、武器与前置 |
| `data/localization/` | 英语翻译目录；规则与存档中的中文源标识保持稳定 |
| `scripts/simulation.gd` 与相关模块 | 权威规则及存档状态 |
| `scripts/main.gd`、`paper_hud.gd`、`paper_world.gd` | 输入、镜头、界面与只读呈现 |
| `native/` | C++ 内核、固定版本 Godot C++ 绑定与构建配置 |
| `assets/` | 图像、声音、着色器、字体及来源 |
| `tests/`、`tools/` | 回归、资产工具、无渲染实验与打包 |
| `docs/` | 当前指南、参考资料及保留的实验记录 |
| `media/` | 宣传片、海报与截图 |

宣传视频及截图来自游戏引擎内渲染的编排展示场景。最新宣传片长 29 秒，以真实 4K 游戏内模型画面与受控战斗片段制作，输出为 **1920×1080**。模型镜头为编排展示；战斗通过普通命令与模拟推进，不称为玩家自然操作实录。
