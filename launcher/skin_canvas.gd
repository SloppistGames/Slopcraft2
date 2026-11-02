extends Control
## A single drag is one undoable edit, with integer pixel interpolation.
var editor: Control
var zoom: int = 8
var show_grid: bool = true
var focus_part: String = ""
var focus_overlay: bool = false
var drawing: bool = false
var last_pixel: Vector2i = Vector2i(-1,-1)

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	focus_mode = Control.FOCUS_ALL
	set_zoom(zoom)

func set_zoom(value: int) -> void:
	zoom = clampi(value,4,20)
	custom_minimum_size = Vector2.ONE * 64 * zoom
	size = custom_minimum_size
	queue_redraw()

func _draw() -> void:
	if editor == null: return
	for y in range(0,64,4):
		for x in range(0,64,4):
			var color: Color = Color("354446") if (x/4+y/4)%2 == 0 else Color("263437")
			draw_rect(Rect2(x*zoom,y*zoom,4*zoom,4*zoom),color)
	draw_texture_rect(editor.texture,Rect2(Vector2.ZERO,Vector2.ONE*64*zoom),false)
	if show_grid:
		for i in 65:
			var line: Color = Color(0.7,0.85,0.78,0.24) if i%8 == 0 else Color(0,0,0,0.17)
			draw_line(Vector2(i*zoom,0),Vector2(i*zoom,64*zoom),line)
			draw_line(Vector2(0,i*zoom),Vector2(64*zoom,i*zoom),line)
	if not focus_part.is_empty():
		for rect in editor.Model.face_rects(focus_part,focus_overlay):
			draw_rect(Rect2(rect.position*zoom,rect.size*zoom),Color("c6f28b"),false,2)
	if last_pixel.x >= 0:
		draw_rect(Rect2(Vector2(last_pixel)*zoom,Vector2.ONE*zoom),Color.WHITE,false,1)

func _gui_input(event: InputEvent) -> void:
	if editor == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pixel: Vector2i = Vector2i((event.position / zoom).floor())
		if event.pressed and _inside(pixel):
			grab_focus()
			if editor.tool == "picker":
				editor.select_color(editor.image.get_pixelv(pixel))
			elif editor.tool == "fill":
				editor.fill_at(pixel)
			else:
				drawing = true
				editor.begin_edit()
				editor.paint_pixel(pixel)
				last_pixel = pixel
		else:
			finish_stroke()
		accept_event()
	elif event is InputEventMouseMotion:
		var pixel: Vector2i = Vector2i((event.position / zoom).floor())
		if drawing and _inside(pixel):
			var steps: int = maxi(absi(pixel.x-last_pixel.x),absi(pixel.y-last_pixel.y))
			for step in range(steps+1):
				var point: Vector2i = Vector2i(Vector2(last_pixel).lerp(Vector2(pixel),float(step)/maxi(1,steps)).round())
				editor.paint_pixel(point,false)
			editor.refresh_pixels()
		if _inside(pixel):
			last_pixel = pixel
			editor.coordinate_label.text = "Pixel %02d, %02d" % [pixel.x,pixel.y]
		queue_redraw()

func _input(event: InputEvent) -> void:
	# Finish drags released outside the scrollable pixel grid as well.
	if drawing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish_stroke()

func finish_stroke() -> void:
	if drawing:
		drawing = false
		editor.commit_edit()

func _inside(point: Vector2i) -> bool:
	return point.x >= 0 and point.x < 64 and point.y >= 0 and point.y < 64
