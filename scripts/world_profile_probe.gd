extends PaperWorld
## Opt-in diagnostic only; timers are absent from the ordinary world class.
var sections:Dictionary={}
func record(section:String,started:int)->void:
	var row:Dictionary=sections.get(section,{"calls":0,"us":0})
	row.calls+=1;row.us+=Time.get_ticks_usec()-started;sections[section]=row
func profile_sections()->Dictionary:return sections.duplicate(true)
func _entity_in_view(model:Dictionary,e:Dictionary)->bool:
	var stamp:int=Time.get_ticks_usec()
	var result:bool=super._entity_in_view(model,e)
	record("culling",stamp);return result
func _create_entity(e:Dictionary)->Dictionary:
	var stamp:int=Time.get_ticks_usec()
	var result:Dictionary=super._create_entity(e)
	record("create_or_reuse",stamp);return result
func _update_entity(model:Dictionary,e:Dictionary,selected:bool)->void:
	var stamp:int=Time.get_ticks_usec()
	super._update_entity(model,e,selected)
	record("volume_update" if model.volumetric else "paper_update",stamp)
func _reset_model(model:Dictionary,e:Dictionary)->void:
	var stamp:int=Time.get_ticks_usec()
	super._reset_model(model,e);record("reset",stamp)
func _start_death(model:Dictionary)->void:
	var stamp:int=Time.get_ticks_usec()
	super._start_death(model);record("death",stamp)
func _prepare_quality_batches(model:Dictionary)->void:
	var stamp:int=Time.get_ticks_usec()
	super._prepare_quality_batches(model);record("quality_batches",stamp)
