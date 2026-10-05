# 工程接口（开发约定）

## 入口与 Wiki 接口（2026-10-02）

`PaperHUD.entry_menu` 与 `PaperHUD.wiki` 为遮挡战场输入的全屏纸板Control；入口打开原有战局设置，设置菜单也提供Wiki与返回入口动作。`main` 保存Wiki前的暂停状态，局内查阅暂停，关闭恢复；入口/Wiki在显示期间停止隐藏战场视口的渲染。

`WikiCatalog.entries(rules,faction,kind,query)` 返回稳定目录，`sections(rules,id)` 返回 `{title,rows:[{label,value,source_path,raw_value}]}`。所有实际数值/布尔字段与武器倍率自动收录，新增嵌套数值字段有fallback；目录/详情都不改原规则。

`WikiModelPreview` 使用独立`SubViewport.own_world_3d`，只读真实VolumeModels与PaperWorld纸片，不创建模拟。公开 `set_entry` / `clear_preview` / `set_preview_active` / `set_rotation_active` / `toggle_rotation` / `reset_rotation` / `set_preview_team`；隐藏时停渲染/处理，自动或手动旋转按所有实际mesh边界整圈取景。

`PaperWiki.configure/open_catalog/close_catalog/select_entry` 组织目录、上方模型和下方滚动详情表，`closed`信号返回原菜单。当前49条目全部可查，不受生产前置和历史存档快照限制。导出程序 `--headless -- --verify-wiki` 验证完整目录、所有页面模型与表格、返回入口和正常开局。

## 总部、工程兵与操作规则（2026-10-02）

正常 `build(team,spec,builder=-1)` 永久拒绝 `role:"hq"`。每方同时最多拥有一座存活总部；`capture_error(engineer_id,target_id)` 检查工程兵、敌方建筑及总部数量，围墙和拒马不可占领，防御塔可占领。`issue(ids,"capture",pos,target)` 到建筑边缘立即转移所有权，保留建筑型号与生命，不消耗工程兵。原生产队列按未完成比例退款给原主人后清空；原主人飞机解除被占领机场的保障。

`outpost` 订单须提供己方存活工程兵，订单保存 `builder`。沿用全局建筑预建时间，电站前置仍生效；无需总部或已有扩建覆盖。就绪放置检查地形、边界和占地，然后向该工程兵下达 `{kind:"deploy_outpost",pos,target:-1,spec,cost}`，工程兵走到现场才生成分基地，保留原落地施工动画。预建期间工程兵失去后取消订单，按未完成比例退款。

工程兵 `repair_building` 到位后按缺失生命 × `economy.repair_cost` 一次收费并修至满血；资金不足时保留命令等待，不做部分修复，也不消耗工程兵。`repair_unit` 与 `repair_bridge` 延续原有持续维修与进度付费。总部、捕获、满修、分基地部署与存读的专项回归为 `engineer_rules_tests`。

相机平移使用 WASD；冲突指令移为 Z 攻击移动、X 停止、C 路径点。侦察车配置 `transport_capacity:1`，仅可运输一名 `art:"rifle"` 的己方普通步兵。普通步兵右键侦察车上车，选侦察车通过卸载按钮下车。

## 原图建筑体量修复接口（2026-10-02）

`faction_building_models.gd` 的22核心建筑以用户原始示意图和最新“完整实体体量”要求为视觉验收依据：主楼、屋顶、侧翼与工业设备组成实际房体，维修站保持开放但有实体机修模块。`solid_parts` 保存真实三角面区间；质量校验从真实网格积分重叠实体的并集，底板和细杆不算主建筑量。实际几何仍不得超出 `rules.buildings[id].size`。

`smoke_ports` 由建筑recipe返回烟囱口的本地坐标，并经 `VolumeModels.create_model` 交给 `PaperWorld`，替代写死的旧烟囱位置。模型、生产图标与单独场景由同一几何源重新导出。

`main._building_ray_hit` 对可见建筑网格做射线/三角面拾取，先用AABB过滤并缓存面数据；较高屋顶不再依赖固定高度的屏幕圆。被建筑表面遮挡的单位不抢屋顶选择，前方部队仍保留原点击容差。对应探针 `tools/check_building_roof_selection.gd` 验证真实屋顶投影和点选。

