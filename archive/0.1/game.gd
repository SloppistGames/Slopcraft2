extends Node

const VERSION = "0.1 • THE THREE REALMS"
var world: VoxelWorld
var player: VoxelPlayer
var inventory: PlayerInventory
var entities: SlopEntities
var hud: SlopHUD
var canvas: CanvasLayer
var menu: Control
var menu_camera: Camera3D
var current_data: Dictionary = {}
var settings: Dictionary = {"fov":78.0,"sensitivity":0.0025,"volume":0.55,"fullscreen":false,"view_distance":3}
var selected_world = ""
var page = "title"
var splash: Label
var menu_clock = 0.0
var autosave_clock = 0.0
var world_clock = 0.0
var message_label: Label
var inventory_tab = "Backpack"
var palette_filter = ""
var selected_slot = -1
var loading = false
var audio: Node

func _ready() -> void:
	get_tree().auto_accept_quit = false
	_load_settings()
	canvas = CanvasLayer.new()
	add_child(canvas)
	_build_audio()
	_show_loading("SHAPING A WORLD", "Planting trees. Placing possibilities.")
	await get_tree().process_frame
	await get_tree().process_frame
	_build_preview()
	_show_title()
	if "--smoke-game" in OS.get_cmdline_user_args():
		SaveManager.worlds_directory="user://test-smoke-worlds"
		var d = SaveManager.create_world("Automated smoke world",12345,"creative")
		await _start_world(d)
		await get_tree().create_timer(3).timeout
		_checkpoint()
		DirAccess.remove_absolute(SaveManager._path(str(d.id)))
		DirAccess.remove_absolute(SaveManager._path(str(d.id))+".bak")
		print("GAME_SMOKE_OK")
		get_tree().quit()
	if "--capture-title" in OS.get_cmdline_user_args():
		await get_tree().create_timer(8).timeout
		get_viewport().get_texture().get_image().save_png("user://title-preview.png")
		print("TITLE_CAPTURE="+ProjectSettings.globalize_path("user://title-preview.png"))
		get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _checkpoint():
			_show_pause()
			_notify("Could not save. Keep the game open and export a backup.")
			return
		get_tree().quit()

func _process(delta: float) -> void:
	menu_clock += delta
	if is_instance_valid(splash):
		splash.scale = Vector2.ONE * (1.0+sin(menu_clock*5.0)*.035)
		splash.modulate.a = .87+.13*sin(menu_clock*4)
	if is_instance_valid(menu_camera) and not is_instance_valid(player):
		menu_camera.position = Vector3(34+sin(menu_clock*.025)*12,43,52+cos(menu_clock*.025)*8)
		menu_camera.look_at(Vector3(4,19,2))
	if is_instance_valid(player) and not loading:
		world.update_focus(player.position)
		if page == "game":
			world_clock += delta
			autosave_clock += delta
			if autosave_clock > 45:
				autosave_clock = 0
				_checkpoint()

func _unhandled_input(event: InputEvent) -> void:
	if loading: return
	if is_instance_valid(player) and player.health<=0: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if is_instance_valid(player):
				if page == "game": _show_pause()
				elif page == "pause" or page == "inventory": _resume()
				else: _show_pause()
			elif page != "title": _show_title()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_E and is_instance_valid(player):
			if page == "game": _show_inventory()
			elif page == "inventory": _resume()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F3 and is_instance_valid(hud): hud.debug_visible = not hud.debug_visible
		elif event.physical_keycode == KEY_F5 and is_instance_valid(player):
			_checkpoint()
			_notify("World saved.")

func _build_preview() -> void:
	world = VoxelWorld.new()
	add_child(world)
	world.setup(842019,"overworld",{})
	world.prepare_panorama(Vector3(8,0,8),3)
	menu_camera = Camera3D.new()
	world.add_child(menu_camera)
	menu_camera.position = Vector3(34,43,64)
	menu_camera.look_at(Vector3(4,19,2))
	menu_camera.fov = 72
	menu_camera.current = true

