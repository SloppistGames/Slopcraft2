extends SceneTree
var checks=0
var failures=0
func check(ok,label):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("run")
func run():
	var args=OS.get_cmdline_user_args(); var source=""
	for i in args.size():
		if args[i]=="--package" and i+1<args.size(): source=args[i+1]
	if not FileAccess.file_exists(source): push_error("Pass -- --package /absolute/game.zip"); quit(2); return
	var zip_path="res://tests/actual-game.zip"
	check(DirAccess.copy_absolute(source,zip_path)==OK,"Actual exported package staged")
	var reader=ZIPReader.new(); reader.open(zip_path); var executable=""
	for path in reader.get_files():
		if (OS.get_name()=="macOS" and ".app/Contents/MacOS/" in path and not path.ends_with("/")) or (OS.get_name()=="Windows" and path.ends_with("Slopcraft2.exe")): executable=path; break
	reader.close(); check(not executable.is_empty(),"Export contains platform executable")
	var b=LauncherBackend.new(); b.root_directory="user://packaged-qa-%d" % Time.get_ticks_usec(); b.auto_refresh_enabled=false; root.add_child(b)
	b.manifest={"schema":1,"versions":[{"id":"packaged-qa","category":"snapshot","save_schema":2,"packages":{b.platform_key():{"local_path":"tests/actual-game.zip","sha256":FileAccess.get_sha256(zip_path),"executable":executable}}}]}
	var skin=PlayerModel.default_skin_image(); skin.set_pixel(11,11,Color.MAGENTA); skin.set_pixel(12,13,Color.LIME_GREEN)
	var skin_path=ProjectSettings.globalize_path(b.root_directory.path_join("qa-skin.png")); skin.save_png(skin_path)
	b.settings.player_name="Launcher_QA"; b.settings.skin_path=skin_path; b.save_settings()
	check(await b.install("packaged-qa"),"Launcher installs actual game: "+b.last_error)
	if not b.is_installed("packaged-qa"): b.free(); quit(1); return
	var log=ProjectSettings.globalize_path(b.root_directory.path_join("game.log"))
	var pid=b.launch("packaged-qa",["--headless","--log-file",log],["--smoke-game"])
	check(pid>0,"Launcher starts separate game process")
	var deadline=Time.get_ticks_msec()+90000
	while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline: await create_timer(.25).timeout
	check(not OS.is_process_running(pid),"Game completes native smoke test within timeout")
	if OS.is_process_running(pid): OS.kill(pid)
	var output=FileAccess.get_file_as_string(log)
	check("GAME_SMOKE_OK" in output,"Packaged game creates and saves real world")
	check(not "SCRIPT ERROR" in output and not "ERROR:" in output,"Packaged game has no runtime errors")
	var receipt={}
	for line in output.split("\n"):
		if line.begins_with("GAME_SMOKE_PROFILE="): receipt=JSON.parse_string(line.trim_prefix("GAME_SMOKE_PROFILE="))
	check(receipt.get("name","")=="Launcher_QA","Launcher player name reaches game")
	check(receipt.get("skin_sha256","")==skin.get_data().hex_encode().sha256_text(),"Exact edited skin reaches installed game")
	check(str(receipt.get("worlds_directory","")).contains("game-data/packaged-qa/worlds"),"Installed game saves in its version library")
	var evidence=FileAccess.open("res://../../work/snapshot050/packaged-game-runtime.log",FileAccess.WRITE)
	if evidence: evidence.store_string(output); evidence.close()
	check(b.uninstall("packaged-qa"),"Actual build uninstalls cleanly")
	var directory=b.root_directory; b.free(); await create_timer(.15).timeout
	LauncherBackend._remove_tree(directory); DirAccess.remove_absolute(zip_path)
	print("PACKAGED GAME: ",checks," checks, ",failures," failures"); quit(failures)
