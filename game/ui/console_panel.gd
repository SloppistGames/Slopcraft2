class_name ConsolePanel
extends PanelContainer
## Local, bounded developer commands. No evaluation of arbitrary GDScript.
signal closed
var game: Node
var input: LineEdit
var output: RichTextLabel
var history: Array[String] = []
var history_index = 0
const COMMANDS = ["help","gamemode","give","tp","time","weather","biome","summon","kill","seed","setblock","fill","effect","locate","renderdistance"]
func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left=20; offset_right=-20; offset_top=-330; offset_bottom=-20
	theme=SlopSkin.theme()
	var box=VBoxContainer.new(); add_child(box)
	box.add_child(SlopSkin.label("COMMAND CONSOLE  /  Tab completes  /  Up & Down recall  /  Esc closes",12,SlopSkin.ACCENT))
	output=RichTextLabel.new(); output.custom_minimum_size.y=215; output.scroll_following=true; output.selection_enabled=true; box.add_child(output)
	input=LineEdit.new(); input.placeholder_text="/help"; input.custom_minimum_size.y=40; box.add_child(input)
	input.text_submitted.connect(_submit)
	visible=false
func open() -> void:
	visible=true; game.set_menu_active(true)
	input.text="/"; input.grab_focus(); input.caret_column=1
func close() -> void:
	visible=false; game.set_menu_active(false); closed.emit()
func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_ESCAPE: close()
		KEY_UP:
			history_index=maxi(0,history_index-1)
			if not history.is_empty(): input.text=history[history_index]; input.caret_column=input.text.length()
		KEY_DOWN:
			history_index=mini(history.size(),history_index+1)
			input.text=history[history_index] if history_index<history.size() else "/"
			input.caret_column=input.text.length()
		KEY_TAB:
			var prefix=input.text.trim_prefix("/").to_lower()
			var matches: Array[String]=[]
			for command in COMMANDS:
				if command.begins_with(prefix): matches.append(command)
			if matches.size()==1: input.text="/"+matches[0]+" "; input.caret_column=input.text.length()
			elif not matches.is_empty(): _write("  ".join(matches))
		_: return
	get_viewport().set_input_as_handled()
func _write(message: String) -> void:
	output.add_text(message+"\n")
	if output.get_line_count()>250:
		output.clear()
		output.add_text(message+"\n")
func _submit(line: String) -> void:
	var command=line.strip_edges()
	if command.is_empty(): return
	history.append(command); if history.size()>100: history.pop_front()
	history_index=history.size()
	_write("> "+command)
	_write(execute(command))
	input.text="/"; input.caret_column=1
