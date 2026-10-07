extends SceneTree
var failures:Array[String]=[]
var checks:=0
func _initialize():
 var rules:Dictionary=RulesLoader.load_rules()
 for mode in ["forest","desert","snow","city","random_city","islands"]:
  var map:Dictionary=MapData.generate(mode,73026,{"players":4})
  for team in range(map.starts.size()):
   var start:Vector2=Vector2(float(map.starts[team][0]),float(map.starts[team][1])) if map.starts[team] is Array else map.starts[team]
   var center:Vector2=Vector2(roundf(start.x-4)+4,roundf(start.y-4)+4)
   var level:float=MapData.height_at(map,center)
   var ok:=true
   for z in range(int(center.y-4),int(center.y+4)):
    for x in range(int(center.x-4),int(center.x+4)):
     var point:=Vector2(x+.5,z+.5)
     ok=ok and x>=0 and z>=0 and x<int(map.size) and z<int(map.size) and MapData.terrain_at(map,point) not in [1,2,4] and absf(MapData.height_at(map,point)-level)<.05
   checks+=1
   if not ok:failures.append(mode+" owner"+str(team)+" enlarged HQ overlaps invalid terrain")
 print("RTS_START_FOOTPRINT ",JSON.stringify({"checks":checks,"failures":failures}))
 for failure in failures:push_error(failure)
 quit(0 if failures.is_empty() else 1)
