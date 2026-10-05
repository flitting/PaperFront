"""Shared four-faction balance values for catalog generation and merging.

The function accepts a complete rules catalog or an iron/sky expansion delta.
It changes only entries present in that catalog so every authoring route produces
the same gameplay values without replacing art or other faction details.
"""


TRAITS = {
    "kestrel": {"cohesion_radius": 5.0, "cohesion_min_allies": 2, "cohesion_damage_bonus": 0.08},
    "rivet": {"breakthrough_distance": 5.0, "breakthrough_window": 4.0, "breakthrough_damage_bonus": 0.20},
    "iron": {"damage_reduction": 0.10, "regen_delay": 6.0, "regen_fraction_per_second": 0.012},
}

UNIT_STATS = {
    "rivet_rifle": (120, 100), "rivet_tank": (1100, 650),
    "iron_engineer": (165, 65), "iron_rifle": (105, 85), "iron_anti": (215, 82),
    "iron_harvester": (625, 480), "iron_scout": (330, 210),
    "iron_tank": (850, 540), "iron_aa": (660, 360),
    "iron_fighter": (1025, 340), "iron_advanced": (2150, 760),
    "sky_engineer": (195, 55), "sky_rifle": (115, 70),
    "sky_tank": (1150, 450),
    "sky_harvester": (725, 390), "sky_scout": (390, 170),
    "sky_aa": (780, 290),
}

FIGHTER_DAMAGE = {"kestrel": 75, "rivet": 85, "iron": 75, "sky": 80}


def apply_balance(catalog):
    factions = catalog.get("factions", {})
    units = catalog.get("units", {})
    buildings = catalog.get("buildings", {})
    weapons = catalog.get("weapons", {})

    for faction, traits in TRAITS.items():
        if faction in factions:
            factions[faction]["traits"] = traits.copy()

    for name, (cost, hp) in UNIT_STATS.items():
        if name in units:
            units[name].update(cost=cost, hp=hp)

    for faction in ("kestrel", "rivet", "iron", "sky"):
        scout = units.get(f"{faction}_scout")
        if scout is not None:
            scout["transport_capacity"] = 1
        airfield = buildings.get(f"{faction}_airfield")
        if airfield is not None:
            airfield.setdefault("aircraft_repair_rate", 16)
        harvester = units.get(f"{faction}_harvester")
        if harvester is not None:
            harvester.update(speed=3.0, turn_speed=120, radius=0.75)
        refinery = buildings.get(f"{faction}_refinery")
        if refinery is not None:
            refinery["hp"] = 1600
        fighter = units.get(f"{faction}_fighter")
        if fighter is not None:
            fighter["ammo_capacity"] = 8
            fighter["description"] = fighter.get("description", "").replace("六发", "八发")
        fighter_weapon = weapons.get(f"{faction}_fighter")
        if fighter_weapon is not None:
            fighter_weapon["damage"] = FIGHTER_DAMAGE[faction]
        tank_weapon = weapons.get(f"{faction}_tank")
        if tank_weapon is not None:
            tank_weapon.setdefault("multipliers", {})["infantry"] = 0.30

    if "sky_tank" in weapons:
        weapons["sky_tank"]["damage"] = 75
    if "sky_disruptor" in weapons:
        weapons["sky_disruptor"].update(emp_vehicle_duration=2.0, emp_building_duration=1.0)
    if "sky_disruptor" in units:
        units["sky_disruptor"]["description"] = units["sky_disruptor"]["description"].replace(
            "不附加失控或断电效果", "命中装甲单位或建筑时短暂干扰其行动"
        )
    for spec in units.values():
        description = spec.get("description", "")
        if "普通步兵" in description:
            spec["description"] = description.replace("普通步兵", "地面步兵（含工兵和反甲兵）")
        if spec.get("art") == "air_transport":
            visual = spec.get("description", "").split("；", 1)[0]
            spec["description"] = visual + "；可在任意合法空地降落并装卸4名地面步兵（含工兵和反甲兵）；机场负责维修与弹药补给，机位有限。"
