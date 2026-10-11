extends RefCounted

# Historical test snapshot for outpost travel, scaffolds, engineering commands
# and save restoration. Current Rivet expansion uses the barracks base and is
# covered by rivet_mechanics_tests.gd; these old buildings never enter live rules.
const BUILDINGS = {
  "rivet_hq": {
    "name": "压印总部",
    "faction": "rivet",
    "cost": 2800,
    "hp": 3500,
    "build_time": 60,
    "power": 100,
    "size": 4,
    "requires": [],
    "role": "hq",
    "expands": true,
    "weapon": "",
    "art": "hq",
    "animations": {
      "idle": "res://assets/cards/rivet_hq_portrait.png",
      "death": "res://assets/cards/rivet_hq_death.svg"
    },
    "formal_name": "压印总部",
    "description": "每个势力一场游戏最多拥有一个总部，不能建造额外总部；总部和前线分基地共同维持基地存续。"
  },
  "rivet_barracks": {
    "name": "重锤兵营",
    "faction": "rivet",
    "cost": 500,
    "hp": 1400,
    "build_time": 15,
    "power": -20,
    "size": 3,
    "requires": [
      "rivet_power"
    ],
    "role": "barracks",
    "expands": true,
    "weapon": "",
    "art": "barracks",
    "animations": {
      "idle": "res://assets/cards/rivet_barracks_portrait.png",
      "death": "res://assets/cards/rivet_barracks_death.svg"
    },
    "formal_name": "重锤兵营",
    "description": "训练基础步兵、反装甲兵与工兵；使用独立生产队列。"
  },
  "rivet_outpost": {
    "name": "前线压梁台",
    "faction": "rivet",
    "cost": 1100,
    "hp": 1700,
    "build_time": 60,
    "power": -20,
    "size": 3,
    "requires": [
      "rivet_power"
    ],
    "role": "outpost",
    "expands": true,
    "weapon": "",
    "art": "outpost",
    "animations": {
      "idle": "res://assets/cards/rivet_outpost_portrait.png",
      "death": "res://assets/cards/rivet_outpost_death.svg"
    },
    "formal_name": "前线压梁台",
    "description": "工程兵选址并抵达后搭建低生命脚手架；现场施工逐步付款，受伤先维修、工兵阵亡后可接手或拆除，完工后授权前线建设。"
  }
}

static func adapt(current: Dictionary) -> Dictionary:
	var snapshot: Dictionary = current.duplicate(true)
	snapshot.factions.rivet.erase("building_method")
	# Historical FIFO fixtures recruit individuals. Current whole-squad costs,
	# doorway spawning and refunds are covered by infantry_squad_tests.
	for unit: Dictionary in snapshot.units.values():
		unit.erase("squad_size")
		unit.erase("squad_role")
		unit.erase("squad_build_time")
	for id: String in BUILDINGS:
		snapshot.buildings[id] = BUILDINGS[id].duplicate(true)
	return snapshot
