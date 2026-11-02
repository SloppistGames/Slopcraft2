extends SceneTree
## Rendered art inspection, independent from the production main scene.
## godot --path <project> --script res://tests/texture_gallery.gd -- --capture /absolute/output.png

const WIDTH = 1600
const HEIGHT = 1100
const SPECIMENS = ["Furnace", "Bookshelf", "Mossy Stone Bricks", "Chest", "Crafting Table", "Oak Log", "Birch Log", "Pumpkin", "Bricks", "Cobblestone", "Coal Ore", "Iron Ore", "Diamond Ore", "Grass Block", "Glass"]
var capture_path = ""
var scene: Node3D
var camera: Camera3D

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--capture":
			capture_path = args[i+1] if i+1 < args.size() else "res://../../work/screens/texture-gallery.png"
	call_deferred("_run")

func _run() -> void:
	root.title = "Slopcraft 2 · Texture gallery"
	root.size = Vector2i(WIDTH,HEIGHT)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_DISABLED
	BlockAtlas.prepare()
	scene = Node3D.new()
	root.add_child(scene)
	var environment_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("191d24")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment_node.environment = environment
	scene.add_child(environment_node)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 0.7
	light.light_color = Color.WHITE
	light.shadow_enabled = false
	scene.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.0
	camera.position = Vector3(0,0,-30)
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var overlay = CanvasLayer.new()
	root.add_child(overlay)
	_add_label(overlay,"SLOPCRAFT 2  /  MATERIAL STUDY",Vector2(42,26),Vector2(WIDTH-84,38),30,Color("f2f4f1"),HORIZONTAL_ALIGNMENT_LEFT)
	_add_label(overlay,"Original pixel textures · %d × %d texels per face · top, front (−Z), and right faces" % [BlockAtlas.TILE,BlockAtlas.TILE],Vector2(44,70),Vector2(WIDTH-88,28),18,Color("a0a9b5"),HORIZONTAL_ALIGNMENT_LEFT)
	for i in range(SPECIMENS.size()):
		var id = _find_block(SPECIMENS[i])
		var column = i%5
		var row = int(i/5)
		var center_px = Vector2(176+column*312,235+row*310)
		var specimen = MeshInstance3D.new()
		specimen.name = str(SPECIMENS[i]).replace(" ","_")
		specimen.mesh = _cube(id)
		specimen.rotation_degrees = Vector3(-23,36,0)
		specimen.scale = Vector3.ONE*1.70
		scene.add_child(specimen)
		# Projecting screen positions avoids perspective/shear in the specimen grid.
		specimen.position = camera.project_position(center_px,30)
		_add_label(overlay,SPECIMENS[i],Vector2(center_px.x-145,center_px.y+120),Vector2(290,30),21,Color("e9eceb"))
		_add_label(overlay,"BLOCK %03d"%id,Vector2(center_px.x-145,center_px.y+151),Vector2(290,24),14,Color("7f8c9c"))
	_add_label(overlay,"Same face UV mapping and atlas materials used by the voxel world. Neutral lighting; nearest filtering.",Vector2(44,1048),Vector2(WIDTH-88,28),17,Color("8c97a5"),HORIZONTAL_ALIGNMENT_LEFT)
	if not capture_path.is_empty():
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var path = ProjectSettings.globalize_path(capture_path)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var error = root.get_texture().get_image().save_png(path)
		print("TEXTURE_GALLERY ",path," result=",error)
		quit(0 if error == OK else 1)

func _find_block(display_name: String) -> int:
	for block in BlockDB.all_blocks():
		if str(block.name) == display_name:
			return int(block.id)
	push_error("Missing gallery block: "+display_name)
	return 1

func _cube(id: int) -> ArrayMesh:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	for face in range(6):
		var start = vertices.size()
		var rect = BlockAtlas.tile_rect(id,face)
		var uv = [Vector2(rect.position.x,rect.end.y),rect.position,Vector2(rect.end.x,rect.position.y),rect.end]
		for corner in range(4):
			vertices.append(VoxelChunkMesh.CORNERS[face][corner]-Vector3.ONE*0.5)
			normals.append(VoxelChunkMesh.NORMALS[face])
			var shade: float = VoxelChunkMesh.SHADES[face]
			colors.append(Color(shade,shade,shade))
			uvs.append(uv[corner])
		for index in [0,2,1,0,3,2]:
			indices.append(start+index)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,BlockAtlas.materials[1 if id == 16 else 0])
	return mesh

func _add_label(parent: Node,text: String,pos: Vector2,dimensions: Vector2,font_size: int,color: Color,align: int = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var label = Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
