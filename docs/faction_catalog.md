# Faction reference / 四阵营规则目录

Generated from [data/rules.json](../data/rules.json) and the English content catalog. Run `python3 tools/document_faction_catalog.py` after changing either. These are the rules for **new matches**; older saves retain their own snapshots.

本页直接读取当前规则和英文翻译目录生成。更改规则后运行上述命令更新；旧存档继续使用自己的规则快照。

Current catalog: **116 unit definitions, 60 building definitions, 106 weapon definitions**. Counts include specialized and compatibility definitions; they are not the number of cards available from one production building.

目录数量含专用及兼容定义，不等于单座生产建筑可购买的卡片数量。

## How to read the tables / 表格说明

- Unit cost and training time describe **one complete purchase**. For infantry squads, health, armor, movement speed and weapons describe each individual soldier.
- Squad members keep separate health, collisions, weapons, experience and transport seats. The order cost is per-person cost × squad size; time uses `squad_build_time` when present, otherwise per-person time × squad size.
- Building time is the rule processing/construction time; travel, doorway clearance and resource shortages can add delay. Power is signed generation/consumption; local base power is separate.
- Weapon targets describe what can be attacked, independently of the movement domain. Damage modifiers, splash, EMP and other special fields remain in the source JSON and in-game Wiki.

单位价格和时间是整次购买；小队生命、护甲、速度与武器是每名成员的数据。实际生产还受出入口、前置、供电和资金影响。伤害倍率、溅射与特殊效果请查看游戏图鉴及规则 JSON。

For mechanics, see [Game design](design.md). Background is in [the worldbuilding reference](派系设定/paper_front_world_setting_four_factions.md).

## Canon Legion / 正典军团

Stable ID: `kestrel`

Elite exoskeleton infantry advance alongside inexpensive armor. Basic infrastructure is cheap and quick to establish; advanced technology takes more time and money to unlock. / 精锐外骨骼步兵与廉价装甲混合推进；基础设施便宜快成型，高级科技解锁昂贵缓慢。

### Units / 单位

| Unit / 单位 | Members / 人数 | Order cost / 整队费用 | HP / 生命 | Armor / 护甲 | Speed / 速度 | Seconds / 秒 | Domain / 移动域 | Weapon / 武器 | Producer / 设施角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|---|---|
| Rifleman / 步枪兵<br>`kestrel_rifle` | 5 | 550 | 112 | 12 | 3.08 | 18 | Ground / 地 | `kestrel_rifle` | barracks | — |
| Armor-piercing Trooper / 穿甲兵<br>`kestrel_anti` | 4 | 712 | 112 | 12 | 2.86 | 22.4 | Ground / 地 | `kestrel_anti` | barracks | — |
| Answer Tank / 答案坦克<br>`kestrel_tank` | 1 | 780 | 480 | 60 | 3.85 | 12.8 | Ground / 地 | `kestrel_tank` | factory | — |
| Harvester / 矿车<br>`kestrel_harvester` | 1 | 510 | 420 | 25 | 3 | 10.4 | Ground / 地 | — | factory | — |
| Engineer / 工兵<br>`kestrel_engineer` | 1 | 136 | 65 | 12 | 2.97 | 4.8 | Ground / 地 | — | barracks | — |
| Demolition Trooper / 爆破兵<br>`kestrel_demolition` | 3 | 765 | 90 | 12 | 3.08 | 21.6 | Ground / 地 | `kestrel_demolition` | barracks | Open Calibration Institute / 开放校准所 |
| Patrol Car / 巡逻车<br>`kestrel_scout` | 1 | 255 | 180 | 25 | 6.16 | 7.2 | Ground / 地 | `kestrel_scout` | factory | — |
| Airguard Vehicle / 护空车<br>`kestrel_aa` | 1 | 510 | 320 | 25 | 3.96 | 12 | Ground / 地 | `kestrel_aa` | factory | — |
| Heading Fighter / 航向战机<br>`kestrel_fighter` | 1 | 808 | 300 | 25 | 10.45 | 17.6 | Air / 空 | `kestrel_fighter` | airfield | — |
| Ruling Railgun / 裁定电磁炮<br>`kestrel_advanced` | 1 | 2000 | 620 | 80 | 2.31 | 32.4 | Ground / 地 | `kestrel_advanced` | factory | Open Calibration Institute / 开放校准所 |
| Correction Cannon / 校正炮<br>`kestrel_artillery` | 1 | 892 | 360 | 25 | 2.86 | 17.6 | Ground / 地 | `kestrel_artillery` | factory | Open Calibration Institute / 开放校准所 |
| Approved Attack Aircraft / 批准攻击机<br>`kestrel_attacker` | 1 | 1062 | 340 | 25 | 8.25 | 20.8 | Air / 空 | `kestrel_attacker` | airfield | — |
| Formation Ferry / 编队渡船<br>`kestrel_ship_transport` | 1 | 663 | 610 | 45 | 4.18 | 19.2 | Naval / 海 | — | shipyard | — |
| Coordination Frigate / 协同护卫舰<br>`kestrel_ship_frigate` | 1 | 1266 | 980 | 70 | 3.85 | 27.2 | Naval / 海 | `kestrel_ship_frigate` | shipyard | — |
| Canon Command Ship / 正典指挥舰<br>`kestrel_ship_signature` | 1 | 2450 | 1470 | 100 | 3.41 | 44.1 | Naval / 海 | `kestrel_ship_signature` | shipyard | Open Calibration Institute / 开放校准所 |
| Conclusion Heavy Tank / 定论重坦<br>`kestrel_heavy_tank` | 1 | 1500 | 1000 | 90 | 2.6 | 28 | Ground / 地 | `kestrel_heavy_tank` | factory | Open Calibration Institute / 开放校准所 |
| Squad Machine Gunner / 班用机枪兵<br>`kestrel_gunner` | 5 | 850 | 112 | 12 | 2.65 | 30.5 | Ground / 地 | `kestrel_gunner` | barracks | — |
| Precision Marksman / 精确射手<br>`kestrel_marksman` | 2 | 480 | 85 | 12 | 2.8 | 17.2 | Ground / 地 | `kestrel_marksman` | barracks | — |
| AA Missile Trooper / 防空导弹兵<br>`kestrel_aa_infantry` | 2 | 450 | 100 | 12 | 2.75 | 16 | Ground / 地 | `kestrel_aa_infantry` | barracks | — |
| Accord Attack Helicopter / 协定武装直升机<br>`kestrel_helicopter` | 1 | 1150 | 420 | 25 | 5.6 | 24 | Air / 空 | `kestrel_helicopter` | airfield | — |
| Silent Submarine / 静默潜艇<br>`kestrel_submarine` | 1 | 1400 | 650 | 45 | 3.3 | 27.2 | Naval / 海 | `kestrel_submarine` | shipyard | — |
| Shorecross Armored Vehicle / 渡岸装甲车<br>`kestrel_amphibious` | 1 | 1000 | 720 | 60 | 3.8 | 27.2 | Naval / 海 | `kestrel_amphibious` | amphibious | — |
| Coordination Hovercraft / 协同气垫船<br>`kestrel_hovercraft` | 1 | 900 | 600 | 35 | 5 | 27.2 | Naval / 海 | — | amphibious | — |
| Expedition Support Ship / 远征支援舰<br>`kestrel_support_ship` | 1 | 2100 | 1100 | 75 | 2.8 | 27.2 | Naval / 海 | `kestrel_support_ship` | shipyard | Open Calibration Institute / 开放校准所 |
| Joint Light Carrier / 联合轻型航母<br>`kestrel_carrier` | 1 | 2800 | 1600 | 85 | 2.6 | 27.2 | Naval / 海 | `kestrel_carrier` | shipyard | Open Calibration Institute / 开放校准所 |
| Carrier Attack Aircraft / 舰载攻击机<br>`kestrel_carrier_plane` | 1 | 180 | 180 | 25 | 9 | 20 | Air / 空 | `kestrel_carrier_plane` | carrier | — |
| Lookout Reconnaissance Aircraft / 瞭望侦察机<br>`kestrel_recon` | 1 | 650 | 230 | 25 | 12 | 17.6 | Air / 空 | — | airfield | — |
| Accord AA Ship / 协定防空舰<br>`kestrel_ship_aa` | 1 | 1200 | 850 | 70 | 3.9 | 28 | Naval / 海 | `kestrel_ship_aa` | shipyard | — |

