class_name SlopHUD
extends Control
var player: VoxelPlayer
var inventory: PlayerInventory
var entities: SlopEntities
var world_name = ""
var dimension = "overworld"
var help_timer = 18.0
var elapsed = 0.0
var notice = ""
var notice_time = 0.0
var debug_visible = false
var selection_cache = -1
var selection_time = 0.0
var icons: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 9:
		var icon = ItemIcon.new()
		add_child(icon)
		icons.append(icon)

func _process(delta: float) -> void:
	if not visible or not is_instance_valid(player): return
	elapsed += delta
	help_timer = maxf(0,help_timer-delta)
	notice_time = maxf(0,notice_time-delta)
	selection_time = maxf(0,selection_time-delta)
	if selection_cache != inventory.selected:
		selection_cache = inventory.selected
		selection_time = 3.5
	var origin = Vector2(size.x/2-9*56/2,size.y-78)
	for i in 9:
		icons[i].position = origin+Vector2(i*56+4,4)
		icons[i].size = Vector2(48,48)
		icons[i].item_id = int(inventory.slots[i].get("id",0))
		icons[i].amount = int(inventory.slots[i].get("count",0)) if not inventory.creative else 0
		icons[i].queue_redraw()
	queue_redraw()

func toast(message: String) -> void:
	notice = message
	notice_time = 4.0

func text_at(p: Vector2, txt: String, font_size: int = 16, color: Color = Color.WHITE) -> void:
	draw_string(SlopSkin.font,p+Vector2(2,2),txt,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(0,0,0,.8))
	draw_string(SlopSkin.font,p,txt,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func center_text(y: float, txt: String, font_size: int = 16, color: Color = Color.WHITE) -> void:
	var w = SlopSkin.font.get_string_size(txt,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	text_at(Vector2((size.x-w)/2,y),txt,font_size,color)

func heart(p: Vector2, full: bool) -> void:
	var pixels = ["0110110","1111111","1111111","0111110","0011100","0001000"]
	var color = Color("ec5c56") if full else Color("3e3834")
	for y in pixels.size():
		for x in pixels[y].length():
			if pixels[y][x] == "1": draw_rect(Rect2(p+Vector2(x*3,y*3),Vector2(3,3)),color)
	if full: draw_rect(Rect2(p+Vector2(3,3),Vector2(3,3)),Color("ffb8a2"))

func _draw() -> void:
	if not is_instance_valid(player) or not inventory: return
	var center = size*.5
	draw_line(center-Vector2(7,0),center+Vector2(7,0),Color(0,0,0,.5),4)
	draw_line(center-Vector2(0,7),center+Vector2(0,7),Color(0,0,0,.5),4)
	draw_line(center-Vector2(6,0),center+Vector2(6,0),Color(1,1,1,.9),2)
	draw_line(center-Vector2(0,6),center+Vector2(0,6),Color(1,1,1,.9),2)
	var origin = Vector2(size.x/2-252,size.y-78)
	draw_rect(Rect2(origin-Vector2(4,4),Vector2(512,64)),Color("151b19"))
	for i in 9:
		var r = Rect2(origin+Vector2(i*56,0),Vector2(56,56))
		draw_rect(r,Color("767c78"))
		draw_rect(r.grow(-3),Color("242c25"))
		draw_line(r.position+Vector2(3,3),r.position+Vector2(53,3),Color("111914"),3)
		if i == inventory.selected:
			draw_rect(r.grow(2),SlopSkin.ACCENT,false,3)
			draw_rect(Rect2(r.position+Vector2(12,53),Vector2(32,3)),SlopSkin.ACCENT)
		text_at(r.position+Vector2(5,13),str(i+1),10,Color("b2b6a9"))
	if not inventory.creative:
		for i in 10:
			heart(origin+Vector2(i*24,-35),player.health>i*2)
			var col = Color("d6a46a") if player.hunger>i*2 else Color("504437")
			var p = origin+Vector2(278+i*23,-28)
			draw_rect(Rect2(p+Vector2(8,2),Vector2(7,10)),Color("e2ddc9"))
			draw_rect(Rect2(p-Vector2(0,6),Vector2(15,13)),Color("392f26"))
			draw_rect(Rect2(p+Vector2(2,-4),Vector2(11,9)),col)
		draw_rect(Rect2(origin+Vector2(0,-10),Vector2(504,5)),Color("1e2d25"))
		draw_rect(Rect2(origin+Vector2(0,-10),Vector2(504*player.health/20.0,5)),Color("8dae5b"))
	else: center_text(size.y-94,"CREATIVE  /  F TO FLY",12,SlopSkin.ACCENT)
	if selection_time>0 and inventory.selected_id()>0:
		center_text(size.y-128,BlockDB.item_name(inventory.selected_id()),17)
	if player.target_name != "":
		center_text(size.y*.5+38,player.target_name,12,Color("d3dac8"))
	if player.mining_progress>0:
		draw_rect(Rect2(center+Vector2(-40,49),Vector2(80,4)),Color("263125"))
		draw_rect(Rect2(center+Vector2(-40,49),Vector2(80*player.mining_progress,4)),SlopSkin.ACCENT)
	text_at(Vector2(26,35),"SLOPCRAFT 2",17,SlopSkin.ACCENT)
	text_at(Vector2(26,57),dimension.to_upper()+" / "+world_name,11,Color("d0d6c4"))
	if help_timer>0:
		text_at(Vector2(26,size.y-58),"WASD MOVE  /  SPACE JUMP  /  SHIFT SPRINT",11)
		text_at(Vector2(26,size.y-36),"E INVENTORY  /  ESC PAUSE",11,Color("bfcab3"))
		var txt = "LMB MINE  /  RMB PLACE"
		var w = SlopSkin.font.get_string_size(txt,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		text_at(Vector2(size.x-w-26,size.y-36),txt,11,Color("bfcab3"))
	if notice_time>0:
		center_text(118,notice,17,SlopSkin.ACCENT)
	if is_instance_valid(entities) and entities.boss_alive and dimension=="end":
		center_text(34,"ENDERSLOP",20,Color("edc2ff"))
		var r = Rect2(Vector2(size.x/2-250,46),Vector2(500,10))
		draw_rect(r.grow(3),Color("221729"))
		draw_rect(Rect2(r.position,Vector2(500*entities.boss_health/entities.boss_max_health,10)),Color("bd76db"))
	if debug_visible:
		text_at(Vector2(26,90),"FPS %d   XYZ %.1f / %.1f / %.1f" % [Engine.get_frames_per_second(),player.position.x,player.position.y,player.position.z],12)
	if player.health < 8 and not inventory.creative:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.6,0.03,0.01,.04+.025*sin(elapsed*3)))
