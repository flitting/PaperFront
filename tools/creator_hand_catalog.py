"""Stage 4's Sky creator hand, applied after the ordinary faction catalog.

Keeping the entry in its own final overlay makes rerunning the source catalog
idempotent without changing established faction traits or roster values.
"""


def apply(rules):
    rules["units"]["sky_creator_hand"] = {
        "name": "创世之手", "formal_name": "天翼创世之手",
        "description": "天翼教团唯一的巨型手掌，拥有有别于本阵营常规脆弱装备的两万生命。近距离拍击单位，并一次摧毁任意建筑；每名玩家同一时间只能拥有或生产一只。",
        "faction": "sky", "cost": 15000, "hp": 20000, "speed": 2.2,
        "build_time": 110, "radius": 1.45, "turn_speed": 115,
        "producer": "factory", "requires": ["sky_tech", "sky_command"],
        "weapon": "sky_creator_hand", "crush": False, "crushable": False,
        "art": "creator_hand", "domain": "ground", "armor_class": "armored",
        "max_active": 1, "hero": True, "attack_windup": 0.5,
        "attack_recovery": 0.35,
        "animations": {
            "idle": "res://assets/cards/sky_creator_hand_idle.png",
            "move": "res://assets/cards/sky_creator_hand_idle.png",
            "attack": "res://assets/cards/sky_creator_hand_idle.png",
            "hit": "res://assets/cards/sky_creator_hand_idle.png",
            "death": "res://assets/cards/sky_creator_hand_death.png",
        },
        "portrait": "res://assets/cards/sky_creator_hand_portrait.png",
        "voices": {"select": ["我看见每一张纸的去向。"],
                   "move": ["让想象向前。"],
                   "attack": ["这一页，由我定稿。"],
                   "ready": ["创世之手已完成。"]},
    }
    rules["weapons"]["sky_creator_hand"] = {
        "damage": 900, "interval": 7.0, "range": 6.5,
        "kind": "instant", "blast": 0.0, "speed": 0.0,
        "targets": ["ground", "air", "naval"],
        "multipliers": {}, "execute_building": True,
    }
    return rules