### Buildings / 建筑

| Building / 建筑 | Cost / 费用 | HP / 生命 | Armor / 护甲 | Seconds / 秒 | Power / 电力 | Footprint / 占地 | Role / 角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|
| Original Plan Headquarters / 原图总部<br>`kestrel_hq` | 2400 | 2800 | 40 | 60 | 0 | 8 × 8 | hq | — |
| Standard Power Plant / 标准发电站<br>`kestrel_power` | 360 | 750 | 40 | 11.25 | 220 | 3 × 3 | power | — |
| Crystal Refinery / 辉晶精炼厂<br>`kestrel_refinery` | 1160 | 1600 | 40 | 18.75 | -60 | 5 × 5 | refinery | — |
| Canon Barracks / 正典兵营<br>`kestrel_barracks` | 360 | 1100 | 40 | 11.25 | -20 | 3 × 3 | barracks | — |
| Arch-frame Assembly Works / 拱架装配厂<br>`kestrel_factory` | 1000 | 2000 | 40 | 22.5 | -100 | 6 × 6 | factory | — |
| Repeating-fire Guard Tower / 连射守备塔<br>`kestrel_tower` | 550 | 750 | 80 | 12 | -35 | 2 × 2 | tower | — |
| Open Calibration Institute / 开放校准所<br>`kestrel_tech` | 1800 | 1000 | 40 | 65 | -40 | 3 × 3 | tech | — |
| Defensive Wall / 防御围墙<br>`kestrel_wall` | 60 | 700 | 80 | 3 | 0 | 1 × 1 | wall | — |
| Anti-tank Obstacle / 反坦克拒马<br>`kestrel_barricade` | 40 | 400 | 80 | 3 | 0 | 1 × 1 | barricade | — |
| Frontline Planning Table / 前线图台<br>`kestrel_outpost` | 720 | 1350 | 40 | 45 | -20 | 3 × 3 | outpost | — |
| Heading Air Station / 航向航空站<br>`kestrel_airfield` | 1040 | 1650 | 40 | 22.5 | -90 | 7 × 7 | airfield | — |
| Standard Shipyard / 标准船坞<br>`kestrel_shipyard` | 1450 | 2150 | 40 | 34 | -95 | 4 × 4 | shipyard | — |
| Standard Refit Repair Depot / 标准整备修理厂<br>`kestrel_repair` | 700 | 1100 | 40 | 18 | -40 | 4 × 4 | repair | — |
| Long-range Precision Turret / 远程精确炮塔<br>`kestrel_advanced_tower` | 1250 | 1050 | 100 | 33 | -65 | 3 × 3 | tower | — |
| Twin AA Turret / 双联防空炮塔<br>`kestrel_aa_tower` | 750 | 900 | 80 | 16 | -45 | 3 × 3 | tower | — |

## Heavy Hammer Legion / 重锤军团

Stable ID: `rivet`

Armed engineers build scaffolds on ore veins to establish a dispersed drilling economy, while heavy tanks and heavy bomber airships protect expansion. / 武装工兵用脚手架在矿脉建立分散钻机经济，重装坦克和重型轰炸飞艇保护扩张。

### Units / 单位

