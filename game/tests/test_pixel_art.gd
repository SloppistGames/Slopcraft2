extends SceneTree
## Rendering contracts for save-stable IDs, face mapping, shape icons and item art.
var failures: Array[String] = []
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
func pixels(img: Image) -> PackedByteArray:
	return img.get_data()
func opaque_count(img: Image) -> int:
	var count: int = 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x,y).a > .1:
				count += 1
	return count
func _initialize() -> void:
	BlockAtlas.prepare()
	var checked: int = 0
	for data in BlockDB.all_blocks():
		var id: int = int(data.id)
		if id == 0: continue
		for face in 6:
			var uv: Rect2 = BlockAtlas.tile_rect(id,face)
			check(uv.position.x >= 0 and uv.position.y >= 0 and uv.end.x <= 1 and uv.end.y <= 1,"Atlas bounds %d/%d"%[id,face])
			check(opaque_count(BlockAtlas.face_image(id,face)) > 0,"Blank block %d/%d"%[id,face])
			if data.has("base_id"):
				check(pixels(BlockAtlas.face_image(id,face)) == pixels(BlockAtlas.face_image(int(data.base_id),face)),"Shape material mismatch %d/%d"%[id,face])
		check(opaque_count(BlockAtlas.icon_texture(id).get_image()) > 0,"Blank block icon %d"%id)
		checked += 1
	check(opaque_count(BlockAtlas.face_image(0,0)) == 0,"Air has texture")
	check(opaque_count(BlockAtlas.face_image(9999,0)) == 0,"Unknown ID has texture")
	var furnace_front: PackedByteArray = pixels(BlockAtlas.face_image(26,5))
	for face in range(5):
		check(pixels(BlockAtlas.face_image(26,face)) != furnace_front,"Furnace opening repeated on face %d"%face)
	check(pixels(BlockAtlas.face_image(91,2)) != pixels(BlockAtlas.face_image(91,5)),"Bookshelf books on top")
	check(pixels(BlockAtlas.face_image(91,0)) != pixels(BlockAtlas.face_image(91,5)),"Bookshelf books on side")
	check(pixels(BlockAtlas.face_image(153,2)) != pixels(BlockAtlas.face_image(154,2)),"End eye not visible")
	check(pixels(BlockAtlas.face_image(159,5)) != pixels(BlockAtlas.face_image(160,5)),"Sticky piston front indistinct")
	check(pixels(BlockAtlas.icon_texture(200).get_image()) != pixels(BlockAtlas.icon_texture(201).get_image()),"Stair/slab silhouette identical")
	check(pixels(BlockAtlas.icon_texture(200).get_image()) != pixels(BlockAtlas.icon_texture(7).get_image()),"Stair is full cube icon")
	var moss: Image = BlockAtlas.face_image(54,5)
	var moss_pixels: int = 0
	for y in 16:
		for x in 16:
			var c: Color = moss.get_pixel(x,y)
			if c.g > c.r*1.12: moss_pixels += 1
	check(moss_pixels > 15 and moss_pixels < 125,"Moss should be patches on grey bricks")
	var items_checked: int = 0
	for data in BlockDB.all_items():
		var id: int = int(data.id)
		if BlockDB.is_block(id): continue
		var sprite: Image = ItemGlyphs.texture_for(id).get_image()
		check(sprite.get_size() == Vector2i(16,16),"Item pixel dimensions %d"%id)
		var visible: int = opaque_count(sprite)
		check(visible > 15 and visible < 240,"Item silhouette missing or full rectangle %d"%id)
		check(ItemGlyphs.texture_for(id) == ItemGlyphs.texture_for(id),"Item cache instability %d"%id)
		items_checked += 1
	for pair in [[1006,1009],[1001,1018],[1011,1010],[1202,1208],[1303,1400],[1400,1401],[1102,1112],[1112,1122]]:
		check(pixels(ItemGlyphs.texture_for(pair[0]).get_image()) != pixels(ItemGlyphs.texture_for(pair[1]).get_image()),"Item identity collision %s"%str(pair))
	if failures.is_empty():
		print("PIXEL_ART_PASS: %d blocks, %d authored items; face orientation, shape alias/silhouette, moss coverage, transparency and item identity validated."%[checked,items_checked])
		quit(0)
	else:
		for message in failures: push_error(message)
		quit(1)