func _clear_menu(dim: float = .64) -> void:
	if is_instance_valid(menu):
		canvas.remove_child(menu)
		menu.queue_free()
	splash = null
	message_label = null
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.theme = SlopSkin.theme()
	canvas.add_child(menu)
	var bg = ColorRect.new()
	bg.color = Color(.025,.04,.025,dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(player): player.active = false
	if is_instance_valid(entities): entities.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(hud): hud.visible = false

func _panel(title: String, subtitle: String, width: float = 780) -> VBoxContainer:
	_clear_menu()
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = width
	center.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	panel.add_child(column)
	var head = HBoxContainer.new()
	column.add_child(head)
	var l = SlopSkin.label(title,27)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	head.add_child(SlopSkin.label("SC / 2",16,SlopSkin.ACCENT))
	if subtitle != "": column.add_child(SlopSkin.label(subtitle,12,SlopSkin.MUTED))
	var sep = HSeparator.new()
	column.add_child(sep)
	message_label = SlopSkin.label("",12,SlopSkin.ACCENT)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return column

func _footer(column: VBoxContainer) -> void:
	column.add_child(message_label)

func _show_loading(title: String, subtitle: String) -> void:
	_clear_menu(.94)
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(cc)
	var vb = VBoxContainer.new()
	cc.add_child(vb)
	var label = SlopSkin.label(title,28,SlopSkin.ACCENT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(label)
	var sub = SlopSkin.label(subtitle,14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

func _show_title() -> void:
	page = "title"
	_clear_menu(.23)
	var vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ vec2 p=UV-vec2(.5); float a=clamp(length(p)*.85+UV.y*.15,0.,.72); COLOR=vec4(.015,.025,.018,a); }"
	var mat = ShaderMaterial.new()
	mat.shader = shader
	vignette.material = mat
	menu.add_child(vignette)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = 680
	column.add_theme_constant_override("separation",8)
	center.add_child(column)
	var brand = Control.new()
	brand.custom_minimum_size = Vector2(680,305)
	column.add_child(brand)
	var logo = TextureRect.new()
	logo.texture = preload("res://assets/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(-40,-60)
	logo.size = Vector2(760,428)
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	brand.add_child(logo)
	splash = SlopSkin.label("NOW WITH 200% MORE SLOP!",20,Color("ffe84d"))
	splash.position = Vector2(360,245)
	splash.rotation = deg_to_rad(-13)
	brand.add_child(splash)
	var buttons = VBoxContainer.new()
	buttons.custom_minimum_size.x = 490
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_theme_constant_override("separation",9)
	column.add_child(buttons)
	buttons.add_child(SlopSkin.button("Singleplayer",_show_worlds,490))
	buttons.add_child(SlopSkin.button("How to play",_show_guide))
	var row = HBoxContainer.new()
	buttons.add_child(row)
	var settings_b = SlopSkin.button("Options...",func(): _show_options("title"))
	settings_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(settings_b)
	var quit = SlopSkin.button("Quit game",func(): get_tree().quit())
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(quit)
	var tagline = SlopSkin.label("BUILD SOMETHING WORTH GETTING LOST IN.",11,SlopSkin.MUTED)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.custom_minimum_size.y = 40
	buttons.add_child(tagline)
	var version = SlopSkin.label("SLOPCRAFT 2  /  "+VERSION,11)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left=22
	version.offset_top=-30
	version.offset_right=620
	version.offset_bottom=-8
	menu.add_child(version)
	var note = SlopSkin.label("A LITTLE BLOCK. A BIG ADVENTURE.",11,SlopSkin.MUTED)
	note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	note.offset_left=-364
	note.offset_top=-30
	note.offset_right=-22
	note.offset_bottom=-8
	menu.add_child(note)

func _show_worlds() -> void:
	page = "worlds"
	var worlds = SaveManager.list_worlds()
	if selected_world == "" and not worlds.is_empty(): selected_world = str(worlds[0].get("id",""))
	var col = _panel("YOUR WORLDS","Pick up where you left off. Every block remembered.")
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740,300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if worlds.is_empty():
		var empty = SlopSkin.label("A fresh horizon awaits.\n\nCreate your first world to begin.",19,SlopSkin.MUTED)
		empty.custom_minimum_size.y = 220
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(empty)
	for data in worlds:
		var id = str(data.get("id",""))
		var prefix = "> " if id==selected_world else "  "
		var b = SlopSkin.button(prefix+str(data.get("name","World"))+"\n  "+str(data.get("mode","survival")).to_upper()+"  /  "+str(data.get("dimension","overworld")).to_upper()+"  /  SEED "+str(data.get("seed",0)),func(): selected_world=id; _show_worlds())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 78
		b.add_theme_font_size_override("font_size",14)
		if id==selected_world: b.add_theme_stylebox_override("normal",SlopSkin.stone(Color("5c7051"),true))
		list.add_child(b)
	var actions = HBoxContainer.new()
	col.add_child(actions)
	var play = SlopSkin.button("Play selected",func(): _start_world(SaveManager.load_world(selected_world)))
	play.disabled = worlds.is_empty()
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(play)
	var create = SlopSkin.button("Create new world",_show_create)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(create)
	var secondary = HBoxContainer.new()
	col.add_child(secondary)
	for entry in [["Import world",_import_dialog],["Export backup",func(): _export_dialog(selected_world)],["Back",_show_title]]:
		var b = SlopSkin.button(entry[0],entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry[0]=="Export backup": b.disabled = worlds.is_empty()
		secondary.add_child(b)
	_footer(col)

func _show_create() -> void:
	page = "create"
	var col = _panel("A NEW BEGINNING","A seed makes a world. What you do with it is up to you.",660)
	col.add_child(SlopSkin.label("WORLD NAME",13,SlopSkin.MUTED))
	var name_input = LineEdit.new()
	name_input.text = "My Slopworld"
	name_input.max_length = 48
	name_input.custom_minimum_size.y = 46
	col.add_child(name_input)
	col.add_child(SlopSkin.label("SEED  /  LEAVE BLANK FOR A SURPRISE",13,SlopSkin.MUTED))
	var seed_input = LineEdit.new()
	seed_input.placeholder_text = "A number, a word, a possibility..."
	seed_input.custom_minimum_size.y = 46
	col.add_child(seed_input)
	var mode = {"value":"survival"}
	var mode_b = Button.new()
	mode_b.custom_minimum_size.y = 52
	mode_b.text = "Game mode: SURVIVAL"
	col.add_child(mode_b)
	var desc = SlopSkin.label("Gather, craft, eat, explore. Face the Enderslop.",13,SlopSkin.MUTED)
	col.add_child(desc)
	mode_b.pressed.connect(func():
		mode.value = "creative" if mode.value=="survival" else "survival"
		mode_b.text = "Game mode: "+str(mode.value).to_upper()
		desc.text = "Every block at your fingertips. Fly and build freely." if mode.value=="creative" else "Gather, craft, eat, explore. Face the Enderslop."
	)
	col.add_child(SlopSkin.button("Create world",func():
		var seed_text = seed_input.text.strip_edges()
		var world_seed = int(seed_text) if seed_text.is_valid_int() else int(seed_text.hash())
		if seed_text=="": world_seed = randi()%2147483647
		var title = name_input.text.strip_edges()
		if title=="": title="My Slopworld"
		var data = SaveManager.create_world(title,world_seed,mode.value)
		if data.is_empty(): _notify("Couldn't create the world. Check free disk space.")
		else: _start_world(data)
	))
	col.add_child(SlopSkin.button("Back",_show_worlds))
	_footer(col)
	name_input.grab_focus()

func _start_world(data: Dictionary) -> void:
	if data.is_empty():
		_notify("The world could not be loaded. Your backup may be recoverable.")
		return
	loading = true
	page = "loading"
	_show_loading("ENTERING "+str(data.get("name","WORLD")).to_upper(),"Building chunks. Packing your inventory.")
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	if is_instance_valid(hud): hud.queue_free()
	current_data = data
	inventory = PlayerInventory.new()
	inventory.setup(data.get("mode","survival")=="creative")
	if not data.get("inventory",{}).is_empty(): inventory.restore(data.inventory)
	var dim = str(data.get("dimension","overworld"))
	world = VoxelWorld.new()
	add_child(world)
	world.setup(int(data.get("seed",842019)),dim,data.get("dimensions",{}).get(dim,{}).get("edits",{}))
	player = VoxelPlayer.new()
	world.add_child(player)
	player.setup(world,inventory)
	player.position = world.spawn_position()
	if not data.get("player",{}).is_empty(): player.restore(data.player)
	world.ensure_ready_at(player.position)
	await get_tree().physics_frame
	player.camera.fov = float(settings.fov)
	_apply_player_settings()
	player.notify.connect(_notify)
	player.portal_requested.connect(_travel)
	player.died.connect(_show_death)
	player.interact_requested.connect(_interact_block)
	player.can_break_block = _can_break
	entities = SlopEntities.new()
	world.add_child(entities)
	entities.setup(world,player,dim)
	player.entities = entities
	var ed = data.get("dimensions",{}).get(dim,{}).get("entities",{})
	if not ed.is_empty(): entities.restore(ed)
	entities.boss_defeated.connect(_boss_won)
	hud = SlopHUD.new()
	hud.player = player
	hud.inventory = inventory
	hud.entities = entities
	hud.world_name = data.get("name","World")
	hud.dimension = dim
	canvas.add_child(hud)
	loading = false
	autosave_clock = 0
	world_clock = float(data.get("play_time",0))
	_resume()
	_notify("Welcome home. E opens your inventory and field guide.")

func _resume() -> void:
	if not is_instance_valid(player): return
	if player.health<=0:
		_show_death()
		return
	page = "game"
	if is_instance_valid(menu):
		menu.queue_free()
		menu = null
	player.active = true
	entities.process_mode = Node.PROCESS_MODE_INHERIT
	hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _checkpoint() -> bool:
	if current_data.is_empty() or not is_instance_valid(player): return true
	var dim = str(current_data.get("dimension","overworld"))
	if not current_data.has("dimensions"): current_data.dimensions = {}
	current_data.dimensions[dim] = {"edits":world.get_edits(),"entities":entities.serialize(),"position":player.serialize()}
	current_data.player = player.serialize()
	current_data.inventory = inventory.serialize()
	current_data.play_time = world_clock
	var error = SaveManager.save_world(current_data)
	if error != OK:
		_notify("SAVE FAILED. Export a backup and check your disk.")
		return false
	return true

func _show_pause() -> void:
	page = "pause"
	var col = _panel("GAME MENU",str(current_data.get("name","World"))+"  /  "+str(current_data.get("dimension","overworld")).to_upper(),570)
	col.add_child(SlopSkin.button("Back to game",_resume))
	col.add_child(SlopSkin.button("Inventory & crafting",_show_inventory))
	var row = HBoxContainer.new()
	col.add_child(row)
	for e in [["Field guide",_show_guide],["Options...",func(): _show_options("pause")]]:
		var b = SlopSkin.button(e[0],e[1]); b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(b)
	col.add_child(SlopSkin.button("Export world backup",func():
		if _checkpoint(): _export_dialog(str(current_data.id))
	))
	col.add_child(SlopSkin.button("Save and quit to title",_quit_to_title))
	_footer(col)
	message_label.text = "Autosaves every 45 seconds. F5 saves anytime."

func _quit_to_title() -> void:
	if not _checkpoint(): return
	loading = true
	_show_loading("SAVING YOUR ADVENTURE","See you on the other side of the next block.")
	await get_tree().process_frame
	if is_instance_valid(hud): hud.queue_free()
	if is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	player = null
	entities = null
	current_data = {}
	_build_preview()
	loading = false
	_show_title()

func _travel(dim: String) -> void:
	if loading or not ["overworld","nether","end"].has(dim): return
	if dim==str(current_data.get("dimension","overworld")): return
	if not _checkpoint(): return
	var data = current_data.duplicate(true)
	data.dimension = dim
	var state = data.dimensions.get(dim,{})
	data.player = state.get("position",{}).duplicate(true)
	data.player.health = player.health
	data.player.hunger = player.hunger
	await _start_world(data)
	_checkpoint()
	_notify("THE "+dim.to_upper()+"  /  A new horizon.")

func _show_death() -> void:
	page = "death"
	var col = _panel("YOU BECAME THE SLOP","Your inventory is safe. Take a breath, then try again.",620)
	col.add_child(SlopSkin.button("Respawn",func():
		player.respawn()
		_resume()
		_checkpoint()
	))
	col.add_child(SlopSkin.button("Save and quit",_quit_to_title))
	_footer(col)

func _boss_won() -> void:
	current_data.boss_defeated=true
	_notify("ENDERSLOP DEFEATED! The void is yours.")
	_checkpoint()

func _show_inventory() -> void:
	page = "inventory"
	var col = _panel("INVENTORY",("CREATIVE" if inventory.creative else "SURVIVAL")+"  /  "+"E to return. Select a slot, then another to swap.",900)
	var tabs = HBoxContainer.new()
	col.add_child(tabs)
	var names = ["Backpack","Crafting","Field guide"]
	if inventory.creative: names.insert(1,"All items")
	for name in names:
		var b = SlopSkin.button(name,func(): inventory_tab=name; selected_slot=-1; _show_inventory())
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if name==inventory_tab: b.add_theme_stylebox_override("normal",SlopSkin.stone(Color("61784f"),true))
		tabs.add_child(b)
	var area = ScrollContainer.new()
	area.custom_minimum_size = Vector2(850,340)
	area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(area)
	var contents = VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(contents)
	match inventory_tab:
		"Backpack": _inventory_slots(contents)
		"All items": _creative_items(contents)
		"Crafting": _crafting(contents)
		_: _field_guide(contents)
	var footer = HBoxContainer.new()
	col.add_child(footer)
	var done = SlopSkin.button("Back to game",_resume); done.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(done)
	if inventory.creative:
		footer.add_child(SlopSkin.button("Travel...",_show_travel,210))
	_footer(col)

func _inventory_slots(parent: VBoxContainer) -> void:
	parent.add_child(SlopSkin.label("HOTBAR",13,SlopSkin.MUTED))
	var grid = GridContainer.new()
	grid.columns = 9
	parent.add_child(grid)
	for i in inventory.slots.size():
		var slot = inventory.slots[i]
		var b = Button.new()
		b.custom_minimum_size = Vector2(85,68)
		b.tooltip_text = BlockDB.item_name(int(slot.get("id",0)))
		SlopSkin.style_slot(b,i==selected_slot)
		b.pressed.connect(func():
			if selected_slot<0:
				selected_slot=i
				if i<9: inventory.selected=i
			else:
				var temp = inventory.slots[i]
				inventory.slots[i]=inventory.slots[selected_slot]
				inventory.slots[selected_slot]=temp
				inventory.changed.emit()
				selected_slot=-1
			_show_inventory()
		)
		grid.add_child(b)
		var icon = ItemIcon.new()
		icon.item_id=int(slot.get("id",0)); icon.amount=int(slot.get("count",0))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(icon)
	parent.add_child(SlopSkin.label("Top row = keys 1-9. Right-click with food equipped to eat.",12,SlopSkin.MUTED))

func _creative_items(parent: VBoxContainer) -> void:
	var search = LineEdit.new()
	search.placeholder_text="Search blocks, tools and supplies..."
	search.text=palette_filter
	parent.add_child(search)
	var grid = GridContainer.new()
	grid.columns=9
	parent.add_child(grid)
	var populate = func(query: String):
		for c in grid.get_children(): grid.remove_child(c); c.queue_free()
		for entry in BlockDB.all_items():
			var id = int(entry.get("id",0)) if entry is Dictionary else int(entry)
			if id==0 or (query!="" and not query.to_lower() in BlockDB.item_name(id).to_lower()): continue
			var b = Button.new()
			b.custom_minimum_size=Vector2(85,68)
			b.tooltip_text=BlockDB.item_name(id)+" — equip to selected hotbar slot"
			SlopSkin.style_slot(b)
			b.pressed.connect(func():
				inventory.select_item(id)
				_notify(BlockDB.item_name(id)+" equipped to slot "+str(inventory.selected+1))
			)
			grid.add_child(b)
			var icon = ItemIcon.new(); icon.item_id=id; icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); b.add_child(icon)
	populate.call(palette_filter)
	search.text_changed.connect(func(q): palette_filter=q; populate.call(q))

func _crafting(parent: VBoxContainer) -> void:
	parent.add_child(SlopSkin.label("Recipe book  /  Materials are taken from your backpack.",12,SlopSkin.MUTED))
	for recipe in inventory.recipes():
		var row = HBoxContainer.new()
		parent.add_child(row)
		var icon = ItemIcon.new(); icon.item_id=int(recipe.result); icon.custom_minimum_size=Vector2(48,48); row.add_child(icon)
		var info = VBoxContainer.new(); info.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(info)
		info.add_child(SlopSkin.label(str(recipe.get("name",BlockDB.item_name(int(recipe.result)))),15))
		var ingredients = []
		for key in recipe.ingredients:
			var id=int(key)
			ingredients.append(str(recipe.ingredients[key])+" "+BlockDB.item_name(id))
		var needed=SlopSkin.label(", ".join(ingredients),10,SlopSkin.MUTED)
		needed.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		info.add_child(needed)
		var b=SlopSkin.button("Craft",func():
			if inventory.craft(recipe): _show_inventory(); _notify("Crafted "+BlockDB.item_name(int(recipe.result)))
			else: _notify("Not enough materials or inventory space.")
		,100)
		b.disabled=not inventory.can_craft(recipe)
		row.add_child(b)

func _field_guide(parent: VBoxContainer) -> void:
	var text = "01  MAKE YOUR MARK\nHold left mouse to mine. Right mouse places your selected block.\nUse number keys or the wheel to choose a hotbar slot.\n\n02  FROM WOOD TO DIAMOND\nGather logs, craft planks and sticks, then tools in the Crafting tab.\nBetter pickaxes mine faster. Recipes include smelting with fuel.\n\n03  THREE REALMS\nAt spawn, find the violet Nether gate and the cyan End gate.\nWalk into a gate to travel. Each realm remembers your changes.\nReturn gates await at the arrival points.\n\n04  THE ENDERSLOP\nIn the End, aim your bow at the flying boss and hold left mouse.\nIt swoops, fires void bolts, and becomes fiercer as it weakens.\nBring arrows and food. Defeat it to claim the empty sky.\n\n05  A WORLD THAT STAYS\nAutosave runs every 45 seconds. F5 saves immediately.\nExport .slopworld backups from the pause menu or world browser.\nImport makes a separate copy, preserving the original world."
	var l = SlopSkin.label(text,13)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)

func _show_travel() -> void:
	page="travel"
	var col=_panel("THE THREE REALMS","Creative travel. In Survival, walk into a gateway near spawn.",700)
	for e in [["overworld","OVERWORLD  /  Green hills. Blue skies."],["nether","THE NETHER  /  Fire beneath your feet."],["end","THE END  /  A dragon in the dark."]]:
		var dim=str(e[0])
		var b=SlopSkin.button(e[1],func(): _travel(dim))
		b.disabled=dim==str(current_data.dimension)
		col.add_child(b)
	col.add_child(SlopSkin.button("Back",_show_inventory))
	_footer(col)

func _show_guide() -> void:
	page="guide"
	var col=_panel("A FIELD GUIDE","Small blocks. A whole lot to do.",850)
	var scroll=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(810,355); col.add_child(scroll)
	var inner=VBoxContainer.new(); inner.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(inner)
	_field_guide(inner)
	inner.add_child(SlopSkin.label("CONTROLS\nWASD: move  /  Space: jump  /  Shift: sprint  /  Ctrl: crouch\nMouse: look  /  LMB: mine or attack  /  RMB: place or eat\nE: inventory  /  1-9 or wheel: slot  /  F: Creative flight\nF3: coordinates & FPS  /  F5: save  /  Escape: pause",12,SlopSkin.ACCENT))
	col.add_child(SlopSkin.button("Back",func():
		if is_instance_valid(player): _show_pause()
		else: _show_title()
	))
	_footer(col)

func _show_options(back: String) -> void:
	page="options"
	var col=_panel("OPTIONS","Make yourself at home.",700)
	_add_slider(col,"Field of view",60,105,1,float(settings.fov),func(v): settings.fov=v; _apply_player_settings())
	_add_slider(col,"Mouse sensitivity",1,10,0.5,float(settings.sensitivity)*2000,func(v): settings.sensitivity=v/2000.0; _apply_player_settings())
	_add_slider(col,"View distance (chunks)",2,6,1,float(settings.view_distance),func(v): settings.view_distance=int(v); world.set_render_distance(int(v)))
	_add_slider(col,"Sound volume",0,100,1,float(settings.volume)*100,func(v): settings.volume=v/100.0; _apply_volume())
	var full=SlopSkin.button("Fullscreen: "+("ON" if settings.fullscreen else "OFF"),func():
		settings.fullscreen=not settings.fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		_show_options(back)
	)
	col.add_child(full)
	col.add_child(SlopSkin.label("Render style: crisp pixels / compatibility renderer\nWorlds stream as you explore. UI scales with your window.",12,SlopSkin.MUTED))
	col.add_child(SlopSkin.button("Done",func():
		_save_settings()
		if back=="pause": _show_pause()
		else: _show_title()
	))
	_footer(col)

func _add_slider(parent: VBoxContainer,title: String,minv: float,maxv: float,stepv: float,value: float,fn: Callable) -> void:
	var row=HBoxContainer.new(); parent.add_child(row)
	var l=SlopSkin.label(title+": "+str(int(value)),15); l.custom_minimum_size.x=310; row.add_child(l)
	var s=HSlider.new(); s.min_value=minv; s.max_value=maxv; s.step=stepv; s.value=value; s.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(s)
	s.value_changed.connect(func(v): l.text=title+": "+str(int(v)); fn.call(v))

func _apply_player_settings() -> void:
	if not is_instance_valid(player): return
	player.camera.fov=float(settings.fov)
	world.set_render_distance(int(settings.view_distance))
	player.set("mouse_sensitivity",float(settings.sensitivity))

func _load_settings() -> void:
	var cfg=ConfigFile.new()
	if cfg.load("user://settings.cfg")==OK:
		for k in settings: settings[k]=cfg.get_value("game",k,settings[k])
	_apply_volume()
	if settings.fullscreen: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _save_settings() -> void:
	var cfg=ConfigFile.new()
	for k in settings: cfg.set_value("game",k,settings[k])
	cfg.save("user://settings.cfg")

func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.001,float(settings.volume))))
	AudioServer.set_bus_mute(0,float(settings.volume)==0)