func execute(line: String) -> String:
	var args=line.strip_edges().trim_prefix("/").split(" ",false)
	if args.is_empty(): return "Enter /help for commands."
	var command=args[0].to_lower(); args.remove_at(0)
	if not command in COMMANDS: return "Unknown command. Use /help."
	if command == "help": return "Commands: /"+"  /".join(COMMANDS)+"\nCoordinates are absolute. Block/item names use underscores. Creative mode enables cheats."
	if not is_instance_valid(game.player): return "Enter a world first."
	if command == "seed": return "Seed: "+str(game.world.world_seed)
	if command == "biome": return "%s / %s" % [game.world.biome_at(game.player.position),game.world.cave_biome_at(game.player.position)]
	if not game.inventory.creative and not bool(game.current_data.get("cheats_enabled",false)):
		return "Cheats are disabled for this survival world."
	match command:
		"gamemode":
			if args.size()!=1 or not args[0] in ["survival","creative"]: return "Usage: /gamemode survival|creative"
			game.inventory.creative=args[0]=="creative"; game.current_data.mode=args[0]
			game.player.flying=false; game.inventory.changed.emit()
			return "Game mode: "+args[0]
		"give":
			if args.size()<1 or args.size()>2: return "Usage: /give item_name [count]"
			var id=_item_id(args[0]); var amount=1
			if id<=0: return "Unknown item."
			if args.size()==2:
				if not args[1].is_valid_int(): return "Count must be an integer."
				amount=int(args[1])
			if amount<1 or amount>2304: return "Count must be between 1 and 2304."
			return "Added %d %s." % [amount,BlockDB.item_name(id)] if game.inventory.add_item(id,amount) else "Not enough inventory space."
		"tp":
			if args.size()!=3 or not _numbers(args): return "Usage: /tp x y z"
			var pos=Vector3(float(args[0]),float(args[1]),float(args[2]))
			if not _valid_position(pos): return "Position outside the supported world."
			game.world.ensure_ready_at(pos); game.player.position=pos; game.player.velocity=Vector3.ZERO
			return "Teleported to "+str(pos)
		"time":
			if args.size()!=1 or not is_instance_valid(game.weather): return "Usage: /time day|night|dawn|dusk|0..1"
			var times={"day":0.3,"night":0.8,"dawn":0.0,"dusk":0.55}
			if not times.has(args[0]) and not args[0].is_valid_float(): return "Use day, night, dawn, dusk or a number between 0 and 1."
			var value=float(times.get(args[0],args[0]))
			if not is_finite(value) or value<0 or value>1: return "Time must be between 0 and 1."
			game.weather.set_time(value); return "Time updated."
		"weather":
			if args.size()!=1 or not is_instance_valid(game.weather): return "Usage: /weather clear|cloudy|light_rain|moderate_rain|heavy_rain|thunderstorm|light_snow|heavy_snow|blizzard|windstorm|hurricane"
			return "Weather: "+args[0] if game.weather.set_weather(args[0]) else "Unknown weather type."
		"summon":
			if args.size()!=1 or not args[0] in ["pig","sheep","slime"]: return "Usage: /summon pig|sheep|slime"
			if game.entities.actors.size()>=80: return "Entity limit reached."
			game.entities._spawn_actor(args[0],game.player.position+Vector3(2,1,0)); return "Summoned "+args[0]
		"kill":
			if not args.is_empty() and args[0]!="self": return "Usage: /kill [self]"
			game.player.health=0; game.player.died.emit(); close(); return "You died."
		"setblock","fill":
			return _blocks(command,args)
		"effect":
			if args.size()!=1 or args[0]!="heal": return "Usage: /effect heal"
			game.player.health=20; game.player.hunger=20; return "Health and hunger restored."
		"locate":
			if args.size()!=1: return "Usage: /locate village|stronghold|temple|mineshaft|ruins|camp|cabin"
			if game.world.structure_provider==null: return "Structure locations are available in new snapshot Overworlds."
			var pos=game.world.structure_provider.locate(args[0],game.player.position)
			return "Nearest %s: %s" % [args[0],str(pos)] if pos is Vector3 and pos.is_finite() else "No matching structure found."
		"renderdistance":
			if args.size()!=1 or not args[0].is_valid_int(): return "Usage: /renderdistance 2..32"
			var distance=int(args[0])
			if distance<2 or distance>32: return "Distance must be 2..32 chunks."
			game.settings.view_distance=distance; game.world.set_render_distance(distance); return "Landscape distance: %d chunks." % distance
	return "No command executed."
func _blocks(command: String,args: PackedStringArray) -> String:
	var required=4 if command=="setblock" else 7
	if args.size()!=required: return "Usage: /setblock x y z block | /fill x1 y1 z1 x2 y2 z2 block"
	var coordinates=args.slice(0,required-1)
	if not _numbers(coordinates): return "Coordinates must be finite numbers."
	var first=Vector3i(int(float(args[0])),int(float(args[1])),int(float(args[2])))
	var last=first if command=="setblock" else Vector3i(int(float(args[3])),int(float(args[4])),int(float(args[5])))
	if not _valid_position(Vector3(first)) or not _valid_position(Vector3(last)): return "Position outside the supported world."
	var id=_item_id(args[required-1])
	if id<0 or not BlockDB.is_block(id): return "Unknown block."
	var lo=first.min(last); var hi=first.max(last)
	var span=hi-lo+Vector3i.ONE
	if span.x>4096 or span.y>4096 or span.z>4096: return "Fill is limited to 4096 blocks per command."
	var volume=span.x*span.y*span.z
	if volume>4096: return "Fill is limited to 4096 blocks per command."
	if id>0 and AABB(Vector3(lo),Vector3(hi-lo+Vector3i.ONE)).intersects(AABB(game.player.position-Vector3(.35,0,.35),Vector3(.7,1.8,.7))): return "This would trap the player inside blocks."
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1): game.world.set_block(Vector3i(x,y,z),id)
	return "Updated %d blocks." % volume
func _numbers(args: PackedStringArray) -> bool:
	for arg in args:
		if not arg.is_valid_float() or not is_finite(float(arg)): return false
	return true
func _valid_position(p: Vector3) -> bool:
	return p.is_finite() and absf(p.x)<=30000000 and absf(p.z)<=30000000 and p.y>=game.world.min_y() and p.y<game.world.max_y()
func _item_id(value: String) -> int:
	if value.is_valid_int(): return int(value) if BlockDB.valid_item(int(value)) or int(value)==0 else -1
	if value.to_lower()=="air": return 0
	for item in BlockDB.all_items():
		if str(item.get("name","")).to_lower().replace(" ","_")==value.to_lower(): return int(item.id)
	return -1