新增 `tests/building_mass_tests.gd` 检查质量测量器的反例与解析体积；`tools/check_faction_buildings.gd` 同时校验体量、足迹、颜色、部件区间和炮塔。参考前后固定世界尺度对照见 `docs/building_reference_repair.md`。

## v2 首发阵营与空军接口（2026-10-02）

当前规则目录：正典军团 `kestrel`、重锤军团 `rivet`，23 units / 26 buildings / 21 weapons。历史 ID 保留，公共名称来自 `rules.factions[id].name`。固定涂装由阵营决定，玩家识别色独立：team 0 `e7ad42`，team 1 `41c7c6`。下面早期接口中对目录数量、纸片步兵、producer 和 role 的列举以本节为准。

units 增加 `formal_name`, `description`, `voices:{select,move,attack,ready,return?:Array[String]}`, `domain:"ground"|"air"`, `armor_class:"infantry"|"armored"`。飞机必须配置 `producer:"airfield"`, `flight_height`, 整数 `ammo_capacity`, `rearm_time`。工程师可配置 `repair_radius` / `repair_rate`（HP/s）。weapons 可配置 `targets:["ground"]|["air"]` 和 `multipliers:{building?,armored?,infantry?:float}`；旧规则默认仅对地，未指定倍率默认 1。

buildings 的新增 role 为 `outpost` / `repair` / `command` / `airfield`。机场 `aircraft_capacity` 为正整数，机位由现有归属飞机与全部待生产订单共同预留，取消/死亡/转场释放。维修站 `repair_radius` / `repair_rate`，正常电力下付费修复范围内装甲地面单位，效果不叠加。指挥中心 `vision_bonus` 增加自动索敌范围，属于侦察协调参数；本工程没有因此新增战争迷雾系统。

空军实体另有 `flight_state:"airborne"|"returning"|"rearming"|"stranded"`, `ammo:int`, `home_airfield:int`, `rearm_remaining:float`, `flight_height:float`, `airborne:bool`。空军直接移动，不参与地面编队、碰撞、碾压、桥梁占道或桥断伤亡。空弹药触发自动返航，降落补给后恢复保留的任务；机场毁坏时重新寻找有容量的友方机场，无保障时等待。`issue(...,"return",...)` 主动返航，`repair` 对友方实体路由为 `repair_unit` / `repair_building`，桥梁沿用 `repair_bridge`。只有工兵执行维修。

空地武器在索敌、发射、弹丸影响三个阶段检查攻击域。对空弹丸记录 `target` 并更新追踪目标位置；projectile 另含 `targets`, `multipliers`, `source_height`, `target_height`，视觉表现保留高度与发射朝向。RulesLoader 与 SaveValidator 校验这些字段，旧地面规则快照仍可加载。

`VolumeModels.supports` 覆盖42种建筑/载具对象，7种步兵刻意排除并使用五动作纸片与固定80°镜像。步兵纹理有独立同UV的 `_identity.svg` 遮罩（白填、黑描线、透明底）；shader仅以mask.r×mask.a替换识别区域。飞机使用厚翼和尾翼；坦克炮塔仍独立。`PaperWorld` 将飞机 `art_root` 与血条升至飞行高度，地面选择圈和影子维持地面位置；主输入使用飞机实际空中投影进行点选、框选与编队定位。生产卡仍由 SVG 和 contours 驱动。

`PaperAudio.configure_units(rules)` 读取中文语音 manifest，`play_unit_voice(spec,action)` 使用独立语音总线和单一播放池，`unit_caption` 信号供字幕显示。96条中文合成 WAV 在 `assets/audio/voices`，manifest 保存对白、来源与哈希；运行不需要网络。静音同时停止音效、航空循环、语音并清理字幕。

批量数据工具：`tools/build_faction_catalog.py`、`tools/generate_faction_cards.py`、`tools/generate_unit_voices.py`、`tools/document_faction_catalog.py`。对应专项验收为 `faction_catalog_tests` / `airforce_tests` / `faction_visual_tests` / `faction_ui_audio_tests`，并纳入 `tools/test.sh`。

Godot 4.6.x，GDScript，Forward+ renderer。坐标用 Vector2(x,z)，世界高度由 MapData.height_at(map,pos) 返回。所有队列和游戏数值读取 data/rules.json。四类地图使用同一 Simulation。

