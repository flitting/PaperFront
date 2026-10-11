# Game mechanics / 当前玩法设计

This describes current new-match behavior. [data/rules.json](../data/rules.json), simulation modules and the in-game Wiki are authoritative for exact values. Historical saves carry their own rules. For keyboard bindings and the first-match walkthrough, see [the README](../README.md).

本页说明当前新对局。价格、前置和特殊能力以当前规则与游戏图鉴为准；旧存档保留旧规则。本页不把世界观中的长期战役构想当作已完成玩法。

## Match structure / 对局结构

The game offers one tutorial mission and single-player skirmishes with 2–4 armies. Six main battlefield profiles are 320 × 320; the symmetric land map is 192 × 192 and supports two armies. The development map is available through development controls. Older map generators remain for compatibility, but do not all appear in the new-match menu.

Each army begins with its faction base and 4000 funds. Defeat is determined by loss of every building that counts toward survival, excluding walls, barricades and rails; losing the Headquarters alone does not always end a match. A simultaneous loss in the same damage settlement can draw.

## Economy, construction and power / 经济、施工与供电

Canon, Long Nail and Skywing process ordinary building orders through completed Headquarters/Outposts, then place completed orders on legal terrain. Normal and defensive construction channels are independent. Engineers can establish Outposts outside the existing base radius by moving to a site and constructing paid scaffolding.

Heavy Hammer uses Base Barracks instead. Every Base Barracks produces infantry and engineers, provides local power and construction coverage, and can be rebuilt or duplicated. Its engineers build all structures on site; normal sites need Base Barracks coverage, while a new Base Barracks can expand beyond it. Work progresses only with the required engineer and funds. Damaged scaffolding is repaired before construction continues. Another engineer can take over interrupted work; dismantling does not refund already spent construction funds.

Crystal deposits are persistent resources in current new matches. Ordinary harvesters mine and deliver to a refinery; the initial refinery includes its configured free harvester. Long Nail mining vehicles require friendly railway. Heavy Hammer engineers build mining drills at deposits instead of relying on the ordinary refinery/harvester economy. Congested doors and mining positions must clear rather than producing overlapping units.

Bases provide local power: capacity and distance are separate constraints. Distant buildings still need nearby supply. Low power slows construction/production and disables affected defenses and service operations; existing troops and harvesting continue according to their own rules.

正典、长钉与天翼先加工普通建筑订单，再选择合法地面放置；工兵可在范围外搭建分基地。重锤全部建筑由工兵现场施工，基地兵营可重复建造并拓展建设范围。供电同时受容量和距离约束，堵门不会重叠生成单位。当前矿点持续供给，长钉矿车需轨道，重锤靠矿脉钻机建立收入。

## Troops and movement / 部队与移动

Combat infantry recruit in 2–6 person squads depending on role; engineers remain independent. Each squad member is a real soldier with separate health, collision, weapon cooldown, veterancy and transport seat. Selecting a member selects the available squad. Casualties preserve group identity and a survivor becomes its representative. One purchase pays the whole squad cost; sequential emergence uses the actual production doorway. There is no free replenishment.

Ground movement uses terrain-aware paths, continuous footprint checks, local avoidance and yielding. Different units need different clearance. Movement orders and attack-move are distinct; tanks with suitable weapons can move while their turrets engage. Railway vehicles use track, ships navigate water, amphibious units cross appropriate shore connections, and aircraft use a separate aerial movement domain.

Some vehicles can crush enemy infantry, with heavy units having different crush rules. Friendly infantry are protected from vehicle crushing. Engineers can repair, capture eligible enemy buildings and rebuild broken bridges through contextual commands. Ordinary combat infantry can garrison suitable neutral houses; engineers cannot. Transports reserve one seat per real member and require legal boarding/unloading conditions.

## Combat and technology / 战斗与科技

Weapons have explicit target domains, ranges, armor penetration, damage modifiers and special behavior. A ground-moving unit is not necessarily limited to ground targets. Projectiles can retain their fired landing point; splash damage can affect allies and falls off with distance. Normal move/attack-move does not automatically destroy neutral scenery; force attack can target trees, houses, stone walls and friendly objects. Bridges can be attacked, destroyed and repaired.

Current armor damage tiers use effective penetration:

| Condition | Damage factor |
|---|---:|
| Armor is zero, or penetration exceeds armor | 100% |
| Penetration reaches 80% of armor without exceeding armor | 50% |
| Penetration is below 80% of armor | 25% |

These are damage factors, not hit probabilities. Splash can reduce effective penetration with distance. Old snapshots without the threshold field retain their older behavior. Light/medium/heavy building armor and unit roles make dedicated anti-armor and siege support useful rather than providing a universal tank bonus.

Combat value earned from enemy kills grants veterancy after the configured threshold. Veteran bonuses and the doubled experience value of killing an enemy veteran are rule fields. Friendly kills do not grant experience; increased experience is not extra income.

Technology follows facility prerequisites. Barracks open T1, a factory or airfield opens T2, and the faction technology building opens T3; Heavy Hammer Base Barracks also fills the barracks role. Cards hide unavailable technology, while the Wiki remains a full reference. Aircraft with finite ammunition return for servicing; permanent airborne helicopter/airship behavior and carrier operations follow each unit's specific definition.

护甲判定是伤害倍率，不是命中概率。专职反甲与攻城装备通过穿深和目标倍率发挥作用。伤害、命令、占领、铁路、运输、生产与经验均属于模拟状态，而非画面效果。新旧存档依各自规则判定。

## Information and AI / 信息与电脑

Visibility uses observers, terrain and target detection, with last-known enemy records. AI acts on its own units, the public map and observed enemy information. It buys production and construction through ordinary interfaces, without extra funds or damage bonuses. Difficulty and strategy affect decision timing, budgets and force composition.

Balanced, pressure and armor strategies share a land planner with faction adapters for construction, mining, rails and unit choices. Naval and campaign behavior have their own paths. Historical experiments establish behavior only under their documented conditions; they do not certify all maps, late-game behavior or equal faction strength. See [AI experiments](ai_balance_experiments.md).

## Presentation and persistence / 表现与持久化

Vehicles/buildings use 3D paper models; infantry are cut-paper figures. Rendering uses model and scenery levels of detail while retaining simulation positions, collision, targeting and unit counts. Camera movement, zoom, orbit and pitch are player controls. Lower render scale reduces the internal 3D resolution while keeping UI/click coordinates at native resolution.

The Settings gear manages graphics, camera, audio and independent interface/voice languages. Saving captures the actual map, current rules and simulation state. Match reports retain time-series statistics and events, rather than a playable replay. See [architecture](architecture.md) and [statistics](balance_preparation.md).
