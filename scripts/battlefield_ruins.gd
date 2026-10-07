extends RefCounted
class_name BattlefieldRuins
static var _visual_models: Script

static func apply_layout(map: Dictionary) -> void:
	# Retire solitary boulder/pillar cells; trees and timber fences stay put.
	for field in ["decorations","foreground_grove","north_context"]:
		var kept: Array = []
		for item in map.get(field,[]):
			if str(item.kind) in ["rock","ruin"]:
				var p:=Vector2(item.pos[0],item.pos[1])
				if int(map.terrain[int(p.y)][int(p.x)])==4:map.terrain[int(p.y)][int(p.x)]=0
			else:kept.append(item)
		if map.has(field):map[field]=kept
	map.ruins=[]
	var centers: Array[Vector2]=[]
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(map.seed)+731915
	# Seeded random, separated same-kind clusters. Mirrored locations retain
	# equal terrain for the two starting sides; no wall/house compound pairing.
	for attempt in range(9600 if int(map.size) >= 640 else 2400):
		var center:=Vector2(rng.randi_range(5,int(map.size)/2-5)+.5,rng.randi_range(5,int(map.size)-6)+.5)
		var mirror:=Vector2(float(map.size)-center.x,center.y)
		var close: bool=false
		for old in centers:
			if old.distance_to(center)<15:close=true;break
		if close or not _safe_compound(map,center) or not _safe_compound(map,mirror):continue
		var kind: String="wall" if rng.randf()<.55 else "house"
		if centers.size()==2:kind="house" if map.ruins[0].kind=="wall" else "wall"
		var turn: int=rng.randi_range(0,3)
		var variant: int=rng.randi_range(0,2)
		var parts: Array=[]
		if kind=="wall":
			parts=[[Vector2(-1.5,-.3),0.0],[Vector2(1.5,-.3),0.0]]
			if variant==1:parts.append([Vector2(1.5,1.55),PI*.5])
		else:
			parts=[[Vector2(-1.65,-1.45),0.0],[Vector2(1.65,1.45),PI]]
		for c in [center,mirror]:
			var group: int=centers.size()
			centers.append(c)
			var yaw: float=turn*PI*.5
			for part in parts:
				var rotation: float=yaw+float(part[1])
				var half:=Vector2(1.5,1.35) if kind=="house" else Vector2(1.5,.34)
				if posmod(roundi(rotation/(PI*.5)),2)==1:half=Vector2(half.y,half.x)
				map.ruins.append({"id":map.ruins.size(),"group":group,"kind":kind,"pos":c+(part[0] as Vector2).rotated(-yaw),"half":half,"yaw":rotation,"hp":900.0 if kind=="house" else 360.0,"max_hp":900.0 if kind=="house" else 360.0,"variant":variant})
		if centers.size()>=(4 if int(map.size)==48 else 240 if int(map.size)>=640 else 60 if int(map.size)>=320 else 20):break
	register_trees(map)

## Keep tree art in its original prop lists, while neutral footprints own its
## collision and health. The static grid has a node under every removable tree.
static func register_trees(map: Dictionary) -> void:
	if not map.has("ruins"): map.ruins = []
	var occupied: Dictionary = {}
	for ruin in map.ruins:
		if ruin.kind == "tree": occupied[Vector2i(floori(ruin.pos.x), floori(ruin.pos.y))] = int(ruin.id)
	for field in ["decorations", "foreground_grove", "north_context"]:
		for item in map.get(field, []):
			if item.get("kind") != "tree": continue
			var pos := Vector2(float(item.pos[0]), float(item.pos[1]))
			var cell := Vector2i(floori(pos.x), floori(pos.y))
			if int(map.terrain[cell.y][cell.x]) == 4: map.terrain[cell.y][cell.x] = 0
			if occupied.has(cell):
				item.ruin_id = occupied[cell]
				continue
			var id: int = map.ruins.size()
			item.ruin_id = id
			occupied[cell] = id
			map.ruins.append({"id": id, "kind": "tree", "pos": pos, "half": Vector2(.48, .48), "cell": cell, "yaw": float(item.get("yaw", 0.0)), "hp": 180.0, "max_hp": 180.0, "variant": int(item.get("variant", posmod(cell.x * 7 + cell.y * 11, 3)))})

static func _safe_compound(map: Dictionary, p: Vector2) -> bool:
	for start in map.starts:
		if p.distance_to(Vector2(start[0],start[1]))<15:return false
	for mine in map.mines:
		if p.distance_to(Vector2(mine.pos[0],mine.pos[1]))<7:return false
	var level: float=float(map.heights[int(p.y)][int(p.x)])
	for z in range(floori(p.y-4),ceili(p.y+4)):
		for x in range(floori(p.x-4),ceili(p.x+4)):
			if x<2 or z<2 or x>=int(map.size)-2 or z>=int(map.size)-2:return false
			if int(map.terrain[z][x])!=0 or absf(float(map.heights[z][x])-level)>.01:return false
	return true

## Visual authoring is loaded only by the landscape renderer. Map generation,
## saves and logic-only runs never initialize mesh resources.
static func meshes(kind: String, variant: int) -> Dictionary:
	if _visual_models == null: _visual_models = load("res://scripts/battlefield_ruin_models.gd")
	return _visual_models.meshes(kind, variant)
