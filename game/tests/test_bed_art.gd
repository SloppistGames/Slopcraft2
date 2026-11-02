extends SceneTree
## Probe exported mesh UVs at physical pillow/blanket positions in all rotations.
var failures=0
var checks=0
func check(ok,label):
	checks+=1
	if not ok: failures+=1; push_error(label)
func sample_mesh(mesh: ArrayMesh, point: Vector3) -> Color:
	var data=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=data[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array=data[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array=data[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		var a=vertices[indices[i]]; var b=vertices[indices[i+1]]; var c=vertices[indices[i+2]]
		var v0=b-a; var v1=c-a; var v2=point-a
		if absf(v0.cross(v1).normalized().dot(v2))>.0001: continue
		var den=v0.dot(v0)*v1.dot(v1)-v0.dot(v1)*v0.dot(v1)
		if absf(den)<.000001: continue
		var u=(v1.dot(v1)*v2.dot(v0)-v0.dot(v1)*v2.dot(v1))/den
		var v=(v0.dot(v0)*v2.dot(v1)-v0.dot(v1)*v2.dot(v0))/den
		if u<-.0001 or v<-.0001 or u+v>1.0001: continue
		var at=uv[indices[i]]*(1-u-v)+uv[indices[i+1]]*u+uv[indices[i+2]]*v
		var image=BlockAtlas.texture.get_image()
		return image.get_pixel(clampi(int(at.x*image.get_width()),0,image.get_width()-1),clampi(int(at.y*image.get_height()),0,image.get_height()-1))
	return Color.TRANSPARENT
func white(c: Color): return c.a>.9 and c.g>.65 and absf(c.r-c.g)<.12
func red(c: Color): return c.a>.9 and c.r>c.g*1.5 and c.r>c.b*1.3
func _initialize(): call_deferred("run")
func run():
	var fixture=load("res://tests/test_shapes.gd").FixtureWorld.new(); root.add_child(fixture)
	var foot=Vector3i(7,0,7)
	for rotation in 4:
		var head=foot+RestTransportSystem.DIRECTIONS[rotation]
		fixture.values={foot:181,head:182}; fixture.states={foot:{"rotation":rotation},head:{"rotation":rotation}}
		var chunk=VoxelChunkMesh.build(fixture,Vector2i.ZERO,fixture.buffer()); root.add_child(chunk)
		var mesh: ArrayMesh=chunk.get_child(0).mesh
		var basis=Basis(Vector3.UP,-rotation*PI*.5)
		for probe in [[Vector3(.5,.5625,.2),true],[Vector3(.5,.5625,.82),false],[Vector3(1,.5,.2),true],[Vector3(1,.5,.82),false],[Vector3(0,.5,.2),true],[Vector3(0,.5,.82),false],[Vector3(.5,.5,0),true],[Vector3(.5,.5,1),false]]:
			var point=Vector3(head)+basis*(probe[0]-Vector3(.5,0,.5))+Vector3(.5,0,.5)
			var color=sample_mesh(mesh,point)
			check(white(color) if probe[1] else red(color),"Bed head material at %s rotation %d = %s" % [probe[0],rotation,color])
		var point=Vector3(foot)+basis*Vector3(0,.5625,0)+Vector3(.5,0,.5)
		check(red(sample_mesh(mesh,point)),"Foot has continuous blanket rotation "+str(rotation))
		check(BlockShapes.boxes(181,{"rotation":rotation}).size()+BlockShapes.boxes(182,{"rotation":rotation}).size()==6,"Complete bed has two mattresses and four legs")
		chunk.free()
	fixture.free()
	print("BED ART: ",checks," checks, ",failures," failures")
	quit(failures)
