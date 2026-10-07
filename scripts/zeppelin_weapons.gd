extends RefCounted

## The gondola drops unguided gravity bombs; the dorsal gun has its own aim,
## acquisition and cooldown. Neither weapon borrows the other's ammunition.
const MAP = preload("res://scripts/map_data.gd")
const TRANSPORT = preload("res://scripts/unit_transport.gd")
static var _bomb_mesh: ArrayMesh

static func is_zeppelin(sim, e: Dictionary) -> bool:
	return str(sim.data_for(str(e.spec)).get("art","")) == "zeppelin"

static func secondary(sim, e: Dictionary) -> Dictionary:
	return sim.weapon_for(e,str(sim.data_for(e.spec).get("secondary_weapon","")))

static func can_target(sim, e: Dictionary, target: int, force: bool = false) -> bool:
	if not sim.entities.has(target) or not sim._target_alive(target) or not sim.entity_visible_to(int(e.team),target) or TRANSPORT.is_loaded(e): return false
	var other: Dictionary = sim.entities[target]
	if int(other.team)==int(e.team) and not force and not sim._force_attack_active(e,target): return false
	return sim._target_domain(other) in secondary(sim,e).get("targets",[])

static func engage_air(sim,e: Dictionary,target: int,delta: float,pursue: bool) -> bool:
	if not sim.entities.has(target) or not sim._is_air(sim.entities[target]): return false
	var weapon: Dictionary = secondary(sim,e)
	if weapon.is_empty(): return true
	e.zeppelin_mg_order_target = target
	if (e.pos as Vector2).distance_to(sim._target_position(target)) > float(weapon.range):
		if pursue: sim._pursue_target(e,target,sim._target_position(target),float(weapon.range),delta)
	else: e.state = "attack"
	return true

static func _surface(sim,position: Vector2) -> float:
	return MAP.water_surface_y(sim.map,position) if MAP.terrain_at(sim.map,position)==MAP.WATER else MAP.height_at(sim.map,position)

static func _position(sim,bomb: Dictionary,t: float) -> Vector2:
	var wanted: Vector2 = (bomb.start as Vector2)+(bomb.horizontal_velocity as Vector2)*t
	return wanted.clamp(Vector2(.10,.10),Vector2.ONE*(float(sim.map.size)-.10))

static func launch_bomb(sim,e: Dictionary,weapon_id: String,damage: float,target: int,force: bool) -> void:
	var weapon: Dictionary = sim.rules.weapons[weapon_id]
	var origin: Vector2 = e.pos
	var velocity: Vector2 = Vector2.from_angle(deg_to_rad(float(e.alpha)))*maxf(0,float(e.get("motion",0.0)))
	if float(e.get("air_motion_time",-1.0))==float(sim.time) and e.get("air_motion_from") is Vector2:
		velocity = (origin-(e.air_motion_from as Vector2))/maxf(float(sim._step_delta),.001)
	velocity *= float(weapon.get("inherited_velocity",.20))
	var gravity: float = float(weapon.get("gravity",9.8))
	var release_height: float = sim._source_height(e)+float(sim.data_for(e.spec).get("bomb_release_height",.07))
	var origin_y: float = MAP.height_at(sim.map,origin)+release_height
	var fall: float = sqrt(maxf(.02,2.0*(origin_y-_surface(sim,origin))/gravity))
	var bomb: Dictionary = {"trajectory":"gravity_bomb","pos":origin,"start":origin,"landing":origin,"elapsed":0.0,"duration":fall,"gravity_origin_y":origin_y,"gravity_y":origin_y,"gravity_velocity":0.0,"gravity":gravity,"horizontal_velocity":velocity,"damage":damage,"blast":float(weapon.blast),"team":int(e.team),"source":int(e.id),"spec":str(e.spec),"weapon":weapon_id,"heading":float(e.alpha),"body_heading":float(e.alpha),"targets":weapon.get("targets",["ground","naval"]).duplicate(),"multipliers":weapon.get("multipliers",{}).duplicate(),"target":target,"source_height":release_height,"target_height":0.0,"force":force}
	# Prediction is for UI/serialization only; simulation intersects actual
	# terrain each tick and never changes trajectory to follow a target.
	bomb.landing = _position(sim,bomb,fall)
	sim.projectiles.append(bomb)
	e.zeppelin_bomb_flash = .30
	sim.events.append({"kind":"fire","weapon_slot":"bomb","pos":origin,"landing":bomb.landing,"target":target,"id":int(e.id),"team":int(e.team),"weapon":weapon_id,"spec":str(e.spec),"heading":float(e.alpha),"body_heading":float(e.alpha),"height":release_height,"target_height":0.0,"moving":float(e.motion)>0})

static func step_bomb(sim,bomb: Dictionary,delta: float) -> bool:
	var previous: float = float(bomb.elapsed)
	var next: float = previous+maxf(delta,0)
	var pos: Vector2 = _position(sim,bomb,next)
	var y: float = float(bomb.gravity_origin_y)-.5*float(bomb.gravity)*next*next
	if y <= _surface(sim,pos):
		# Bracket impact for stable results at different tick sizes and slopes.
		var low: float = previous
		var high: float = next
		for i in range(12):
			var middle: float = (low+high)*.5
			var sample: Vector2 = _position(sim,bomb,middle)
			if float(bomb.gravity_origin_y)-.5*float(bomb.gravity)*middle*middle > _surface(sim,sample): low = middle
			else: high = middle
		next = high
		pos = _position(sim,bomb,next)
		y = _surface(sim,pos)
		bomb.elapsed = next; bomb.pos = pos; bomb.landing = pos; bomb.gravity_y = y; bomb.gravity_velocity = -float(bomb.gravity)*next
		return true
	bomb.elapsed = next; bomb.pos = pos; bomb.gravity_y = y; bomb.gravity_velocity = -float(bomb.gravity)*next
	return false

