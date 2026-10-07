# 导航修正与后续改造交接（2026-10-07）

产品源码已冻结。只保留经过最终回归的版本；没有扩大地形碰撞架构。本轮没有改变单位速度、原始体积、到达容差、伤害、建造/生产成本、地图边界或敌军碾压规则。

## 保留的改动

- `simulation.gd` 提供 `set_player_navigation_priority(ids)`；选中己方单位优先，其次是刚下令的三秒服务期，普通等待队列保持同级 FIFO。后台请求不会抢占最后四个 foreground 槽。总并发仍32、每 tick 32次提交，管理预算750μs。
- `path_worker.gd` 与 `path_worker_pool.gd` 对已排队任务进行优先排序；取消选中恢复原基础优先级，不锁住游戏线程。
- 大车可以要求更早生成、正在移动的己方步兵温和让路。队形前后落点沿行军方向分配，列按横向位置、列内按预计到达顺序分配；停车列之间留有原车身尺寸可通行的空间。共享路径拐点在 worker 内提供有限的分散入口，完整验证静态连接。
- 车对车保留原有 ID 仲裁、退让传播和退距。当前版本没有承诺所有拥挤布局都不会堵住。选中/新下令的 foreground 可以优先获得退让；已到达的闲置选中单位也可以让行，hold-position 仍不能强推。
- 让行结束清除旧 avoid/reversing/传播源，平坦且完整静态安全的路线可重接保存路径的可见后缀；水、悬崖、BLOCKED 边缘交回 worker 生成入口。保存可选命令优先级时限与几何 epoch，旧存档安全默认，待规划存档继续保持一致。
- 追击缓存接近点，目标位移触发限频更新；可直达时更新最后一段，受阻时沿原有安全路径继续移动，异步替换验证入口后才切换。原生 UnitTick 使用同一追击/让行完成 helper。

## 最终版本的实际证据

都是30Hz真实异步模拟，每 tick 给 worker 1ms 墙钟调度机会；这是压缩的纯模拟 fixture，不是游戏渲染 FPS，也不是玩家实机到达用时保证。

| 场景 | before | 最终保留版本 |
| --- | --- | --- |
| 48混编、8m真实静态 gate | 原始40秒到达36/48，289次提交；before脚本续跑48全到63.57秒/322次提交 | 40秒到达44/48；48全到54.17秒，94次提交，等待单位帧14157 |
| 单选坦克处于四个正在移动的步兵间 | 原始10.7秒，148等待帧 | 6.63–6.70秒，27–29等待帧 |
| 坦克追击移动坦克、20秒窗口 | 216等待帧，2次开火，6次寻路 | 0等待帧，6次开火，1次寻路 |
| 移动目标绕墙追击，native与script各30秒 | 本轮新功能控制 | 各9次开火、8次寻路、31–32等待帧，0静态穿越 |
| 96混编、正常120秒持续模拟 | 没有相同isolated fixture的可靠before数字，不提供百分比提升 | 96/96全到；两个样本最后到达101.73/95.73秒，第二份持续到120秒且result为空 |
| 倒序ID的8坦克狭道、真实append让行 | before原脚本3次倒序完成32.2/64.8/22.5秒 | 最终候选3次完成23.23/21.87/31.30秒；append让行队列均13秒完成，120/120断言 |

48与96最终 fixture 都记录0静态穿越、所有单位HP保持原值、最多32个in-flight。48管理最大471μs、本地查询395μs；96完整窗口管理732μs、本地798μs。另96提前全到样本单个不可分查询结束时本地累计1050μs，体现软时间预算最后一个查询的少量超出，不宣称严格硬上限。48模拟 tick P95约1.75ms、96完整窗口约2.89ms，仅供本机该 fixture，不能换算实机渲染 FPS。

原 `final_candidate_96.json` 无效：停车区进入东北敌HQ射程，正常胜利在68.17秒结束模拟。修正 fixture 只将敌HQ放在西北(3,4)以隔离导航；没有增加HP、关闭伤害、移动测试单位或禁用胜利规则。`final_candidate_96_isolated.json`、`final_candidate_96_window120.json` 才是有效证据。

