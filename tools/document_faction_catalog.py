#!/usr/bin/env python3
"""Publish the four playable factions from the current game rules."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
r = json.loads((ROOT / "data/rules.json").read_text())
factions = ["kestrel", "rivet", "iron", "sky"]
trait_text = json.loads((ROOT / "scripts/faction_trait_text.json").read_text())
target_labels = {"ground": "地", "air": "空", "naval": "海"}
emp_unit_name = r["units"]["sky_disruptor"]["name"]
voice_manifest = json.loads((ROOT / "assets/audio/revision_v8/radio/manifest.json").read_text())
voice_clips = voice_manifest.get("clips", [])
voice_groups = {(clip["faction"], clip["category"], clip["action"]) for clip in voice_clips}
def voice_category(spec):
    if spec.get("voice_category") in ("infantry", "vehicle", "air"):
        return spec["voice_category"]
    if spec.get("domain", "ground") == "air": return "air"
    if spec.get("infantry") or spec.get("art") in ("rifle", "anti", "engineer", "demolition"):
        return "infantry"
    return "vehicle"
spoken_units = {unit for unit, spec in r["units"].items()
                if all((spec["faction"], voice_category(spec), action) in voice_groups
                       for action in ("select", "move", "attack", "ready", "return", "combat", "under_attack", "death"))}
speech_coverage = "、".join(
    f"{r['factions'][faction]['name']}{sum(r['units'][unit]['faction'] == faction for unit in spoken_units)}种"
    for faction in factions
)

def faction_trait_description(faction):
    config = r["factions"][faction].get("traits", {})
    hq = r["buildings"][faction + "_hq"]
    barracks = hq if faction == "rivet" and hq.get("rebuildable", False) else r["buildings"].get(faction + "_barracks", {})
    values = {"delay": f'{config.get("regen_delay", 0):g}',
              "regen": f'{config.get("regen_fraction_per_second", 0) * 100:g}',
              "barracks_cost": f'{barracks.get("cost", 0):g}',
              "barracks_build_time": f'{barracks.get("build_time", 0):g}',
              "barracks_local_power": f'{barracks.get("local_power", 0):g}',
              "barracks_local_power_radius": f'{barracks.get("local_power_radius", 0):g}',
              "barracks_construction_radius": f'{barracks.get("construction_radius", 0):g}',
              "local_power": f'{hq.get("local_power", 0):g}',
              "local_power_radius": f'{hq.get("local_power_radius", 0):g}'}
    field = "standard_description" if faction == "rivet" and r["factions"][faction].get("building_method", "") != "engineer" else "description"
    if faction == "rivet" and field == "description" and not hq.get("rebuildable", False):
        field = "legacy_engineer_description"
    descriptions = [trait_text[faction][field].format(**values)]
    if faction == "iron" and config.get("regen_fraction_per_second", 0) > 0:
        descriptions.append(trait_text["iron"]["regeneration"].format(**values))
    if faction == "sky":
        emp = r["weapons"].get("sky_disruptor", {})
        if emp.get("emp_vehicle_duration"):
            description = trait_text["emp"]["description"]
            _, trigger, effect = description.partition("命中")
            if trigger:
                description = emp_unit_name + trigger + effect
            descriptions.append(description.format(
                vehicle=f'{emp["emp_vehicle_duration"]:g}', building=f'{emp["emp_building_duration"]:g}'))
    if hq.get("local_power", 0) > 0:
        power_field = "base_barracks_description" if faction == "rivet" and hq.get("rebuildable", False) else "description"
        descriptions.append(trait_text["hq_power"][power_field].format(**values))
    return " ".join(descriptions)

paper_count = sum(bool(spec.get("crushable", False)) for spec in r["units"].values())
skin_count = sum(spec.get("art") == "creator_hand" for spec in r["units"].values())
solid_count = len(r["buildings"]) + len(r["units"]) - paper_count - skin_count
hand_rig = json.loads((ROOT / "assets/creator_hand/rig.json").read_text())
hand_bones = len(hand_rig["bone_names"])
lines = ["# 四阵营单位与建筑目录", "",
    "依据[四阵营世界观与美术设定 v4.1](派系设定/paper_front_world_setting_four_factions.md)及当前 `data/rules.json` 生成。运行 `python3 tools/document_faction_catalog.py` 可更新数值表。铁钉与天翼的设计修订和机制边界见[扩展说明](expansion_factions.md)。", "",
    "## 身份与资产", "",
    "正典军团、重锤军团、铁钉同盟、天翼教团均为当前可选阵营。固定基础配色与独立玩家识别区共同保留：正典蓝漆、重锤暗红漆、铁钉赭黄与石墨结构、天翼象牙底纸与靛紫刷痕。选择圈、血条、小地图及模型识别区使用所属玩家色。", "",
    "稳定内部 ID 为 `kestrel`、`rivet`、`iron`、`sky`，单位重命名保持既有引用兼容。旧存档自带规则快照；当前规则用于新开对局。", "",
    f"当前目录共 **{len(r['units'])} 种单位、{len(r['buildings'])} 种建筑、{len(r['weapons'])} 套武器**。模型类别为 **{solid_count} 个实体建筑／地面载具／飞机／舰艇条目、{skin_count} 种连续皮肤蒙皮巨手、{paper_count} 种纸片步兵**；这些是目录条目分类，不是网格或骨骼数量。步兵保留五状态切边与玩家识别遮罩，铁钉与天翼保留可靠工业工艺与简陋纸盒高科技构造。数值是当前规则基线，持续平衡以对战结果为准。", "",
    f"创世之手现使用 MakeHuman Community 的 CC0 图形基础网格裁出的连续手部皮肤，通过 GLB、Skin 与 {hand_bones} 骨 Skeleton3D 变形；五指不再以13块刚体拼接。骨数是当前美术资产说明，不是玩法限制。只使用图形网格，没有把 MakeHuman 应用程序代码纳入游戏；[来源与许可](../assets/creator_hand/README.md)、[官方资产许可副本](../assets/creator_hand/MAKEHUMAN_LICENSE_ASSETS.md)及[来源校验记录](../assets/creator_hand/source_provenance.json)随源工程保留。", "",
    "## 阵营作战机制", "",
    f"机制说明与游戏阵营卡、单位介绍共用 `scripts/faction_trait_text.json`，参数来自当前规则。阵营差异来自具体兵种、生产与工程机制；全军加成仅暂时保留铁钉单位的脱战自愈。天翼EMP由{emp_unit_name}的武器触发，标定、蓄能与维修遵守对应平台的现场条件。", "",
    "| 阵营 | 当前机制 |", "|---|---|"]
for faction in factions:
    lines.append(f"| {r['factions'][faction]['name']} | {faction_trait_description(faction)} |")
lines += ["", "经济基线按同样条件统一：采速、货量与开局资金来自共享经济规则；矿车、精炼厂和截击机的实际生命与弹药以下表为准。具体装备的维修、目标标定与局部蓄能分别结算。", "",
          "| 阵营 | 矿车生命 | 精炼厂生命 | 截击机弹药 |", "|---|---:|---:|---:|"]
for faction in factions:
    lines.append(f"| {r['factions'][faction]['name']} | {r['units'][faction + '_harvester']['hp']} | {r['buildings'][faction + '_refinery']['hp']} | {r['units'][faction + '_fighter']['ammo_capacity']} |")
lines += ["", "## 空军、维修与运输", "",
    "飞机从机场生产，具有空中高度和独立飞行移动，可越过地面障碍。截击机与防空车只对空；攻击机、轰炸机与其他武器遵守各自空地目标配置。有限弹药耗尽后自动返航补给，也可按 B 返航；机场损毁后寻找备用机场，缺少保障时进入等待状态。", "",
    "| 阵营 | 每座机场机位（含生产队列） | 停机维护速度 |", "|---|---:|---|"]
for faction in factions:
    fields = [s for s in r["buildings"].values() if s["faction"] == faction and s.get("role") == "airfield"]
    if fields:
        field = fields[0]
        maintenance = field.get("aircraft_repair_rate", 0)
        lines.append(f"| {r['factions'][faction]['name']} | {field.get('aircraft_capacity', 4)} | {str(maintenance) + ' 生命/秒，按实际恢复付费' if maintenance else '沿用弹药补给，无专属付费维护'} |")
lines += ["",
    "重锤工程兵在现场搭建全部建筑，普通建筑限于基地兵营的建设范围内；基地兵营可在已有范围外选址，开局与工兵新建的是同一种建筑，完工后继续扩张。其他阵营工程兵可在范围外现场建设分基地。脚手架均按施工进度付费，受损后先维修再施工，工兵离开或阵亡后暂停，可由其他工兵接手。基础修理和桥梁作业继续使用统一规则。维修站通电后付费修复范围内地面装甲；多个维修来源取最高速度，不能叠加。扳手维修车、检验车与吊装工程车右键受损己方地面载具后靠近维修，不修复步兵、建筑或飞机。费用沿用现有资金体系，不添加零件资源。", "",
    f"当前维修费用为 **{r['economy'].get('repair_cost', .2)} 资金/恢复生命**。机场停机维护同样按实际恢复生命付费；低电停止维护。飞机弹药补给按机场与出动周期进行。", "",
    "右下第三格为「装载/卸载」两动作菜单。装载时先选己方载具再点地面步兵，或先选步兵再点载具；包括工兵和反甲兵，有余位可继续补员。菜单显示空位/人数，未选有运输资格的对象时禁用；具体容量按单位条目读取。卸载动作或 U 后左键指定合法空地/登陆海岸，载具到达后下客；也保留当前位置卸载按钮和步兵右键己方载具登乘。运输机 L 后左键指定合法空地降落；B 主动返航维修补给后停机，移动命令重新起飞；自动弹尽返航保留原任务，服务完成后恢复。", "",
    "四阵营船坞直接建在海面上，全部占地须为水域，并保留可出航及往返登陆海岸的通道；仍受己方扩建/港湾权限与前置约束。运输船只能在合法海岸登卸步兵。旧存档保留旧规则中的岸边船坞位置，重新开局使用全海面选址。", "",
    "## 铁钉与天翼支援规则", "",
    "| 平台 | 当前行为 |", "|---|---|",
    "| 扳手维修车 | 半径4.5，每秒恢复14生命；按实际恢复生命付费。 |",
    "| 检验车 | 半径4，每秒恢复9生命；手绘刻度板与工具柜表现现场检验。 |",
    "| 吊装工程车 | 半径3，每秒恢复6生命；作为低速辅助保障。 |",
    "| 拖救车 | 右键仍存活的友方受损地面载具持续护送；目标生命≤60%且执行撤离移动时，4格内与可通行连接满足后提供25%速度增量，多车不叠加。 |",
    "| 标定车 | 自动选择范围内敌方地面载具，保持12格距离、视线与1.5秒跟踪后，己方对目标伤害提高15%；追踪中断失效，多车不叠加。 |",
    "| 蓄能站 | 附近武装单位交战时自动消耗60资金及80电力余量，8格内提供5秒20%伤害增量，再等待25秒散热充能；低电中断，多站增幅不叠加。 |", "",
    f"指挥中心扩大自动索敌范围，不能扩大武器射程。正典、铁钉与天翼总部失守后，存活分基地可继续授权建设；重锤取消分基地，每座基地兵营提供前线扩张与局部供电，工程兵继续现场施工，也可重新建造基地兵营。{emp_unit_name}的EMP按装甲单位与建筑分别计时，步兵不受影响；受到EMP的目标暂停对应作业，状态可在选中信息中查看。", "",
    "## 科技流程", "",
    "正典、铁钉、天翼选择已完成总部/分基地，下方显示已解锁的常规与防御建筑；两类订单各有独立队列。重锤基地兵营只显示步兵生产，开局即可使用；选中重锤工程兵显示常规与防御建筑，全部通过现场脚手架施工。重锤开局与扩张统一使用基地兵营，每座都提供建设范围、局部供电与独立步兵生产队列。选择兵营、工厂、机场或船坞时，只显示该设施能生产的单位，并把订单放入所选设施的独立队列。不选对象或选择其他非生产对象时，下方栏隐藏。", "",
    "科技前置、阵营或生产资格不满足的项目直接隐藏。正典、铁钉与天翼总部不可重造，重锤基地兵营可建造多座，也可在失守后重建。资金暂不足、队列占用或机场机位已满时，已解锁卡保留费用和状态，避免目录闪烁。其他阵营工兵在右侧独立「部署分基地」操作中选址，不唤起下方建筑目录；重锤工兵可从建筑目录选址。抵达后施工并随进度付款，均可重新选址或取消。", "",
    "标准流程为总部 → 电站 → 精炼厂与兵营 → 载具工厂 → 维修站／指挥中心／研究所。重锤基地兵营同时满足基地和兵营前置，先训练工兵再建设电站与精炼厂即可开启载具工厂；新建基地兵营用于扩张和增加独立步兵生产队列，价格高于其他阵营的普通兵营。机场、船坞及高级装备按各条目的前置开放。下表的「地/空/海」读取武器 targets，表示攻击域，不能把单位所在的移动领域当成攻击域；例如创世之手在地面行走，其武器按当前规则可攻击地、空、海目标。以下价格、生命、攻击数值与前置均直接来自当前规则。", ""]
for faction in factions:
    lines += [f"## {r['factions'][faction]['name']}", "", r['factions'][faction]['motto'], "", "### 单位数值", "", "| 单位 / 正式型号 | 价格 | 生命 | 速度 | 生产秒数 | 攻击域 | 伤害 / 间隔 / 射程 | 弹药 | 前置 |", "|---|---:|---:|---:|---:|---|---|---:|---|"]
    for uid, spec in r['units'].items():
        if spec['faction'] != faction: continue
        w = r['weapons'].get(spec['weapon'], {})
        targets = "/".join(target_labels.get(target, target) for target in w.get('targets', [])) or "无"
        weapon = f"{w['damage']} / {w['interval']} / {w['range']}" if w else "无"
        requires = "、".join(r['buildings'][x]['name'] for x in spec['requires']) or "生产设施"
        lines += [f"| {spec['name']} / {spec['formal_name']} | {spec['cost']} | {spec['hp']} | {spec['speed']} | {spec['build_time']} | {targets} | {weapon} | {spec.get('ammo_capacity','—')} | {requires} |"]
    lines += ["", "武器对不同类型目标的伤害倍率见 `data/rules.json` 的 `multipliers`；未配置项为 1。", "", "### 建筑数值", "", "| 建筑 | 价格 | 生命 | 建造秒数 | 电力 | 占地 | 前置 |", "|---|---:|---:|---:|---:|---|---|"]
    for bid, spec in r['buildings'].items():
        if spec['faction'] != faction: continue
        requires = "、".join(r['buildings'][x]['name'] for x in spec['requires']) or "无"
        display_name = spec['name']
        lines += [f"| {display_name} | {spec['cost']} | {spec['hp']} | {spec['build_time']} | {spec['power']:+} | {spec['size']}×{spec['size']} | {requires} |"]
    lines += ["", "### 说明与语音", "", "| 单位 | 用途与限制 | 选中 / 移动 / 攻击 / 就绪 |", "|---|---|---|"]
    for uid, spec in r['units'].items():
        if spec['faction'] != faction: continue
        voice = " / ".join(spec['voices'][k][0] for k in ['select','move','attack','ready'])
        lines += [f"| {spec['name']} | {spec['description']} | {voice} |"]
    lines += [""]
lines += ["## 生成与验证记录", "",
    "数值目录由本工具读取当前规则生成，不代表本轮已经完成回归或发行。[v6 实施与待验收记录](revision_v6_validation.md)跟踪当前模型、交互与地图重建；[v5 四阶段扩展验证](expansion_v5_validation.md)是此前发行的历史结果，不可替代 v6。铁钉与天翼模型源在 `scripts/iron_models.gd` 与 `scripts/sky_models.gd`；更早的[阵营修订验证](faction_revision_validation.md)与[首发制作验证](faction_validation.md)继续保留。", "",
    "```sh", "python3 tools/document_faction_catalog.py", "```", "",
    f"当前 `assets/audio/revision_v8/radio/manifest.json` 登记 **{len(voice_clips)} 条新普通话合成语音**，覆盖 **{len(spoken_units)} 种单位**：{speech_coverage}。每个阵营的步兵、车辆、空军各共用一套声音，选择、移动、攻击、就绪、返程、交战、遇袭、死亡八种情境各有三条不同的实际录音文件。音频来源与格式记录在 manifest 中，游玩无需联网；制作和检查见[音频记录](revision_v8_audio.md)，重制命令为 `python3 tools/generate_revision_v8_audio.py --generate`。", "",
    f"当前还有 {len(r['units']) - len(spoken_units)} 种单位缺少完整阵营／类别情境覆盖。旧机械应答与旧语音银行已从活动游戏素材移除，不作为播放回退；历史生成器和 v7 对应源记录只保留为开发档案。", ""]
(ROOT / 'docs/faction_catalog.md').write_text('\n'.join(lines), encoding="utf-8")
print('docs/faction_catalog.md updated for four playable factions')
