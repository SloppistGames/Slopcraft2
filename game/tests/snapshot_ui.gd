extends SceneTree
var failures=0
func check(ok,label):
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("run")
func shot(name):
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../../work/snapshot050/"+name+".png")
func run():
	root.size=Vector2i(1280,800)
	var game=load("res://main.tscn").instantiate(); game.settings_path="user://qa-snapshot-settings.cfg"; root.add_child(game)
	SaveManager.worlds_directory="user://qa-snapshot-ui"
	await create_timer(2).timeout
	var data=SaveManager.create_world("The living world",817263,"creative")
	await game._start_world(data)
	for i in 60: await process_frame
	game._record_map_discovery()
	game._show_map()
	var map=game.world_map
	check(game.page=="map" and not game.player.active,"Map pauses player")
	check(map.add_waypoint("Home",Vector2(game.player.position.x,game.player.position.z)),"Map adds waypoint")
	for i in 100: await process_frame
	check(map.cache.size()>0,"Map renders top-down explored chunks")
	await shot("world-map")
	var event=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_WHEEL_UP; event.pressed=true; event.position=map.view.size*.5
	var zoom=map.zoom; map.map_input(event); check(map.zoom>zoom,"Map scroll zoom")
	var before=map.center
	var drag=InputEventMouseButton.new(); drag.button_index=MOUSE_BUTTON_LEFT; drag.pressed=true; map.map_input(drag)
	var motion=InputEventMouseMotion.new(); motion.relative=Vector2(100,50); map.map_input(motion); check(map.center!=before,"Map drag pan")
	map.closed.emit(); check(game.page=="game" and game.player.active,"Map close resumes")
	var custom={}; var key=InputEventKey.new(); key.physical_keycode=KEY_N; key.pressed=true
	check(SlopBindings.assign("world_map",key,custom)=="" and InputMap.event_is_action(key,"world_map"),"Map hotkey can be rebound")
	check(not SlopBindings.assign("inventory",key,custom).is_empty(),"Conflicting keybind rejected")
	SlopBindings.apply({})
	game.options_tab="Video"; game._show_options("pause"); await shot("options-video")
	game.options_tab="Sound"; game._show_options("pause"); await shot("options-sound")
	game.options_tab="Controls"; game._show_options("pause"); await shot("options-controls")
	check(game._checkpoint(),"Map checkpoint succeeds")
	var saved=SaveManager.load_world(str(game.current_data.id))
	check(saved.dimensions.overworld.map.waypoints[0].name=="Home","Waypoint survives real world save")
	game._resume(); game.player.camera_mode=2; game.player._update_camera(0); game.inventory.select_item(1102); game.player._update_held_item(); game.hud.debug_visible=true
	await shot("third-person-world")
	await game._quit_to_title()
	check(game.page=="title","Save and Quit returns to title")
	var reopened=SaveManager.load_world(str(saved.id))
	await game._start_world(reopened)
	check(game.page=="game" and game.player.active,"Saved world reopens from title")
	check(game.map_data.get("waypoints",[]).size()==1,"Reopened world retains waypoint")
	game.queue_free(); await process_frame; await create_timer(.15).timeout
	for file in DirAccess.get_files_at(SaveManager.worlds_directory): DirAccess.remove_absolute(SaveManager.worlds_directory.path_join(file))
	DirAccess.remove_absolute(SaveManager.worlds_directory); DirAccess.remove_absolute("user://qa-snapshot-settings.cfg")
	print("SNAPSHOT UI failures: ",failures); quit(failures)