## 最终检查

`artifacts/navigation_revision_20261007/checks/summary.json`：10组最终检查，6720项通过，无脚本、资源、引擎错误或泄漏警告。包括 overlap线程执行的6002项 native/script 完整 tick 等价、269项15个狭道/停止/死亡/hold/append控制、70项导航/存档、152项任意角度与连续接触、74项200ms真实延迟worker预算、19项吞吐、19项几何失效、20项让行路径、62项空中导航、33项优先级与追击。

最终检查列表没有代表整个仓库所有测试。历史实验日志保留供排查，不能把它们作为最终PASS，或把被回退分支45秒/96单位74秒标为保留成果。

## 被回退的实验与底层风险

更激进的35/65度 detour评分、按turn_speed延长承诺、前视commit、同车型空间排名及普遍加大车对车退距在异步重复狭道里出现不稳定失败，已回退。当前 `ground_movement.hpp` 与原before版本一致，已重新构建 `.so`；仅 UnitTick 的追击/让行完成调用保留。

值得新session检查的底层不一致：实际移动/standing 在部分地形区域使用8方向半径采样，而worker使用连续圆形/矩形地形边界。BLOCKED角落的某些真实圆相交位置可能被实际采样视为合法，worker却拒绝它作为路径起点。不要用减小半径、加大到达容差、关掉伤害或清除障碍来隐藏问题。

最小几何例：平地48×48；将x=21..26的全部格设为BLOCKED，保留z=23和24两行LAND。半径.75，中心(20.428,24.800)到墙角(21,25)距离约.606。真实圆与角落相交，但0°/45°等八个外圈点可能没有进入BLOCKED格；连续worker connector会拒绝。可用原`tests/demo_navigation_control_tests.gd -- --cases tank_fifo8_reversed_ids`反复观察角落与等待轨迹，但当前稳定候选不是保证每次都会生成该问题点。`checks/reversed_commit_2.json`等失败实验保留出现问题的路径/位置；只是证据，不是当前产品源码。

另需后续审查：同类退让传播没有严格的全局无环证明；96密集部队仍有长队尾和较多等待帧；当前GroupNavigation helper已不参与运行，旧portal预约文档不应误当实际实现。

## 复现与修改范围

运行最终fixture：

```sh
godot --headless --path . --script res://tools/profile_mixed_navigation.gd -- --output=res://artifacts/navigation_revision_20261007/replay48.json --mixed-seconds 120
godot --headless --path . --script res://tools/profile_mixed_navigation.gd -- --output=res://artifacts/navigation_revision_20261007/replay96.json --mixed-seconds 120 --mixed-rows 12 --full-window
godot --headless --path . --script res://tests/navigation_priority_pursuit_tests.gd
godot --headless --path . --script res://tests/demo_navigation_control_tests.gd -- --output res://artifacts/navigation_revision_20261007/replay_controls.json
godot --headless --path . --script res://tests/native_unit_tick_tests.gd -- --threaded-tick-equivalence
```

下一session可从 `simulation.gd` 的 `_traffic_may_yield`、`_request_movement_yield`、`_complete_movement_yield`、`_movement_clear`、`_segment_static`、`_pursue_target`、队列服务入口开始；worker的连续terrain connector在 `path_worker.gd`/`path_terrain_geometry.gd`；对应native在 `ground_movement.hpp`/`geometry_queries.hpp`/`unit_tick.hpp`。保留main已接好的 `set_player_navigation_priority`。`_kill_entity` 的死亡/上下落惯性元数据由Root负责，本轮导航未改该区块。

新的大规模改造应先对齐真实native/GDScript与worker地形体积判定，再考虑无环瓶颈协调或动态路径更新。不要把音频、Wiki、设置、world、HUD、结算、main等其他已完成修改卷入导航回退。所有文件有原先dirty工作；before备份在`artifacts/navigation_revision_20261007/before_source/`，`.gd.txt`保留原内容以避免Godot全局类扫描冲突。当前源码/so校验值见最终summary。