| Unit / 单位 | Members / 人数 | Order cost / 整队费用 | HP / 生命 | Armor / 护甲 | Speed / 速度 | Seconds / 秒 | Domain / 移动域 | Weapon / 武器 | Producer / 设施角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|---|---|
| Assault Trooper / 突击兵<br>`rivet_rifle` | 6 | 720 | 100 | 16 | 2.4 | 30 | Ground / 地 | `rivet_rifle` | barracks | — |
| Armor Breaker / 破甲兵<br>`rivet_anti` | 4 | 880 | 95 | 16 | 2.2 | 32 | Ground / 地 | `rivet_anti` | barracks | — |
| Hammerhead Tank / 锤头坦克<br>`rivet_tank` | 1 | 1100 | 650 | 70 | 2.8 | 18 | Ground / 地 | `rivet_tank` | factory | — |
| Armed Engineer / 武装工兵<br>`rivet_engineer` | 1 | 180 | 150 | 16 | 2.3 | 7 | Ground / 地 | `rivet_engineer` | barracks | — |
| Reason Cannon / 理由炮<br>`rivet_assault` | 1 | 1500 | 1200 | 100 | 1.8 | 28 | Ground / 地 | `rivet_assault` | factory | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Scout Car / 侦察车<br>`rivet_scout` | 1 | 360 | 240 | 35 | 4.6 | 9 | Ground / 地 | `rivet_scout` | factory | — |
| No-fly Vehicle / 拒飞车<br>`rivet_aa` | 1 | 720 | 420 | 35 | 2.8 | 15 | Ground / 地 | `rivet_aa` | factory | — |
| Interceptor / 拦截战机<br>`rivet_fighter` | 1 | 1100 | 400 | 35 | 8 | 22 | Air / 空 | `rivet_fighter` | airfield | — |
| Final Appeal Cannon / 终审炮<br>`rivet_advanced` | 1 | 2300 | 950 | 95 | 1.6 | 36 | Ground / 地 | `rivet_advanced` | factory | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Reiteration Bomber / 重申轰炸机<br>`rivet_bomber` | 1 | 1700 | 560 | 50 | 5.8 | 32 | Air / 空 | `rivet_bomber` | airfield | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Ironclad Ferry / 铁甲渡船<br>`rivet_ship_transport` | 1 | 850 | 690 | 55 | 3.4 | 24 | Naval / 海 | — | shipyard | — |
| Wavebreaker Gunboat / 破浪炮舰<br>`rivet_ship_frigate` | 1 | 1550 | 1150 | 85 | 3 | 34 | Naval / 海 | `rivet_ship_frigate` | shipyard | — |
| Heavy Hammer Siege Ship / 重锤攻城舰<br>`rivet_ship_signature` | 1 | 2700 | 1800 | 115 | 2.5 | 49 | Naval / 海 | `rivet_ship_signature` | shipyard | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Dusk Bell Heavy Bomber Airship / 暮钟重型轰炸飞艇<br>`rivet_zeppelin` | 1 | 2400 | 2200 | 50 | 3.4 | 42 | Air / 空 | `rivet_zeppelin` | airfield | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Encroachment Heavy Tank / 压境重坦<br>`rivet_heavy_tank` | 1 | 1900 | 1400 | 105 | 2.1 | 32 | Ground / 地 | `rivet_heavy_tank` | factory | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Heavy Machine Gunner / 重装机枪兵<br>`rivet_gunner` | 4 | 960 | 165 | 16 | 1.85 | 34.4 | Ground / 地 | `rivet_gunner` | barracks | — |
| Concussion Grenadier / 震荡榴弹兵<br>`rivet_grenadier` | 4 | 840 | 120 | 16 | 2.1 | 30 | Ground / 地 | `rivet_grenadier` | barracks | — |
| Iron Hammer Attack Helicopter / 铁锤武装直升机<br>`rivet_helicopter` | 1 | 1150 | 420 | 35 | 5.6 | 24 | Air / 空 | `rivet_helicopter` | airfield | — |
| Dark Hammer Submarine / 暗锤潜艇<br>`rivet_submarine` | 1 | 1400 | 650 | 45 | 3.3 | 34 | Naval / 海 | `rivet_submarine` | shipyard | — |
| Wavebreaker Armored Vehicle / 破浪装甲车<br>`rivet_amphibious` | 1 | 1000 | 720 | 60 | 3.8 | 34 | Naval / 海 | `rivet_amphibious` | amphibious | — |
| Heavy-lift Hovercraft / 重载气垫船<br>`rivet_hovercraft` | 1 | 900 | 600 | 35 | 5 | 34 | Naval / 海 | — | amphibious | — |
| Great Hammer Support Ship / 巨锤支援舰<br>`rivet_support_ship` | 1 | 2100 | 1100 | 75 | 2.8 | 34 | Naval / 海 | `rivet_support_ship` | shipyard | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Anvil Light Carrier / 铁砧轻型航母<br>`rivet_carrier` | 1 | 2800 | 1600 | 85 | 2.6 | 34 | Naval / 海 | `rivet_carrier` | shipyard | Korchin Pressure Research Institute / 科尔钦压力研究院 |
| Carrier Attack Aircraft / 舰载攻击机<br>`rivet_carrier_plane` | 1 | 180 | 180 | 35 | 9 | 20 | Air / 空 | `rivet_carrier_plane` | carrier | — |
| Iron Curtain AA Ship / 铁幕防空舰<br>`rivet_ship_aa` | 1 | 1450 | 1300 | 85 | 2.8 | 28 | Naval / 海 | `rivet_ship_aa` | shipyard | — |

### Buildings / 建筑

| Building / 建筑 | Cost / 费用 | HP / 生命 | Armor / 护甲 | Seconds / 秒 | Power / 电力 | Footprint / 占地 | Role / 角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|
| Base Barracks / 基地兵营<br>`rivet_hq` | 1000 | 3500 | 40 | 15 | 0 | 8 × 8 | hq | — |
| Heavy Power Plant / 重型发电站<br>`rivet_power` | 600 | 1100 | 40 | 15 | 300 | 3 × 3 | power | — |
| Transverse Stamping Works / 横向冲压厂<br>`rivet_factory` | 1400 | 2500 | 40 | 30 | -100 | 6 × 6 | factory | — |
| Artillery Guard Tower / 炮击守备塔<br>`rivet_tower` | 700 | 1000 | 80 | 15 | -50 | 2 × 2 | tower | — |
| Korchin Pressure Research Institute / 科尔钦压力研究院<br>`rivet_tech` | 1000 | 1800 | 40 | 25 | -60 | 3 × 3 | tech | — |
| Defensive Wall / 防御围墙<br>`rivet_wall` | 60 | 700 | 80 | 3 | 0 | 1 × 1 | wall | — |
| Anti-tank Obstacle / 反坦克拒马<br>`rivet_barricade` | 40 | 400 | 80 | 3 | 0 | 1 × 1 | barricade | — |
| Heavy-load Air Station / 重载航空站<br>`rivet_airfield` | 1500 | 2000 | 40 | 30 | -90 | 7 × 7 | airfield | — |
| Steel Rivet Shipyard / 钢铆船坞<br>`rivet_shipyard` | 1450 | 2150 | 40 | 34 | -95 | 4 × 4 | shipyard | — |
| Ore-vein Mining Drill / 矿脉采掘钻机<br>`rivet_drill` | 700 | 800 | 40 | 12 | -20 | 2 × 2 | drill | — |
| Heavy Hammer Armored Repair Depot / 重锤装甲修理厂<br>`rivet_repair` | 850 | 1450 | 40 | 22 | -40 | 4 × 4 | repair | — |
| Heavy Bombardment Fortress Turret / 重轰堡垒炮塔<br>`rivet_advanced_tower` | 1500 | 1500 | 100 | 33 | -65 | 3 × 3 | tower | — |

## Long Nail Legion / 长钉军团

Stable ID: `iron`

Rail mobility, durable armor, and out-of-combat self-repair. Harvesters and armored trains run only on friendly tracks; infantry and buildings do not self-repair. / 铁路机动、耐用装甲与脱战自修复；矿车和装甲列车仅沿己方铁路运行，自愈不适用于步兵和建筑。

### Units / 单位

