extends SceneTree
var failures=0
var checks=0
func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition: failures+=1; push_error(message)
func _initialize() -> void:
	call_deferred("run")
func package(path: String,entries: Dictionary) -> void:
	var zip=ZIPPacker.new(); zip.open(path)
	for key in entries:
		zip.start_file(key); zip.write_file(str(entries[key]).to_utf8_buffer()); zip.close_file()
	zip.close()
func run() -> void:
	var b=LauncherBackend.new(); b.root_directory="user://test-library-%d" % Time.get_ticks_usec(); root.add_child(b)
	check(LauncherBackend.valid_player_name("Slopmaker_2"),"Player name accepted")
	for name in ["ab","hello world","../../escape","abc;sh"]: check(not LauncherBackend.valid_player_name(name),"Invalid name rejected")
	for path in ["../escape","/etc/passwd","a/../../escape","C:/test","a\\b","a//b","a/./b"]: check(not LauncherBackend.safe_relative(path),"Unsafe path rejected: "+path)
	var zip_path="res://tests/installer-fixture.zip"
	var receipt=ProjectSettings.globalize_path(b.root_directory.path_join("launch-receipt.txt"))
	var script="#!/bin/sh\nprintf '%s\\n' \"$@\" > '"+receipt+"'\n"
	package(zip_path,{"Game/run.sh":script,"Game/readme.txt":"Installer test fixture, not a game release."})
	check(LauncherBackend.inspect_zip(zip_path).get("ok",false),"Valid archive accepted")
	var malicious="res://tests/installer-invalid.zip"; package(malicious,{"../escape.txt":"bad"})
	check(not LauncherBackend.inspect_zip(malicious).get("ok",false),"Traversal archive rejected")
	package(malicious,{"Game/readme":"a","game/readme":"b"})
	check(not LauncherBackend.inspect_zip(malicious).get("ok",false),"Case-ambiguous archive rejected")
	var entry={"id":"installer-test","category":"snapshot","save_schema":2,"packages":{b.platform_key():{"local_path":"tests/installer-fixture.zip","sha256":FileAccess.get_sha256(zip_path),"executable":"Game/run.sh"}}}
	b.manifest={"schema":1,"versions":[entry]}
	check(LauncherBackend.valid_manifest(b.manifest),"Manifest validated")
	check(await b.install("installer-test"),"Verified installation succeeds")
	check(b.is_installed("installer-test"),"Installation registered")
	var saved=LauncherBackend.new(); saved.root_directory=b.root_directory; root.add_child(saved)
	check(saved.is_installed("installer-test"),"Installation survives launcher restart")
	if OS.get_name()!="Windows":
		var pid=b.launch("installer-test")
		check(pid>0,"Separate process starts")
		for i in 40:
			if FileAccess.file_exists(receipt): break
			await create_timer(.025).timeout
		check(FileAccess.file_exists(receipt),"Child process ran")
		if FileAccess.file_exists(receipt):
			var args=FileAccess.get_file_as_string(receipt)
			check("--player-name\nSlopmaker" in args,"Player name forwarded")
			check("--data-dir" in args and "game-data/installer-test" in args,"Version-specific data path forwarded")
	await create_timer(.1).timeout
	entry.packages[b.platform_key()].sha256="0".repeat(64)
	check(not await b.install("installer-test"),"Checksum mismatch rejects update")
	check(b.is_installed("installer-test"),"Rejected update preserves installed build")
	var data=b.root_directory.path_join("game-data/installer-test")
	DirAccess.make_dir_recursive_absolute(data)
	var save=FileAccess.open(data.path_join("world.json"),FileAccess.WRITE); save.store_string("preserve me"); save.close()
	check(b.uninstall("installer-test"),"Installed program removable")
	check(not b.is_installed("installer-test"),"Installation registry removed")
	check(FileAccess.file_exists(data.path_join("world.json")),"Uninstall preserves worlds")
	LauncherBackend._remove_tree(b.root_directory); DirAccess.remove_absolute(zip_path); DirAccess.remove_absolute(malicious)
	saved.queue_free(); b.queue_free(); await process_frame
	print("INSTALLER: ",checks," checks, ",failures," failures")
	quit(failures)
