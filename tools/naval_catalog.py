"""Deterministic Stage 3 naval rules extension.

``apply`` is idempotent and intentionally merges into an existing catalog.  Both
full and expansion catalog generators may call it after their balance pass.
"""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
FACTIONS = ("rivet", "kestrel", "iron", "sky")
SHIP_STATS = {
    "rivet": {"transport": (850, 690, 3.4, 7), "frigate": (1550, 1150, 3.0, 1), "signature": (2700, 1800, 2.5, 1)},
    "kestrel": {"transport": (780, 610, 3.8, 7), "frigate": (1490, 980, 3.5, 1), "signature": (2450, 1470, 3.1, 1)},
    "iron": {"transport": (800, 760, 3.2, 8), "frigate": (1510, 1200, 3.0, 1), "signature": (2550, 1700, 2.7, 1)},
    "sky": {"transport": (900, 580, 4.1, 7), "frigate": (1620, 900, 3.8, 1), "signature": (2750, 1380, 3.5, 1)},
}
NAMES = {
    "rivet": ("铁甲渡船", "破浪炮舰", "重锤攻城舰", "钢铆船坞"),
    "kestrel": ("编队渡船", "协同护卫舰", "正典指挥舰", "标准船坞"),
    "iron": ("补给渡船", "铆钉护卫舰", "铁钉工坊舰", "工匠船坞"),
    "sky": ("折翼渡船", "天翼护卫舰", "脉冲巡洋舰", "观测船坞"),
}
DESCRIPTIONS = {
    "rivet": ("加厚舷板和双登船坡道，跨岛转运全部地面步兵。", "低矮重装船壳与前后炮座，压制敌舰并支援岸线。", "装甲楔艏、双层重炮座与宽舷板；沿攻击移动推进后首击更强。"),
    "kestrel": ("清晰甲板分区和编号登船口，跨岛转运全部地面步兵。", "轻快护卫舰，兼顾防空、反舰与岸边掩护。", "双舰桥和独立指挥炮座；与两艘同域战舰协同增伤。"),
    "iron": ("结实货舱与修理坡道，跨岛转运全部地面步兵。", "铆接船壳及检修甲板；受击减伤，脱离战斗后缓慢修复。", "移动工坊和分层炮座，舰队维修线上的持久火力核心。"),
    "sky": ("折板外壳、光环吊架与登船口，跨岛转运全部地面步兵。", "纸板翼形舰桥与高射炮座，快速制空护航。", "双环蓄能塔与脉冲炮座；冲击敌舰、岸防与空中目标。"),
}
WEAPON_STATS = {
    "rivet": {"frigate": (83, 1.7, 12.0, 1.0, 22, ["naval", "ground", "air"]), "signature": (205, 3.5, 15.0, 2.0, 19, ["naval", "ground"])},
    "kestrel": {"frigate": (67, 1.35, 13.0, 0.5, 28, ["naval", "ground", "air"]), "signature": (150, 2.65, 16.0, 1.1, 26, ["naval", "ground", "air"])},
    "iron": {"frigate": (75, 1.65, 12.0, 0.6, 22, ["naval", "ground", "air"]), "signature": (175, 3.2, 15.5, 1.5, 21, ["naval", "ground"])},
    "sky": {"frigate": (64, 1.15, 13.5, 0.35, 32, ["naval", "ground", "air"]), "signature": (165, 3.0, 16.0, 1.9, 30, ["naval", "ground", "air"])},
}


def apply(catalog: dict) -> dict:
    """Add/update naval entries in place; preserve all unrelated rules and traits."""
    units = catalog.setdefault("units", {})
    buildings = catalog.setdefault("buildings", {})
    weapons = catalog.setdefault("weapons", {})
    for faction in FACTIONS:
        if faction not in catalog.get("factions", {}):
            continue
        transport_name, frigate_name, signature_name, yard_name = NAMES[faction]
        buildings[f"{faction}_shipyard"] = {
            "name": yard_name, "formal_name": yard_name, "faction": faction,
            "cost": 1450 if faction != "sky" else 1600,
            "hp": 2150 if faction != "iron" else 2400, "build_time": 34,
            "power": -95, "size": 4, "requires": [f"{faction}_factory"],
            "role": "shipyard", "art": "shipyard", "expands": False, "weapon": "",
            "domain": "naval", "harbor_depth": 2.0,
            "animations": {"idle": f"res://assets/cards/{faction}_shipyard_portrait.png", "death": f"res://assets/cards/{faction}_shipyard_death.svg"},
            "description": "全部占地建在水面，保留己方港湾或基地扩建范围；舰艇从合法水面出口出航，步兵仍在岸边登卸。",
        }
        for role, name in zip(("transport", "frigate", "signature"), (transport_name, frigate_name, signature_name)):
            cost, hp, speed, capacity = SHIP_STATS[faction][role]
            spec_id = f"{faction}_ship_{role}"
            unit = {
                "name": name, "formal_name": name, "faction": faction, "art": f"naval_{role}",
                "cost": cost, "hp": hp, "speed": speed,
                "build_time": 24 if role == "transport" else 34 if role == "frigate" else 49,
                # Circular navigation envelopes cover the whole visible hull,
                # including its long bow and stern at shoreline turns.
                "radius": 2.2 if role == "transport" else 2.65 if role == "frigate" else 3.25,
                "turn_speed": 95 if role == "transport" else 80 if role == "frigate" else 65,
                "producer": "shipyard", "requires": [] if role != "signature" else [f"{faction}_tech"],
                "weapon": "" if role == "transport" else spec_id,
                "crush": False, "crushable": False, "domain": "naval", "armor_class": "armored",
                "has_turret": role != "transport", "turret_turn_speed": 95,
                "fire_while_moving": role == "frigate",
                "transport_capacity": capacity if role == "transport" else 0,
                "naval_air_draft": 1.35 if role == "transport" else 1.8 if role == "frigate" else 2.25,
                "animations": {state: f"res://assets/cards/{spec_id}_portrait.png" if state == "idle" else f"res://assets/cards/{spec_id}_{state}.svg"
                               for state in ("idle", "move", "attack", "hit", "death")},
                "description": DESCRIPTIONS[faction][("transport", "frigate", "signature").index(role)],
                "voices": {"select": [f"{name}就位。"], "move": ["航线确认，开始前进。"], "attack": ["锁定目标，准备开火。"], "ready": [f"{name}下水。"]},
            }
            units[spec_id] = unit
        for role in ("frigate", "signature"):
            damage, interval, reach, blast, speed, targets = WEAPON_STATS[faction][role]
            spec_id = f"{faction}_ship_{role}"
            weapon = {"damage": damage, "interval": interval, "range": reach,
                      "kind": "shell", "blast": blast, "speed": speed, "targets": targets,
                      "multipliers": {"infantry": 0.45 if role == "frigate" else 0.65,
                                      "building": 0.9 if role == "frigate" else 1.3}}
            if faction == "sky" and role == "signature":
                weapon.update(emp_vehicle_duration=2.0, emp_building_duration=1.0)
            weapons[spec_id] = weapon
        # Heavy ground ordnance can punish ships at the coast, while rifles and
        # scouts remain ineffective. Extend existing target arrays in place.
        for role in ("anti", "tank", "artillery", "advanced", "anti_tower"):
            weapon = weapons.get(f"{faction}_{role}")
            if weapon is not None and "naval" not in weapon["targets"]:
                weapon["targets"].append("naval")
    return catalog


apply_naval = apply


if __name__ == "__main__":
    path = ROOT / "data" / "rules.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    apply(data)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