| Unit / 单位 | Members / 人数 | Order cost / 整队费用 | HP / 生命 | Armor / 护甲 | Speed / 速度 | Seconds / 秒 | Domain / 移动域 | Weapon / 武器 | Producer / 设施角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|---|---|
| Railway Engineer / 铁道工程兵<br>`iron_engineer` | 1 | 165 | 65 | 10 | 2.3 | 7 | Ground / 地 | — | barracks | — |
| Nailgun Trooper / 钉枪兵<br>`iron_rifle` | 5 | 525 | 85 | 10 | 2.4 | 25 | Ground / 地 | `iron_rifle` | barracks | — |
| Anti-armor Trooper / 反甲兵<br>`iron_anti` | 4 | 860 | 82 | 10 | 2.15 | 32 | Ground / 地 | `iron_anti` | barracks | — |
| Harvester / 矿车<br>`iron_harvester` | 1 | 625 | 480 | 35 | 3 | 15 | Ground / 地 | — | factory | — |
| Inspection Car / 巡检车<br>`iron_scout` | 1 | 330 | 210 | 35 | 4.8 | 9 | Ground / 地 | `iron_scout` | factory | — |
| Bedrock Tank / 磐石坦克<br>`iron_tank` | 1 | 850 | 720 | 75 | 2.75 | 18 | Ground / 地 | `iron_tank` | factory | — |
| Roadguard Support Vehicle / 护路支援车<br>`iron_assault` | 1 | 1150 | 850 | 85 | 2.1 | 25 | Ground / 地 | `iron_assault` | factory | Durable Mechanics Research Institute / 耐久机工研究院 |
| Convoy AA Vehicle / 护队防空车<br>`iron_aa` | 1 | 660 | 360 | 35 | 3.15 | 16 | Ground / 地 | `iron_aa` | factory | — |
| Crane Engineering Vehicle / 吊装工程车<br>`iron_rig` | 1 | 575 | 400 | 35 | 2.4 | 14 | Ground / 地 | — | factory | — |
| Stable-mount Howitzer / 稳座榴弹炮<br>`iron_artillery` | 1 | 925 | 400 | 35 | 2.25 | 23 | Ground / 地 | `iron_artillery` | factory | Durable Mechanics Research Institute / 耐久机工研究院 |
| Wrench Repair Vehicle / 扳手维修车<br>`iron_repair_vehicle` | 1 | 550 | 330 | 35 | 3 | 14 | Ground / 地 | — | factory | — |
| Recovery Vehicle / 拖救车<br>`iron_recycler` | 1 | 625 | 450 | 35 | 2.5 | 17 | Ground / 地 | — | factory | Durable Mechanics Research Institute / 耐久机工研究院 |
| Watchguard Fighter / 守望战机<br>`iron_fighter` | 1 | 1025 | 340 | 35 | 8.5 | 23 | Air / 空 | `iron_fighter` | airfield | — |
| Stone Falcon Attack Aircraft / 石隼攻击机<br>`iron_attacker` | 1 | 1100 | 390 | 35 | 6.8 | 28 | Air / 空 | `iron_attacker` | airfield | — |
| Steadywing Transport Aircraft / 稳翼运输机<br>`iron_air_transport` | 1 | 1150 | 500 | 45 | 6.5 | 30 | Air / 空 | — | airfield | — |
| Assurance Cannon / 定心炮<br>`iron_advanced` | 1 | 2150 | 760 | 90 | 1.9 | 38 | Ground / 地 | `iron_advanced` | factory | Durable Mechanics Research Institute / 耐久机工研究院 |
| Escort APC / 护送装甲车<br>`iron_transport` | 1 | 475 | 440 | 35 | 3.45 | 13 | Ground / 地 | — | factory | — |
| Supply Ferry / 补给渡船<br>`iron_ship_transport` | 1 | 800 | 760 | 55 | 3.2 | 24 | Naval / 海 | — | shipyard | — |
| Rivet Frigate / 铆钉护卫舰<br>`iron_ship_frigate` | 1 | 1510 | 1200 | 85 | 3 | 34 | Naval / 海 | `iron_ship_frigate` | shipyard | — |
| Long Nail Workshop Ship / 长钉工坊舰<br>`iron_ship_signature` | 1 | 2550 | 1700 | 110 | 2.7 | 49 | Naval / 海 | `iron_ship_signature` | shipyard | Durable Mechanics Research Institute / 耐久机工研究院 |
| Iron Oath Armored Train / 铁誓装甲列车<br>`iron_train` | 1 | 2400 | 1800 | 90 | 2.6 | 38 | Ground / 地 | `iron_train` | factory | Durable Mechanics Research Institute / 耐久机工研究院 |
| Mountain Anchor Heavy Tank / 镇岳重坦<br>`iron_heavy_tank` | 1 | 1750 | 1350 | 100 | 2.05 | 32 | Ground / 地 | `iron_heavy_tank` | factory | Durable Mechanics Research Institute / 耐久机工研究院 |
| Long Nail Sniper / 长钉狙击兵<br>`iron_marksman` | 2 | 510 | 90 | 10 | 2.2 | 18.2 | Ground / 地 | `iron_marksman` | barracks | — |
| Rail Mortar Trooper / 轨道迫击炮兵<br>`iron_mortar` | 3 | 900 | 100 | 10 | 1.9 | 32.1 | Ground / 地 | `iron_mortar` | barracks | — |
| Rivetwing Attack Helicopter / 铆翼武装直升机<br>`iron_helicopter` | 1 | 1150 | 420 | 35 | 5.6 | 24 | Air / 空 | `iron_helicopter` | airfield | — |
| Long Needle Submarine / 长针潜艇<br>`iron_submarine` | 1 | 1400 | 650 | 45 | 3.3 | 34 | Naval / 海 | `iron_submarine` | shipyard | — |
| Amphibious Nail-armored Vehicle / 两栖钉甲车<br>`iron_amphibious` | 1 | 1000 | 720 | 60 | 3.8 | 34 | Naval / 海 | `iron_amphibious` | amphibious | — |
| Railboat Hovercraft / 轨舟气垫船<br>`iron_hovercraft` | 1 | 900 | 600 | 35 | 5 | 34 | Naval / 海 | — | amphibious | — |
| Far Nail Support Ship / 远钉支援舰<br>`iron_support_ship` | 1 | 2100 | 1100 | 75 | 2.8 | 34 | Naval / 海 | `iron_support_ship` | shipyard | Durable Mechanics Research Institute / 耐久机工研究院 |
| Workshop Light Carrier / 工坊轻型航母<br>`iron_carrier` | 1 | 2800 | 1600 | 85 | 2.6 | 34 | Naval / 海 | `iron_carrier` | shipyard | Durable Mechanics Research Institute / 耐久机工研究院 |
| Carrier Attack Aircraft / 舰载攻击机<br>`iron_carrier_plane` | 1 | 180 | 180 | 35 | 9 | 20 | Air / 空 | `iron_carrier_plane` | carrier | — |
| Rivetwing AA Ship / 铆翼防空舰<br>`iron_ship_aa` | 1 | 1360 | 1150 | 85 | 3.1 | 28 | Naval / 海 | `iron_ship_aa` | shipyard | — |