## MapData (scripts/map_data.gd)
RefCounted。static generate(mode:String, seed:int)->Dictionary；static height_at(map,pos:Vector2)->float；static cell(map,pos:Vector2)->Vector2i；static terrain_at(map,pos:Vector2)->int；static validate(map)->Array[String]。
map: {mode, seed, size:int, heights:Array[Array[float]], terrain:Array[Array[int]], starts:[[x,z],[x,z]], mines:[{pos:[x,z],capacity}], bridges:[{id:int,bounds:[x,z,w,d],heads:[[x,z],[x,z]]}], decorations:[{pos:[x,z],kind:String}], valid:bool}。terrain 0=land,1=water,2=ramp,3=road,4=blocked decoration。bridge bounds 中水格由 Simulation 活桥覆盖。层高 0/2/4/6；坡道渐变。

## Rules (data/rules.json)
{version, economy:{initial_money,ore_capacity,ore_regen,harvester_capacity,harvest_rate,low_power_multiplier,construction_animation,sell_ratio,repair_rate,repair_cost,bridge_hp,bridge_cost,bridge_time,build_radius,fire_angle}, factions:{rivet:{name,mark},kestrel:{name,mark}}, units:{rivet_rifle:{name,faction,cost,hp,speed,build_time,radius,turn_speed,producer:"barracks",requires:[],weapon:"rivet_rifle",crush:false,crushable:true,art:"rifle"},...}, buildings:{rivet_hq:{name,faction,cost,hp,build_time,power:100,size:4,requires:[],role:"hq",expands:true,weapon:"",art:"hq"},...}, weapons:{id:{damage,interval,range,kind:"instant"|"shell",blast,speed}}}。阵营均为 rif​le/anti/tank/harvester/engineer；专属 rivet_assault / kestrel_demolition；建筑 hq/power/refinery/barracks/factory/tower/tech。

## Simulation (scripts/simulation.gd)
RefCounted，class_name WarSimulation。setup(rules:Dictionary,mode:String,seed:int,player_faction:String="rivet",ai_enabled:bool=true)。step(delta:float)。entities:Dictionary[int,Dictionary]。规则状态：map, rules, factions:Array[String]，money:Array[float]，time:float，result:String（""/"win"/"lose"/"draw"），projectiles:Array，mines:Array，bridges:Array，building_orders:Array（两个阵营各一个 Dictionary 或 {}），notices:Array[String]，events:Array[Dictionary]（消费者读取后 clear），ai_enabled。
实体 e：{id,kind:"unit"|"building",spec:String,team:int,pos:Vector2,hp:float,alpha:float,turret_alpha:float,turret_target:int,state:String,cooldown:float,commands:Array,queue:Array,construct_remaining:float,cargo:float,hit_flash:float}；building 有 rally:Vector2。alpha 单位度，0 朝 Vector2(1,0)，向 +z 增加。步兵镜像 abs(wrapf(alpha,-180,180)) >80。车辆 root.rotation.y=-deg(alpha)，turret.rotation.y=-deg(turret_alpha-alpha)；局部车头和炮管均 +x。
接口：build(team,spec,builder:int=-1)->String（空=成功）；place_building(team,pos)->String；cancel_build(team)->String；produce(building_id,spec)->String；cancel_production(building_id,index)->String；issue(ids:Array,kind:String,pos:Vector2,target:int=-1,append:bool=false)；capture_error(engineer_id,target_id)->String；sell(id:int,confirmed:bool=false)->String；toggle_repair(id:int)；power(team:int)->Vector2（x产能/y需求）；counts(team:int)->Vector2i（x单位/y建筑）；save_game(path:String)->String；load_game(path:String)->String；debug_spawn(team,spec,pos)->int（仅由显式开发模式调用）；set_rally(id,pos)；bridge_at(pos)->int（桥 id 或 -1）。路径 / 经济 / AI / 存档 / 队列均在 Simulation。
projectile: {pos:Vector2,start:Vector2,landing:Vector2,elapsed,duration,damage,blast,team,source,spec,heading,body_heading}。最后四项为可选视觉发射姿态，旧档缺失时保留原起点回退。bridge: {id,bounds,heads,hp,repair_progress,alive}。mine: {pos:Vector2,amount,capacity,...}，新矿柱无限且静态阻挡，按双方合计每根一车维护开采占用。events:{kind:"fire"|"impact"|"death"|"produce"|"delivery"|"build"|"select"|"command"|"sell"|"low_power"|"result",pos:Vector2,...}。

