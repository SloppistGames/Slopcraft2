class_name SlopBindings
extends RefCounted
const DEFAULTS={"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"jump":KEY_SPACE,"sprint":KEY_SHIFT,"crouch":KEY_CTRL,"fly":KEY_F,"inventory":KEY_E,"world_map":KEY_M,"camera_mode":KEY_F5,"debug_info":KEY_F3,"quick_save":KEY_F6,"console":KEY_SLASH,"pause":KEY_ESCAPE,"slot_1":KEY_1,"slot_2":KEY_2,"slot_3":KEY_3,"slot_4":KEY_4,"slot_5":KEY_5,"slot_6":KEY_6,"slot_7":KEY_7,"slot_8":KEY_8,"slot_9":KEY_9,"mine":-1,"use":-2,"pick_block":-3}
const LABELS={"move_forward":"Move forward","move_back":"Move backward","move_left":"Move left","move_right":"Move right","jump":"Jump / swim up","sprint":"Sprint","crouch":"Crouch / descend","fly":"Creative flight","inventory":"Inventory","world_map":"World map","camera_mode":"Camera perspective","debug_info":"Debug information","quick_save":"Quick save","console":"Command console","pause":"Pause","mine":"Mine / attack","use":"Place / use","pick_block":"Pick block"}
static func ensure_defaults() -> void:
	for action in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			InputMap.action_add_event(action,_event(int(DEFAULTS[action])))
static func apply(bindings: Dictionary) -> void:
	ensure_defaults()
	for action in DEFAULTS:
		var code=int(bindings.get(action,DEFAULTS[action]))
		if code==0: code=int(DEFAULTS[action])
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action,_event(code))
static func _event(code: int) -> InputEvent:
	if code<0:
		var e=InputEventMouseButton.new(); e.button_index=-code; return e
	var e=InputEventKey.new(); e.physical_keycode=code; return e
static func title(action: String) -> String:
	return str(LABELS.get(action,action.replace("_"," ").capitalize()))
static func key_name(action: String,bindings: Dictionary) -> String:
	var code=int(bindings.get(action,DEFAULTS.get(action,0)))
	if code<0: return {1:"Left mouse",2:"Right mouse",3:"Middle mouse",4:"Wheel up",5:"Wheel down"}.get(-code,"Mouse "+str(-code))
	return OS.get_keycode_string(code)
static func assign(action: String,event: InputEvent,bindings: Dictionary) -> String:
	var code=0
	if event is InputEventKey: code=int(event.physical_keycode if event.physical_keycode!=0 else event.keycode)
	elif event is InputEventMouseButton: code=-int(event.button_index)
	if code==0: return "Choose a keyboard key or mouse button."
	for other in DEFAULTS:
		if other!=action and int(bindings.get(other,DEFAULTS[other]))==code: return "Already assigned to "+title(other)+"."
	bindings[action]=code; apply(bindings); return ""