### Buildings / 建筑

| Building / 建筑 | Cost / 费用 | HP / 生命 | Armor / 护甲 | Seconds / 秒 | Power / 电力 | Footprint / 占地 | Role / 角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|
| Central Workshop / 总工坊<br>`iron_hq` | 2400 | 3200 | 40 | 60 | 0 | 8 × 8 | hq | — |
| Boiler Power Plant / 锅炉发电站<br>`iron_power` | 475 | 1000 | 40 | 16 | 250 | 5 × 5 | power | — |
| Screening Refinery / 筛选精炼厂<br>`iron_refinery` | 1350 | 1600 | 40 | 26 | -55 | 5 × 5 | refinery | — |
| Garrison Barracks / 守备兵营<br>`iron_barracks` | 425 | 1400 | 40 | 16 | -20 | 5 × 5 | barracks | — |
| Assembly Factory / 装配工厂<br>`iron_factory` | 1200 | 2300 | 40 | 30 | -90 | 6 × 6 | factory | — |
| Durable Mechanics Research Institute / 耐久机工研究院<br>`iron_tech` | 850 | 1400 | 40 | 26 | -55 | 5 × 5 | tech | — |
| Field Airfield / 野战机场<br>`iron_airfield` | 1200 | 1850 | 40 | 32 | -85 | 7 × 7 | airfield | — |
| Frontline Workshop / 前线工坊<br>`iron_outpost` | 850 | 1450 | 40 | 28 | -20 | 4 × 4 | outpost | — |
| Machine-gun Bunker / 机枪堡<br>`iron_tower` | 500 | 850 | 80 | 12 | -30 | 3 × 3 | tower | — |
| Airguard Platform / 护场防空台<br>`iron_aa_tower` | 650 | 950 | 80 | 16 | -45 | 3 × 3 | tower | — |
| Gatekeeper Gun Mount / 守门炮座<br>`iron_anti_tower` | 950 | 1100 | 100 | 27 | -55 | 3 × 3 | tower | — |
| Riveted Wall / 铆接围墙<br>`iron_wall` | 60 | 800 | 80 | 3 | 0 | 1 × 1 | wall | — |
| Artisan Shipyard / 工匠船坞<br>`iron_shipyard` | 1450 | 2400 | 40 | 34 | -95 | 4 × 4 | shipyard | — |
| Railway / 铁路<br>`iron_rail` | 25 | 180 | 0 | 0.2 | 0 | 1 × 1 | rail | — |
| Three-way Rail Junction / 三向铁路岔道<br>`iron_rail_junction` | 45 | 180 | 0 | 0.2 | 0 | 1 × 1 | rail_junction | — |
| Rail Maintenance Repair Depot / 轨道机务修理厂<br>`iron_repair` | 750 | 1300 | 40 | 20 | -40 | 4 × 4 | repair | — |
| Steam Heavy Turret / 蒸汽重炮塔<br>`iron_advanced_tower` | 1375 | 1400 | 100 | 33 | -65 | 3 × 3 | tower | — |

## Skywing Order / 天翼教团

Stable ID: `sky`

Expensive, complex technology combines fragile equipment with powerful aircraft, EMP control, precision lasers, and sustained beams. / 复杂昂贵的高科技，脆弱设备与强力航空，EMP控制、定点激光与持续束流。

### Units / 单位

