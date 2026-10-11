#!/usr/bin/env python3
"""Generate a bilingual reference from the rules used by new matches."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rules = json.loads((ROOT / 'data/rules.json').read_text(encoding='utf-8'))
english = json.loads((ROOT / 'data/localization/en_content.json').read_text(encoding='utf-8'))
FACTIONS = ('kestrel', 'rivet', 'iron', 'sky')
DOMAINS = {'ground': 'Ground / 地', 'air': 'Air / 空', 'naval': 'Naval / 海'}


def text(value):
    source = str(value)
    translated = english.get(source, source)
    return source if translated == source else f'{translated} / {source}'


def number(value):
    return f'{float(value):g}'


def cell(value):
    return str(value).replace('|', '\\|').replace('\n', ' ')


def name(spec_id):
    for catalog in ('units', 'buildings', 'weapons'):
        if spec_id in rules[catalog]:
            return text(rules[catalog][spec_id].get('name', spec_id))
    return str(spec_id)


def squad_size(spec):
    # Same eligibility and bounds as scripts/infantry_squads.gd.
    if (spec.get('armor_class') != 'infantry'
            or spec.get('domain', 'ground') != 'ground'
            or spec.get('art') == 'engineer'):
        return 1
    return max(1, min(6, int(spec.get('squad_size', 1))))


def table(headers, rows):
    output = ['| ' + ' | '.join(headers) + ' |', '|' + '---|' * len(headers)]
    output.extend('| ' + ' | '.join(cell(value) for value in row) + ' |' for row in rows)
    return output


lines = [
    '# Faction reference / 四阵营规则目录', '',
    'Generated from [data/rules.json](../data/rules.json) and the English content catalog. '
    'Run `python3 tools/document_faction_catalog.py` after changing either. '
    'These are the rules for **new matches**; older saves retain their own snapshots.', '',
    '本页直接读取当前规则和英文翻译目录生成。更改规则后运行上述命令更新；旧存档继续使用自己的规则快照。', '',
    f"Current catalog: **{len(rules['units'])} unit definitions, {len(rules['buildings'])} building definitions, "
    f"{len(rules['weapons'])} weapon definitions**. Counts include specialized and compatibility definitions; "
    'they are not the number of cards available from one production building.', '',
    '目录数量含专用及兼容定义，不等于单座生产建筑可购买的卡片数量。', '',
    '## How to read the tables / 表格说明', '',
    '- Unit cost and training time describe **one complete purchase**. For infantry squads, '
    'health, armor, movement speed and weapons describe each individual soldier.',
    '- Squad members keep separate health, collisions, weapons, experience and transport seats. '
    'The order cost is per-person cost × squad size; time uses `squad_build_time` when present, '
    'otherwise per-person time × squad size.',
    '- Building time is the rule processing/construction time; travel, doorway clearance and '
    'resource shortages can add delay. Power is signed generation/consumption; local base power is separate.',
    '- Weapon targets describe what can be attacked, independently of the movement domain. '
    'Damage modifiers, splash, EMP and other special fields remain in the source JSON and in-game Wiki.', '',
    '单位价格和时间是整次购买；小队生命、护甲、速度与武器是每名成员的数据。'
    '实际生产还受出入口、前置、供电和资金影响。伤害倍率、溅射与特殊效果请查看游戏图鉴及规则 JSON。', '',
    'For mechanics, see [Game design](design.md). Background is in '
    '[the worldbuilding reference](派系设定/paper_front_world_setting_four_factions.md).', '',
]

for faction_id in FACTIONS:
    faction = rules['factions'][faction_id]
    lines += [f"## {text(faction['name'])}", '', f'Stable ID: `{faction_id}`', '',
              text(faction.get('description', '')), '', '### Units / 单位', '']
    rows = []
    for spec_id, spec in rules['units'].items():
        if spec.get('faction') != faction_id:
            continue
        members = squad_size(spec)
        rows.append([
            f"{text(spec['name'])}<br>`{spec_id}`", members,
            number(spec.get('cost', 0) * members), number(spec.get('hp', 0)),
            number(spec.get('armor', 0)), number(spec.get('speed', 0)),
            number(spec.get('squad_build_time', spec.get('build_time', 0) * members)),
            DOMAINS.get(spec.get('domain', 'ground'), spec.get('domain')),
            f"`{spec['weapon']}`" if spec.get('weapon') else '—',
            str(spec.get('producer', '—')),
            '; '.join(name(item) for item in spec.get('requires', [])) or '—',
        ])
    lines += table(['Unit / 单位', 'Members / 人数', 'Order cost / 整队费用', 'HP / 生命',
                    'Armor / 护甲', 'Speed / 速度', 'Seconds / 秒', 'Domain / 移动域',
                    'Weapon / 武器', 'Producer / 设施角色', 'Requires / 前置'], rows)
    lines += ['', '### Buildings / 建筑', '']
    rows = []
    for spec_id, spec in rules['buildings'].items():
        if spec.get('faction') != faction_id:
            continue
        size = spec.get('size', '—')
        rows.append([
            f"{text(spec['name'])}<br>`{spec_id}`", number(spec.get('cost', 0)),
            number(spec.get('hp', 0)), number(spec.get('armor', 0)),
            number(spec.get('build_time', 0)), number(spec.get('power', 0)),
            f'{size} × {size}', spec.get('role', '—'),
            '; '.join(name(item) for item in spec.get('requires', [])) or '—',
        ])
    lines += table(['Building / 建筑', 'Cost / 费用', 'HP / 生命', 'Armor / 护甲',
                    'Seconds / 秒', 'Power / 电力', 'Footprint / 占地', 'Role / 角色', 'Requires / 前置'], rows)
    lines += ['']

lines += ['## Weapons / 武器', '',
          'Base values before target multipliers, veterancy and splash falloff. / '
          '以下为基础数值，尚未计算目标倍率、老兵或溅射衰减。', '']
rows = []
for spec_id, spec in rules['weapons'].items():
    rows.append([f'`{spec_id}`', number(spec.get('damage', 0)), number(spec.get('penetration', 0)),
                 number(spec.get('interval', 0)), number(spec.get('range', 0)),
                 ', '.join(DOMAINS.get(item, item) for item in spec.get('targets', ['ground'])),
                 number(spec.get('blast', 0))])
lines += table(['ID', 'Damage / 伤害', 'Penetration / 穿深', 'Interval / 间隔秒',
                'Range / 射程', 'Targets / 攻击域', 'Blast / 溅射'], rows)
lines += ['', 'Asset attribution: [assets/LICENSE.md](../assets/LICENSE.md).', '']
(ROOT / 'docs/faction_catalog.md').write_text('\n'.join(lines), encoding='utf-8')
print('docs/faction_catalog.md updated from current rules')
