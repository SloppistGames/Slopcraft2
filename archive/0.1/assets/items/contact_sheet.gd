extends SceneTree
## Native 4x nearest-neighbour audit; run with --script res://assets/items/contact_sheet.gd.
func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600,1200)
	var background := ColorRect.new()
	background.color = Color("242932")
	background.size = Vector2(1600,1200)
	root.add_child(background)
	var heading := Label.new()
	heading.text = "SLOPCRAFT 2  /  ITEM PIXEL ART  /  16px original sprites at 4x"
	heading.position = Vector2(30,18)
	heading.add_theme_font_size_override("font_size",22)
	root.add_child(heading)
	var index := 0
	var atlas := Image.create(160,128,false,Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for data in BlockDB.all_items():
		var id := int(data.id)
		if BlockDB.is_block(id):
			continue
		var texture: Texture2D = ItemGlyphs.texture_for(id)
		var cell := Vector2(20+(index%10)*158,65+(index/10)*137)
		var checker := ColorRect.new()
		checker.color = Color("313844")
		checker.position = cell+Vector2(43,0)
		checker.size = Vector2(72,72)
		root.add_child(checker)
		var icon := TextureRect.new()
		icon.texture = texture
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.position = cell+Vector2(47,4)
		icon.size = Vector2(64,64)
		root.add_child(icon)
		var label := Label.new()
		label.position = cell+Vector2(0,79)
		label.size = Vector2(158,49)
		label.text = "%d\n%s" % [id,data.name]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",13)
		root.add_child(label)
		atlas.blit_rect(texture.get_image(),Rect2i(0,0,16,16),Vector2i((index%10)*16,(index/10)*16))
		index += 1
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://assets/items/items_contact_sheet.png")
	root.get_texture().get_image().save_png(output)
	atlas.save_png(ProjectSettings.globalize_path("res://assets/items/items_atlas.png"))
	print("ITEM_ART: rendered %d sprites to %s" % [index,output])
	quit()