| Unit / 单位 | Members / 人数 | Order cost / 整队费用 | HP / 生命 | Armor / 护甲 | Speed / 速度 | Seconds / 秒 | Domain / 移动域 | Weapon / 武器 | Producer / 设施角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|---|---|
| Engineer / 工兵<br>`sky_engineer` | 1 | 215 | 50 | 8 | 3 | 6 | Ground / 地 | — | barracks | — |
| Service Trooper / 勤务兵<br>`sky_rifle` | 4 | 440 | 80 | 8 | 3 | 20 | Ground / 地 | `sky_rifle` | barracks | — |
| Guided-missile Trooper / 导引兵<br>`sky_anti` | 4 | 1032 | 68 | 8 | 2.75 | 32 | Ground / 地 | `sky_anti` | barracks | — |
| Harvester / 矿车<br>`sky_harvester` | 1 | 600 | 351 | 20 | 3 | 14 | Ground / 地 | — | factory | — |
| Survey Vehicle / 测绘车<br>`sky_scout` | 1 | 429 | 153 | 20 | 6.1 | 9 | Ground / 地 | `sky_scout` | factory | — |
| Experimental Tank / 试验坦克<br>`sky_tank` | 1 | 900 | 480 | 50 | 3.9 | 20 | Ground / 地 | `sky_tank` | factory | — |
| Revision Cannon / 修订炮<br>`sky_artillery` | 1 | 1320 | 284 | 20 | 2.8 | 25 | Ground / 地 | `sky_artillery` | factory | Next Draft Technology Institute / 续稿科技研究所 |
| Airblock Vehicle / 拦空车<br>`sky_aa` | 1 | 858 | 261 | 20 | 4 | 17 | Ground / 地 | `sky_aa` | factory | — |
| Test Vehicle / 检验车<br>`sky_inspection` | 1 | 605 | 225 | 20 | 4.4 | 13 | Ground / 地 | — | factory | — |
| Designation Vehicle / 标定车<br>`sky_designation` | 1 | 688 | 198 | 20 | 4.8 | 15 | Ground / 地 | — | factory | — |
| Disruptor Vehicle / 断流车<br>`sky_disruptor` | 1 | 1072 | 256 | 20 | 3.7 | 23 | Ground / 地 | `sky_disruptor` | factory | Next Draft Technology Institute / 续稿科技研究所 |
| Pulse Array Vehicle / 脉冲阵列车<br>`sky_pulse` | 1 | 2310 | 472 | 65 | 2.3 | 38 | Ground / 地 | `sky_pulse` | factory | Next Draft Technology Institute / 续稿科技研究所 |
| Overreach Fighter / 越界战机<br>`sky_fighter` | 1 | 1490 | 248 | 20 | 10.7 | 27 | Air / 空 | `sky_fighter` | airfield | — |
| Final-version Attack Aircraft / 终版攻击机<br>`sky_attacker` | 1 | 1595 | 288 | 20 | 8.4 | 27 | Air / 空 | `sky_attacker` | airfield | Next Draft Technology Institute / 续稿科技研究所 |
| Wingbridge Transport Aircraft / 翼桥运输机<br>`sky_air_transport` | 1 | 1430 | 351 | 35 | 8 | 29 | Air / 空 | — | airfield | — |
| Survey Aircraft / 巡测机<br>`sky_recon` | 1 | 853 | 184 | 20 | 11.3 | 18 | Air / 空 | — | airfield | — |
| Foldwing Ferry / 折翼渡船<br>`sky_ship_transport` | 1 | 990 | 522 | 40 | 4.1 | 24 | Naval / 海 | — | shipyard | — |
| Skywing Frigate / 天翼护卫舰<br>`sky_ship_frigate` | 1 | 1782 | 810 | 65 | 3.8 | 34 | Naval / 海 | `sky_ship_frigate` | shipyard | — |
| Pulse Cruiser / 脉冲巡洋舰<br>`sky_ship_signature` | 1 | 3025 | 1242 | 95 | 3.5 | 49 | Naval / 海 | `sky_ship_signature` | shipyard | Next Draft Technology Institute / 续稿科技研究所 |
| Hand of Creation / 创世之手<br>`sky_creator_hand` | 1 | 5000 | 6667 | 65 | 2.2 | 110 | Ground / 地 | `sky_creator_hand` | factory | Next Draft Technology Institute / 续稿科技研究所 |
| Judgment Heavy Tank / 裁决重坦<br>`sky_heavy_tank` | 1 | 2200 | 1000 | 80 | 2.5 | 34 | Ground / 地 | `sky_heavy_tank` | factory | Next Draft Technology Institute / 续稿科技研究所 |
| Pulse Trooper / 脉冲步兵<br>`sky_storm` | 2 | 580 | 78 | 8 | 3 | 20.8 | Ground / 地 | `sky_storm` | barracks | — |
| Foldwing Guided-missile Trooper / 折翼导引兵<br>`sky_aa_infantry` | 2 | 550 | 72 | 8 | 3 | 19.6 | Ground / 地 | `sky_aa_infantry` | barracks | — |
| Skyspin Attack Helicopter / 天旋武装直升机<br>`sky_helicopter` | 1 | 1150 | 420 | 20 | 5.6 | 24 | Air / 空 | `sky_helicopter` | airfield | — |
| Hiddenwing Submarine / 隐翼潜艇<br>`sky_submarine` | 1 | 1400 | 650 | 45 | 3.3 | 34 | Naval / 海 | `sky_submarine` | shipyard | — |
| Foldwing Amphibious Vehicle / 折翼两栖车<br>`sky_amphibious` | 1 | 1000 | 720 | 60 | 3.8 | 34 | Naval / 海 | `sky_amphibious` | amphibious | — |
| Cloudcross Hovercraft / 云渡气垫船<br>`sky_hovercraft` | 1 | 900 | 600 | 35 | 5 | 34 | Naval / 海 | — | amphibious | — |
| Skyveil Support Ship / 天幕支援舰<br>`sky_support_ship` | 1 | 2100 | 1100 | 75 | 2.8 | 34 | Naval / 海 | `sky_support_ship` | shipyard | Next Draft Technology Institute / 续稿科技研究所 |
| Floatwing Light Carrier / 浮翼轻型航母<br>`sky_carrier` | 1 | 2800 | 1600 | 85 | 2.6 | 34 | Naval / 海 | `sky_carrier` | shipyard | Next Draft Technology Institute / 续稿科技研究所 |
| Carrier Attack Aircraft / 舰载攻击机<br>`sky_carrier_plane` | 1 | 180 | 180 | 20 | 9 | 20 | Air / 空 | `sky_carrier_plane` | carrier | — |
| Firmament AA Ship / 天穹防空舰<br>`sky_ship_aa` | 1 | 1500 | 760 | 65 | 4.2 | 28 | Naval / 海 | `sky_ship_aa` | shipyard | — |

### Buildings / 建筑

| Building / 建筑 | Cost / 费用 | HP / 生命 | Armor / 护甲 | Seconds / 秒 | Power / 电力 | Footprint / 占地 | Role / 角色 | Requires / 前置 |
|---|---|---|---|---|---|---|---|---|
| Spreadwing Headquarters / 展翼总部<br>`sky_hq` | 2550 | 2500 | 40 | 60 | 0 | 8 × 8 | hq | — |
| Excitation Power Plant / 励磁发电站<br>`sky_power` | 575 | 722 | 40 | 17 | 300 | 4 × 4 | power | — |
| Crystal Separation Station / 辉晶分离站<br>`sky_refinery` | 1350 | 1360 | 40 | 24 | -65 | 5 × 5 | refinery | — |
| Service Barracks / 勤务兵营<br>`sky_barracks` | 475 | 850 | 40 | 14 | -20 | 4 × 4 | barracks | — |
| Prototype Factory / 试制工厂<br>`sky_factory` | 1200 | 1572 | 40 | 27 | -105 | 6 × 6 | factory | — |
| Next Draft Technology Institute / 续稿科技研究所<br>`sky_tech` | 1300 | 935 | 40 | 30 | -75 | 3 × 3 | tech | — |
| Spreadwing Airfield / 展翼机场<br>`sky_airfield` | 1450 | 1275 | 40 | 28 | -110 | 7 × 7 | airfield | — |
| Frontline Wing Station / 前线翼站<br>`sky_outpost` | 950 | 978 | 40 | 23 | -25 | 4 × 4 | outpost | — |
| Sentry Gun Mount / 哨戒枪座<br>`sky_tower` | 575 | 552 | 80 | 11 | -40 | 3 × 3 | tower | — |
| Air-intercept Battery / 截空炮台<br>`sky_aa_tower` | 750 | 638 | 80 | 15 | -65 | 3 × 3 | tower | — |
| Focus Gun Mount / 聚焦炮座<br>`sky_anti_tower` | 1125 | 680 | 100 | 27 | -80 | 3 × 3 | tower | — |
| Folded-panel Wall / 折板围墙<br>`sky_wall` | 65 | 650 | 80 | 3 | 0 | 1 × 1 | wall | — |
| Observation Shipyard / 观测船坞<br>`sky_shipyard` | 1600 | 1828 | 40 | 34 | -95 | 4 × 4 | shipyard | — |
| Nano Calibration Repair Depot / 纳米校准修理厂<br>`sky_repair` | 950 | 950 | 40 | 20 | -55 | 4 × 4 | repair | — |
| Prism Beam Turret / 棱镜束流炮塔<br>`sky_advanced_tower` | 1700 | 850 | 100 | 33 | -65 | 3 × 3 | tower | — |
| Fusion Crystal Power Plant / 聚变辉晶发电站<br>`sky_advanced_power` | 1500 | 1650 | 40 | 32 | 950 | 5 × 5 | power | — |

