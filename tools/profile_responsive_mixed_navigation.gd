extends "res://tools/profile_responsive_navigation.gd"

# Same short-window metrics, with actual full-size infantry and vehicles.
# Use --units=96 --case=all (rail case remains the inherited train control).
func ground_case(config: Dictionary, opts: Dictionary, gate: bool) -> Dictionary:
 var sim = fixture(config, opts)
 var size: int = int(sim.map.size)
 if gate:
  for z: int in range(size):
   if z >= size / 2 - 4 and z < size / 2 + 4: continue
   for x: int in [size / 2 - 1, size / 2]: sim.map.terrain[z][x] = 4
 finish_geometry(sim)
 var ids: Array[int] = []
 var columns: int = 12
 var count_rows: int = ceili(float(opts.units) / columns)
 var first_z: float = float(size) * .5 - float(count_rows - 1) * 2.2 * .5
 for index: int in range(int(opts.units)):
  var point := Vector2(float(size / 2) - 2.1 - float(columns - 1 - index % columns) * 2.2, first_z + float(index / columns) * 2.2)
  var spec: String = "iron_tank" if index % 2 else "iron_rifle"
  ids.append(quiet_unit(sim,spec,point))
 sim._rebuild_spatial()
 return measure(sim,ids,Vector2(float(size)*.75,float(size)*.5),"mixed_gate" if gate else "mixed_open",opts)