func _import_dialog() -> void:
	var fd=FileDialog.new()
	fd.title="Import a Slopcraft world"
	fd.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	fd.access=FileDialog.ACCESS_FILESYSTEM
	fd.filters=PackedStringArray(["*.slopworld ; Slopcraft world backup","*.json ; World JSON"])
	fd.use_native_dialog=true
	fd.file_selected.connect(func(path):
		var result=SaveManager.import_world(path)
		if result.get("ok",false):
			selected_world=str(result.get("world",{}).get("id",""))
			_show_worlds()
			_notify("World imported as a new copy.")
		else: _notify("Import failed: "+str(result.get("error","Invalid world")))
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	canvas.add_child(fd)
	fd.popup_centered_ratio(.7)

func _export_dialog(id: String) -> void:
	if id=="": return
	var fd=FileDialog.new()
	fd.title="Export world backup"
	fd.file_mode=FileDialog.FILE_MODE_SAVE_FILE
	fd.access=FileDialog.ACCESS_FILESYSTEM
	fd.filters=PackedStringArray(["*.slopworld ; Slopcraft world backup"])
	fd.current_file="Slopcraft-"+id+".slopworld"
	fd.use_native_dialog=true
	fd.file_selected.connect(func(path):
		if not path.ends_with(".slopworld"): path+=".slopworld"
		var error=SaveManager.export_world(id,path)
		_notify("Backup exported successfully." if error==OK else "Export failed. Please choose a writable folder.")
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	canvas.add_child(fd)
	fd.popup_centered_ratio(.7)

func _notify(message: String) -> void:
	if is_instance_valid(hud): hud.toast(message)
	if is_instance_valid(message_label): message_label.text=message

func _build_audio() -> void:
	audio = Node.new()
	audio.set_script(load("res://ui/soundscape.gd"))
	add_child(audio)

func _interact_block(block_id: int, block_position: Vector3i) -> void:
	if block_id==27:
		_show_chest(block_position)
	else:
		inventory_tab="Crafting"
		_show_inventory()
		_notify("Furnace recipes use fuel and materials." if block_id==26 else "Crafting table: choose a recipe.")

func _chest_key(p: Vector3i) -> String:
	return str(current_data.get("dimension","overworld"))+"|%d,%d,%d" % [p.x,p.y,p.z]

func _can_break(p: Vector3i, id: int) -> bool:
	if id!=27: return true
	var stash=current_data.get("chests",{}).get(_chest_key(p),[])
	if stash is Array:
		for slot in stash:
			if slot is Dictionary and int(slot.get("id",0))>0 and int(slot.get("count",0))>0: return false
	return true

func _show_chest(p: Vector3i) -> void:
	page="chest"
	var key=_chest_key(p)
	if not current_data.get("chests",{}) is Dictionary: current_data.chests={}
	if not current_data.has("chests"): current_data.chests={}
	var chest=PlayerInventory.new()
	chest.restore({"slots":current_data.chests.get(key,[]),"creative":false,"selected":0})
	chest.slots.resize(27)
	current_data.chests[key]=chest.slots
	var outer=_panel("CHEST","Click a stack to transfer it. Contents stay with this chest.",900)
	var scroll=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(850,420)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var col=VBoxContainer.new()
	col.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	col.add_child(SlopSkin.label("STORAGE",12,SlopSkin.MUTED))
	var grid=GridContainer.new(); grid.columns=9; col.add_child(grid)
	for i in 27:
		var slot=chest.slots[i]
		var b=Button.new(); b.custom_minimum_size=Vector2(85,50); b.tooltip_text=BlockDB.item_name(int(slot.id)); SlopSkin.style_slot(b); grid.add_child(b)
		var icon=ItemIcon.new(); icon.item_id=int(slot.id); icon.amount=int(slot.count); icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); b.add_child(icon)
		b.pressed.connect(func():
			if int(slot.id)>0 and inventory.add_item(int(slot.id),int(slot.count)):
				chest.slots[i]={"id":0,"count":0}
				current_data.chests[key]=chest.slots.duplicate(true)
				_show_chest(p)
			else: _notify("No room in your backpack.")
		)
	col.add_child(SlopSkin.label("YOUR BACKPACK",12,SlopSkin.MUTED))
	var bag=GridContainer.new(); bag.columns=9; col.add_child(bag)
	for i in inventory.slots.size():
		var slot=inventory.slots[i]
		var b=Button.new(); b.custom_minimum_size=Vector2(85,45); b.tooltip_text=BlockDB.item_name(int(slot.id)); SlopSkin.style_slot(b); bag.add_child(b)
		var icon=ItemIcon.new(); icon.item_id=int(slot.id); icon.amount=int(slot.count); icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); b.add_child(icon)
		b.pressed.connect(func():
			if int(slot.id)>0 and chest.add_item(int(slot.id),int(slot.count)):
				inventory.slots[i]={"id":0,"count":0}
				inventory.changed.emit()
				current_data.chests[key]=chest.slots.duplicate(true)
				_show_chest(p)
			else: _notify("No room in this chest.")
		)
	outer.add_child(SlopSkin.button("Done",func(): _checkpoint(); _resume()))
	_footer(outer)
