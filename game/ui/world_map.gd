class_name SlopWorldMap
extends Control
signal closed
class MapView extends Control:
	var owner_map
	func _draw(): owner_map.draw_map(self)
	func _gui_input(event): owner_map.map_input(event)
var game: Node
var data: Dictionary
var center=Vector2.ZERO
var zoom=5.0
var view: MapView
var coordinate_label: Label
var waypoint_list: VBoxContainer
var cache: Dictionary={}
var pending: Array[Vector2i]=[]
var rendering=Vector2i(2147483647,0)
var image: Image
var cursor=0
var dragging=false
var hover_world=Vector2.ZERO
func setup(owner_game: Node,map_data: Dictionary) -> void:
	game=owner_game; data=map_data
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme=SlopSkin.theme()
	var bg=ColorRect.new(); bg.color=Color("101a1b"); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var title=SlopSkin.label("WORLD ATLAS",27,SlopSkin.ACCENT); title.position=Vector2(26,22); add_child(title)
	var close=SlopSkin.button("Back to game",func(): closed.emit(),210); close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); close.offset_left=-236; close.offset_top=18; close.offset_right=-26; close.offset_bottom=65; add_child(close)
	var body=HBoxContainer.new(); body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); body.offset_left=24; body.offset_top=86; body.offset_right=-24; body.offset_bottom=-52; body.add_theme_constant_override("separation",20); add_child(body)
	view=MapView.new(); view.owner_map=self; view.clip_contents=true; view.size_flags_horizontal=Control.SIZE_EXPAND_FILL; view.custom_minimum_size=Vector2(480,320); body.add_child(view)
	var side=VBoxContainer.new(); side.custom_minimum_size.x=235; side.add_theme_constant_override("separation",12); body.add_child(side)
	side.add_child(SlopSkin.label(str(game.current_data.name),17,SlopSkin.ACCENT))
	side.add_child(SlopSkin.label(game.world.dimension.to_upper(),12,SlopSkin.MUTED))
	var explanation=SlopSkin.label("Drag to pan. Scroll to zoom.\nRight-click to mark a place.\nDark chunks are unexplored.",11,SlopSkin.MUTED); side.add_child(explanation)
	side.add_child(SlopSkin.button("Center on player",center_on_player))
	side.add_child(SlopSkin.button("Add waypoint",func(): waypoint_dialog(center)))
	side.add_child(SlopSkin.label("WAYPOINTS",13,SlopSkin.ACCENT))
	var scroll=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; side.add_child(scroll)
	waypoint_list=VBoxContainer.new(); waypoint_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(waypoint_list)
	coordinate_label=SlopSkin.label("",12,SlopSkin.MUTED); coordinate_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT); coordinate_label.offset_left=26; coordinate_label.offset_top=-33; coordinate_label.offset_right=1000; coordinate_label.offset_bottom=-10; add_child(coordinate_label)
	game.world.block_changed.connect(func(p,_id): cache.erase(Vector2i(floori(p.x/16.0),floori(p.z/16.0)))); _refresh_waypoints(); center_on_player()
func center_on_player() -> void:
	center=Vector2(game.player.position.x,game.player.position.z); view.queue_redraw()
func _input(event: InputEvent) -> void:
	if visible and event.is_pressed() and (event.is_action_pressed("world_map") or event.is_action_pressed("pause")):
		closed.emit(); get_viewport().set_input_as_handled()
func _process(_delta: float) -> void:
	if not visible: return
	if image==null and not pending.is_empty():
		rendering=pending.pop_front(); image=Image.create(16,16,false,Image.FORMAT_RGBA8); cursor=0
	if image!=null:
		var start=Time.get_ticks_usec()
		while cursor<256 and Time.get_ticks_usec()-start<2000:
			var x=rendering.x*16+cursor%16; var z=rendering.y*16+cursor/16
			var h=int(game.world.surface_height(x,z)); var top=h; var id=int(game.world.get_block(Vector3i(x,h,z)))
			for y in range(mini(game.world.max_y()-1,h+22),h,-1):
				var candidate=int(game.world.get_block(Vector3i(x,y,z)))
				if candidate>0 and candidate not in [165,166,168]: id=candidate; top=y; break
			var color: Color=BlockDB.get_block(id).get("color",Color("64705c"))
			if id==9: color=Color("427eab")
			if id==20: color=Color("db6d30")
			var shade=clampf(.85+(top-23)*.004,.65,1.2)
			image.set_pixel(cursor%16,cursor/16,Color(color.r*shade,color.g*shade,color.b*shade,1)); cursor+=1
		if cursor==256:
			cache[rendering]=ImageTexture.create_from_image(image); image=null; rendering=Vector2i(2147483647,0); view.queue_redraw()
	coordinate_label.text="X %d  /  Z %d    •    %s    •    Zoom %.1fx" % [int(hover_world.x),int(hover_world.y),game.world.biome_at(Vector3(hover_world.x,0,hover_world.y)),zoom]