static func step_secondary(sim,delta: float) -> void:
	for e: Dictionary in sim.entities.values():
		if e.kind != "unit" or not is_zeppelin(sim,e): continue
		e.zeppelin_mg_cooldown = maxf(0,float(e.get("zeppelin_mg_cooldown",0))-delta)
		e.zeppelin_mg_flash = maxf(0,float(e.get("zeppelin_mg_flash",0))-delta)
		e.zeppelin_bomb_flash = maxf(0,float(e.get("zeppelin_bomb_flash",0))-delta)
		if float(e.hp)<=0 or not bool(e.get("airborne",true)) or str(e.get("flight_state","")) in ["landed","rearming"] or float(e.get("emp_until",0))>float(sim.time): continue
		var weapon: Dictionary = secondary(sim,e)
		if weapon.is_empty(): continue
		var target: int = -1
		var range_value: float = float(weapon.range)
		# Direct attack orders retain priority. Otherwise hostile aircraft take
		# priority over surface targets, without changing bombing orders.
		var orders: Array = e.get("commands",[])
		if not orders.is_empty() and str(orders[0].kind) in ["attack","force_attack"]:
			var candidate: int = int(orders[0].target)
			if can_target(sim,e,candidate) and sim._is_air(sim.entities[candidate]) and (e.pos as Vector2).distance_to(sim._target_position(candidate))<=range_value: target=candidate
		var best: float = INF
		if target < 0:
			for other: Dictionary in sim._nearby_entities(e.pos,range_value+1.0):
				if int(other.team)==int(e.team) or not can_target(sim,e,int(other.id)): continue
				var distance: float = (e.pos as Vector2).distance_to(other.pos)
				if distance > range_value: continue
				var rank: float = distance+(0.0 if sim._is_air(other) else range_value+1.0)
				if rank < best: best=rank; target=int(other.id)
		e.zeppelin_mg_target = target
		if target < 0: continue
		e.air_idle_time = 0.0
		var target_pos: Vector2 = sim._target_position(target)
		var direction: Vector2 = target_pos-(e.pos as Vector2)
		e.zeppelin_mg_alpha = rad_to_deg(direction.angle())
		var gun_y: float = MAP.height_at(sim.map,e.pos)+sim._source_height(e)+1.33
		var target_y: float = MAP.height_at(sim.map,target_pos)+sim._target_height(target)
		e.zeppelin_mg_pitch = atan2(target_y-gun_y,maxf(.1,direction.length()))
		if float(e.zeppelin_mg_cooldown)>0: continue
		e.zeppelin_mg_cooldown = float(weapon.interval)
		e.zeppelin_mg_flash = .10
		var weapon_id: String = str(sim.data_for(e.spec).secondary_weapon)
		var force: bool = sim._force_attack_active(e,target)
		var damage: float = float(weapon.damage)*load("res://scripts/faction_support.gd").damage_scale(sim,e,target)
		sim._add_damage(target,sim._weapon_damage(damage,target,weapon),force,{"source":int(e.id),"source_team":int(e.team),"weapon":weapon_id,"explosive":false})
		sim.events.append({"kind":"fire","weapon_slot":"secondary","pos":e.pos,"landing":target_pos,"target":target,"id":int(e.id),"team":int(e.team),"weapon":weapon_id,"spec":str(e.spec),"heading":float(e.zeppelin_mg_alpha),"body_heading":float(e.alpha),"height":sim._source_height(e)+1.33,"target_height":sim._target_height(target),"moving":float(e.motion)>0})
		sim.events.append({"kind":"impact","pos":target_pos,"blast":0.0,"team":int(e.team),"source_id":int(e.id),"target":target,"weapon":weapon_id,"spec":str(e.spec),"projectile":false,"height":sim._target_height(target)})

static func bomb_transform(bomb: Dictionary) -> Transform3D:
	var v: Vector2 = bomb.horizontal_velocity
	var yaw: float = -atan2(v.y,v.x) if v.length_squared()>.0001 else 0.0
	var pitch: float = atan2(float(bomb.gravity_velocity),maxf(.001,v.length()))
	return Transform3D(Basis(Vector3.UP,yaw)*Basis(Vector3.BACK,pitch),Vector3(bomb.pos.x,float(bomb.gravity_y),bomb.pos.y))

static func bomb_mesh() -> ArrayMesh:
	if _bomb_mesh != null: return _bomb_mesh
	var mesh = load("res://scripts/volume_models.gd").CraftMesh.new()
	mesh.cylinder(Vector3.ZERO,.11,.37,Vector3.RIGHT,Color("746b54"),10)
	mesh.cylinder(Vector3(.21,0,0),.075,.11,Vector3.RIGHT,Color("c9ad7f"),8)
	mesh.box(Vector3(-.21,0,0),Vector3(.17,.31,.035),Color("c9ad7f"),false)
	mesh.box(Vector3(-.21,0,0),Vector3(.17,.035,.31),Color("c9ad7f"),false)
	_bomb_mesh = mesh.mesh()
	return _bomb_mesh