## Weapons / 武器

Base values before target multipliers, veterancy and splash falloff. / 以下为基础数值，尚未计算目标倍率、老兵或溅射衰减。

| ID | Damage / 伤害 | Penetration / 穿深 | Interval / 间隔秒 | Range / 射程 | Targets / 攻击域 | Blast / 溅射 |
|---|---|---|---|---|---|---|
| `rivet_rifle` | 12 | 18 | 0.8 | 5 | Ground / 地 | 0 |
| `kestrel_rifle` | 11.25 | 18 | 0.65 | 5.5 | Ground / 地 | 0 |
| `rivet_anti` | 100 | 120 | 3 | 8 | Ground / 地, Naval / 海 | 0.35 |
| `kestrel_anti` | 112.5 | 120 | 2.8 | 8.5 | Ground / 地, Naval / 海 | 0.35 |
| `rivet_tank` | 90 | 85 | 2 | 9 | Ground / 地, Naval / 海 | 1.2 |
| `kestrel_tank` | 70 | 85 | 2 | 9.5 | Ground / 地, Naval / 海 | 1 |
| `rivet_assault` | 150 | 100 | 3.8 | 10 | Ground / 地 | 2 |
| `kestrel_demolition` | 80 | 100 | 2.8 | 7 | Ground / 地 | 1.8 |
| `rivet_tower` | 75 | 22 | 2 | 12 | Ground / 地 | 1.2 |
| `kestrel_tower` | 18 | 22 | 0.5 | 12 | Ground / 地 | 0 |
| `kestrel_scout` | 12 | 18 | 0.55 | 7 | Ground / 地 | 0 |
| `kestrel_aa` | 58 | 65 | 1.2 | 13 | Air / 空 | 0 |
| `kestrel_fighter` | 75 | 65 | 0.8 | 10 | Air / 空 | 0 |
| `kestrel_advanced` | 180 | 140 | 4.2 | 16 | Ground / 地, Naval / 海 | 0.4 |
| `rivet_scout` | 15 | 18 | 0.55 | 7 | Ground / 地 | 0 |
| `rivet_aa` | 72 | 65 | 1.5 | 13 | Air / 空 | 0 |
| `rivet_fighter` | 85 | 65 | 0.9 | 10 | Air / 空 | 0 |
| `rivet_advanced` | 210 | 140 | 4.8 | 18 | Ground / 地, Naval / 海 | 1.5 |
| `kestrel_artillery` | 95 | 110 | 3.4 | 15 | Ground / 地, Naval / 海 | 1.7 |
| `kestrel_attacker` | 110 | 120 | 1.8 | 8 | Ground / 地 | 0.6 |
| `rivet_bomber` | 160 | 120 | 3 | 7 | Ground / 地 | 2.2 |
| `iron_rifle` | 10 | 18 | 0.8 | 5.2 | Ground / 地 | 0 |
| `iron_anti` | 90 | 120 | 3.1 | 8 | Ground / 地, Naval / 海 | 0.3 |
| `iron_scout` | 13 | 18 | 0.65 | 6.8 | Ground / 地 | 0 |
| `iron_tank` | 78 | 85 | 2.1 | 9 | Ground / 地, Naval / 海 | 0.8 |
| `iron_assault` | 78 | 100 | 1.7 | 6.5 | Ground / 地 | 2.1 |
| `iron_aa` | 65 | 65 | 1.45 | 12.5 | Air / 空 | 0 |
| `iron_artillery` | 100 | 110 | 3.8 | 15 | Ground / 地, Naval / 海 | 1.8 |
| `iron_fighter` | 75 | 65 | 0.95 | 10 | Air / 空 | 0 |
| `iron_attacker` | 100 | 120 | 2 | 8 | Ground / 地 | 1.1 |
| `iron_advanced` | 175 | 140 | 4.6 | 17 | Ground / 地, Naval / 海 | 1.4 |
| `iron_tower` | 16 | 22 | 0.5 | 11 | Ground / 地 | 0 |
| `iron_aa_tower` | 75 | 65 | 1.5 | 14 | Air / 空 | 0 |
| `iron_anti_tower` | 95 | 140 | 2.6 | 12 | Ground / 地, Naval / 海 | 0.45 |
| `sky_rifle` | 10 | 18 | 0.65 | 5.8 | Ground / 地 | 0 |
| `sky_anti` | 95 | 120 | 2.8 | 9 | Ground / 地, Naval / 海 | 0 |
| `sky_scout` | 11 | 18 | 0.5 | 7.5 | Ground / 地 | 0 |
| `sky_tank` | 75 | 85 | 2.3 | 10 | Ground / 地, Naval / 海 | 0 |
| `sky_artillery` | 90 | 110 | 3.1 | 16 | Ground / 地, Naval / 海 | 1.5 |
| `sky_aa` | 64 | 65 | 1.2 | 13.5 | Air / 空 | 0 |
| `sky_disruptor` | 35 | 9999 | 2.4 | 10 | Ground / 地, Air / 空, Naval / 海 | 1.7 |
| `sky_pulse` | 165 | 140 | 4.2 | 15 | Ground / 地 | 0 |
| `sky_fighter` | 140 | 65 | 0.65 | 11 | Air / 空 | 0 |
| `sky_attacker` | 156 | 120 | 1.7 | 8.8 | Ground / 地 | 0 |
| `sky_tower` | 18 | 22 | 0.55 | 12 | Ground / 地 | 0 |
| `sky_aa_tower` | 65 | 65 | 1.15 | 15 | Air / 空 | 0 |
| `sky_anti_tower` | 110 | 140 | 2.7 | 13 | Ground / 地, Naval / 海 | 0 |
| `rivet_ship_frigate` | 83 | 105 | 1.7 | 12 | Ground / 地, Naval / 海 | 1 |
| `rivet_ship_signature` | 205 | 160 | 3.5 | 15 | Naval / 海, Ground / 地 | 2 |
| `kestrel_ship_frigate` | 67 | 105 | 1.35 | 13 | Ground / 地, Naval / 海 | 0.5 |
| `kestrel_ship_signature` | 150 | 160 | 2.65 | 16 | Naval / 海, Ground / 地, Air / 空 | 1.1 |
| `iron_ship_frigate` | 75 | 105 | 1.65 | 12 | Ground / 地, Naval / 海 | 0.6 |
| `iron_ship_signature` | 175 | 160 | 3.2 | 15.5 | Naval / 海, Ground / 地 | 1.5 |
| `sky_ship_frigate` | 64 | 105 | 1.15 | 13.5 | Ground / 地, Naval / 海 | 0.35 |
| `sky_ship_signature` | 165 | 9999 | 3 | 16 | Naval / 海, Ground / 地, Air / 空 | 0 |
| `sky_creator_hand` | 300 | 9999 | 7 | 6.5 | Ground / 地, Air / 空, Naval / 海 | 3 |
| `rivet_engineer` | 12 | 18 | 0.9 | 5 | Ground / 地 | 0 |
| `iron_train` | 210 | 140 | 4.2 | 30 | Ground / 地, Naval / 海 | 1.8 |
| `rivet_zeppelin` | 220 | 120 | 3.8 | 2.5 | Ground / 地, Naval / 海 | 2.8 |
| `kestrel_heavy_tank` | 110 | 125 | 2.4 | 10 | Ground / 地, Naval / 海 | 1 |
| `rivet_heavy_tank` | 135 | 125 | 2.8 | 9.5 | Ground / 地, Naval / 海 | 1.2 |
| `iron_heavy_tank` | 115 | 125 | 2.5 | 10 | Ground / 地, Naval / 海 | 0.8 |
| `sky_heavy_tank` | 120 | 125 | 2.5 | 11 | Ground / 地, Naval / 海 | 0 |
| `kestrel_advanced_tower` | 87.5 | 125 | 1.8 | 17 | Ground / 地, Naval / 海 | 1.1 |
| `rivet_advanced_tower` | 180 | 125 | 2.1 | 17 | Ground / 地, Naval / 海 | 1.1 |
| `iron_advanced_tower` | 77.8 | 125 | 1.8 | 16 | Ground / 地, Naval / 海 | 1.1 |
| `sky_advanced_tower` | 79.5 | 125 | 1.8 | 17 | Ground / 地, Naval / 海 | 0 |
| `kestrel_aa_tower` | 70 | 65 | 1.15 | 15 | Air / 空 | 0 |
| `rivet_zeppelin_mg` | 12 | 18 | 0.18 | 6 | Ground / 地, Air / 空, Naval / 海 | 0 |
| `rivet_gunner` | 12 | 24 | 0.23 | 6.6 | Ground / 地 | 0 |
| `rivet_grenadier` | 62 | 55 | 2.6 | 7.2 | Ground / 地 | 1.15 |
| `kestrel_gunner` | 10 | 22 | 0.22 | 7 | Ground / 地 | 0 |
| `kestrel_marksman` | 60 | 30 | 2.9 | 11 | Ground / 地 | 0 |
| `kestrel_aa_infantry` | 68 | 70 | 2.4 | 11.5 | Air / 空 | 0 |
| `iron_marksman` | 60 | 36 | 3.2 | 12 | Ground / 地 | 0 |
| `iron_mortar` | 80 | 70 | 3.8 | 13 | Ground / 地 | 1.5 |
| `sky_storm` | 22 | 9999 | 1.4 | 7 | Ground / 地, Air / 空 | 0.8 |
| `sky_aa_infantry` | 62 | 75 | 2 | 12.5 | Air / 空 | 0 |
| `kestrel_helicopter` | 42 | 55 | 0.9 | 11 | Ground / 地, Naval / 海 | 0.5 |
| `kestrel_submarine` | 115 | 95 | 3.6 | 13 | Naval / 海 | 0.5 |
| `kestrel_amphibious` | 54 | 60 | 1.4 | 9 | Ground / 地, Naval / 海 | 0.5 |
| `kestrel_support_ship` | 150 | 100 | 4.8 | 22 | Ground / 地, Naval / 海 | 0.5 |
| `kestrel_carrier` | 1 | 0 | 14 | 25 | Ground / 地, Naval / 海 | 0.5 |
| `kestrel_carrier_plane` | 65 | 70 | 1.2 | 8 | Ground / 地, Naval / 海 | 0.5 |
| `rivet_helicopter` | 42 | 55 | 0.9 | 11 | Ground / 地, Naval / 海 | 1 |
| `rivet_submarine` | 115 | 95 | 3.6 | 13 | Naval / 海 | 1 |
| `rivet_amphibious` | 54 | 60 | 1.4 | 9 | Ground / 地, Naval / 海 | 1 |
| `rivet_support_ship` | 150 | 100 | 4.8 | 22 | Ground / 地, Naval / 海 | 1 |
| `rivet_carrier` | 1 | 0 | 14 | 25 | Ground / 地, Naval / 海 | 1 |
| `rivet_carrier_plane` | 65 | 70 | 1.2 | 8 | Ground / 地, Naval / 海 | 1 |
| `iron_helicopter` | 42 | 55 | 0.9 | 11 | Ground / 地, Naval / 海 | 0.6 |
| `iron_submarine` | 115 | 95 | 3.6 | 13 | Naval / 海 | 0.6 |
| `iron_amphibious` | 54 | 60 | 1.4 | 9 | Ground / 地, Naval / 海 | 0.6 |
| `iron_support_ship` | 150 | 100 | 4.8 | 22 | Ground / 地, Naval / 海 | 0.6 |
| `iron_carrier` | 1 | 0 | 14 | 25 | Ground / 地, Naval / 海 | 0.6 |
| `iron_carrier_plane` | 65 | 70 | 1.2 | 8 | Ground / 地, Naval / 海 | 0.6 |
| `sky_helicopter` | 42 | 55 | 0.9 | 11 | Ground / 地, Naval / 海 | 0.35 |
| `sky_submarine` | 115 | 95 | 3.6 | 13 | Naval / 海 | 0.35 |
| `sky_amphibious` | 54 | 60 | 1.4 | 9 | Ground / 地, Naval / 海 | 0.35 |
| `sky_support_ship` | 150 | 100 | 4.8 | 22 | Ground / 地, Naval / 海 | 0.35 |
| `sky_carrier` | 1 | 0 | 14 | 25 | Ground / 地, Naval / 海 | 0.35 |
| `sky_carrier_plane` | 65 | 70 | 1.2 | 8 | Ground / 地, Naval / 海 | 0.35 |
| `kestrel_ship_aa` | 46 | 60 | 0.6 | 15 | Air / 空 | 0 |
| `rivet_ship_aa` | 94 | 60 | 1.2 | 14.5 | Air / 空 | 0 |
| `iron_ship_aa` | 75 | 60 | 0.9 | 15 | Air / 空 | 0 |
| `sky_ship_aa` | 52 | 60 | 0.65 | 17 | Air / 空 | 0 |

Asset attribution: [assets/LICENSE.md](../assets/LICENSE.md).