func draw_map(canvas: Control) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO,canvas.size),Color("172328"))
	var half=canvas.size/(2*zoom); var low=center-half; var high=center+half
	var first=Vector2i(floori(low.x/16),floori(low.y/16)); var last=Vector2i(floori(high.x/16),floori(high.y/16))
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var coord=Vector2i(x,z); var pos=to_screen(Vector2(x*16,z*16)); var rect=Rect2(pos,Vector2.ONE*16*zoom)
			if cache.has(coord): canvas.draw_texture_rect(cache[coord],rect,false)
			elif data.get("discovered",{}).has("%d,%d" % [x,z]):
				canvas.draw_rect(rect,Color("344b42"))
				if not pending.has(coord) and rendering!=coord: pending.append(coord)
			canvas.draw_rect(rect,Color(0,0,0,.13),false,1)
	for waypoint in data.get("waypoints",[]):
		var p=to_screen(Vector2(float(waypoint.x),float(waypoint.z)))
		canvas.draw_circle(p,6,Color("edc967")); canvas.draw_circle(p,3,Color("362d24"))
		canvas.draw_string(SlopSkin.font,p+Vector2(10,-8),str(waypoint.name),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("f6e4a5"))
	var position=to_screen(Vector2(game.player.position.x,game.player.position.z))
	var direction=Vector2(-sin(game.player.rotation.y),-cos(game.player.rotation.y))
	var side=direction.orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([position+direction*11,position-direction*6+side*6,position-direction*6-side*6]),Color("f4f7eb"))
	canvas.draw_circle(canvas.size*.5,3,Color(1,1,1,.5),false,1)
func to_screen(p: Vector2) -> Vector2: return (p-center)*zoom+view.size*.5
func to_world(p: Vector2) -> Vector2: return (p-view.size*.5)/zoom+center
func map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT: dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before=to_world(event.position); zoom=clampf(zoom*(1.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .8),.5,12); center+=before-to_world(event.position); view.queue_redraw()
		if event.pressed and event.button_index==MOUSE_BUTTON_RIGHT: waypoint_dialog(to_world(event.position))
	elif event is InputEventMouseMotion:
		if dragging: center-=event.relative/zoom; view.queue_redraw()
		hover_world=to_world(event.position)
func add_waypoint(title: String,position: Vector2) -> bool:
	if not position.is_finite() or absf(position.x)>30000000 or absf(position.y)>30000000: return false
	if not data.has("waypoints"): data.waypoints=[]
	if data.waypoints.size()>=128: return false
	var name_value=title.strip_edges().left(40)
	if name_value.is_empty(): name_value="Waypoint "+str(data.waypoints.size()+1)
	data.waypoints.append({"id":str(Time.get_ticks_usec()),"name":name_value,"x":position.x,"z":position.y})
	_refresh_waypoints(); view.queue_redraw(); return true
func waypoint_dialog(position: Vector2) -> void:
	var dialog=ConfirmationDialog.new(); dialog.title="Waypoint at %d, %d" % [int(position.x),int(position.y)]; dialog.dialog_text="Name this location"; add_child(dialog)
	var field=LineEdit.new(); field.max_length=40; field.placeholder_text="Home, cave entrance, village..."; field.custom_minimum_size=Vector2(420,44); dialog.add_child(field)
	dialog.confirmed.connect(func(): add_waypoint(field.text,position); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(470,150)); field.grab_focus()
func _refresh_waypoints() -> void:
	if waypoint_list==null: return
	for child in waypoint_list.get_children(): waypoint_list.remove_child(child); child.queue_free()
	for waypoint in data.get("waypoints",[]):
		var row=HBoxContainer.new(); waypoint_list.add_child(row)
		var go=SlopSkin.button(str(waypoint.name),func(): center=Vector2(float(waypoint.x),float(waypoint.z)); view.queue_redraw(),175); go.custom_minimum_size.y=35; go.add_theme_font_size_override("font_size",12); row.add_child(go)
		var remove=SlopSkin.button("×",func(): data.waypoints.erase(waypoint); _refresh_waypoints(); view.queue_redraw(),35); remove.custom_minimum_size.y=35; row.add_child(remove)