## PaperWorld (scripts/paper_world.gd)
Node3D class_name PaperWorld。setup(sim:WarSimulation,camera:Camera3D)；sync(delta,selection:Array,placement:Dictionary={})。组合 PaperLandscape、VolumeModels、步兵剪纸、地面选择圈、血条、真实炮口弹丸和效果。实体体积 mesh 使用开启阴影的 MultiMesh，步兵单独保留纸片状态。只读 Simulation，镜头旋转不改变 sim。placement={pos:Vector2,spec:String,valid:bool}。assets/cards/{faction}_{art}_{state}.svg 用于步兵动作与UI图标；车辆/建筑由VolumeModels几何绘制，不用原SVG作实体立面。步兵 state idle/move/attack/hit/death；实体车体/炮管动画与死亡残骸独立更新。MapData 高度用于接地。

## 主工程
scripts/main.gd 是 root：相机、HUD、小地图、输入与播放自制音效。Control 阻挡 UI 命令。模拟固定 physics tick 实时，不暂停下令。菜单：阵营、320×320 mountains 山地大图、160×160 handmade/random、48×48 dev、种子、新局/读档。地图选项使用稳定mode元数据，旧设置索引迁移至mode。测试通过同一 Simulation。

## VolumeModels / PaperLandscape

`VolumeModels.create_model(spec,kind,team)->Dictionary`：{root,body,turret,muzzle,meshes,dimensions:Vector3,height,footprint:Vector2,volumetric:true}，不支持的步兵返回{}。几何按阵营/art/队伍缓存，body和turret各一个单材质mesh；`update_model(model,e,delta)`仅做摆动、后坐等视觉反馈。`muzzle_offset(spec,kind,team,body_heading,turret_heading,visual_recoil=0)->Vector3`独立于实体存亡，用发射瞬间姿态恢复炮口至世界原点的偏移。

`PaperLandscape.build(sim)->PaperLandscape`返回完整地景node，`sync_resources(sim)`按矿石丰度与桥梁alive变化刷新。地表和坡道精确使用MapData.height_at；各体积景物用受光mesh与MultiMesh批处理。

车辆规则 flags `has_turret`、`fire_while_moving`、`turret_turn_speed`来自JSON。攻击移动持续走原合法路线，炮塔独立索敌；普通move不主动开火，步兵交战停下。老v1档缺炮塔字段时从alpha初始化，保留原经济/伤害快照；旧炮弹没有视觉发射姿态时仍按固定landing继续飞行。

建造/生产条目自身包含ProgressBar，`refresh_entry_progress`只更新进度与ready底色，避免每帧重建UI。ScrollContainer消费GUI滚轮，侧栏等面板禁止强制冒泡，main对UI区域进一步拦截遗留wheel事件，战场仍正常缩放。

## 2026-10-02 分基地施工与强制命令

分基地 `build(team,spec,builder)` 返回无需预付、立即 ready 的选址订单。放置后工兵执行 deploy_outpost，抵达时创建脚手架并转为 `resume_outpost`。未完工实体含 `construction={builder,progress,spent,initial_hp,repair_spent,work_state,pause_reason}`，`construct_remaining` 随进度减少。资金随进度支付，受损先付维修费、修满当前已建生命上限再施工；工兵死亡或离开暂停。完工移除 construction；`dismantle_outpost(id)` 拆除未完工实体，不退款。HUD 显示进度、暂停原因、工兵和已付施工/维修资金；右键脚手架接手，选中后拆除。

H/F 分别进入 force_attack/force_move 光标模式，左键携带 pick_entity 的目标 ID 或 -1 地面位置；Shift 追加。H 可对友方及共享 RUIN_TARGET_BASE 编码的树/中立房/石墙强制攻击；普通右键中立障碍转为移动，不派发攻击。F 指定步兵目标时为坦克提供直接碾压语义。空格仍定位镜头，WASD 保持物理布局的 InputMap 平移。
