class_name LauncherBackend
extends Node
signal changed
signal catalog_updated(new_versions: Array)
signal progress(phase: String, fraction: float)
signal failure(message: String)
const MANIFEST_URL="https://raw.githubusercontent.com/SloppistGames/Slopcraft2/main/launcher/manifest.json"
const MAX_PACKAGE_BYTES=512*1024*1024
const MAX_EXTRACT_BYTES=1024*1024*1024
var root_directory="user://library"
var manifest: Dictionary={"schema":1,"versions":[]}
var settings: Dictionary={"player_name":"Slopmaker","skin_path":"","fullscreen":false,"vsync":true}
var installed: Dictionary={}
var running: Dictionary={}
var busy=false
var last_error=""
var request: HTTPRequest
var cancel_requested=false
var refreshing=false
var auto_refresh_enabled=true
var refresh_interval=300.0
var refresh_clock=0.0
var last_catalog_check=0.0
var last_catalog_error=""
var catalog_etag=""
var catalog_request: HTTPRequest
func _ready() -> void:
	initialize()
func initialize() -> void:
	DirAccess.make_dir_recursive_absolute(root_directory)
	var saved=_read_json(root_directory.path_join("settings.json"))
	settings.merge(saved,true)
	installed=_read_json(root_directory.path_join("installed.json"))
	var cached=_read_json(root_directory.path_join("manifest.json"))
	manifest=cached if valid_manifest(cached) else _read_json("res://manifest.json")
	if not valid_manifest(manifest): manifest={"schema":1,"versions":[]}
	catalog_etag=str(_read_json(root_directory.path_join("catalog-meta.json")).get("etag","")) if valid_manifest(cached) else ""
func platform_key() -> String:
	return "macos" if OS.get_name()=="macOS" else "windows" if OS.get_name()=="Windows" else OS.get_name().to_lower()
func versions(category: String="") -> Array:
	var result: Array=[]
	for entry in manifest.get("versions",[]):
		if category=="" or str(entry.get("category",""))==category: result.append(entry)
	for id in installed:
		var found=false
		for entry in result:
			if str(entry.id)==str(id): found=true; break
		if not found and installed[id].get("entry") is Dictionary:
			var entry: Dictionary=installed[id].entry.duplicate(true)
			if category=="" or str(entry.get("category",""))==category: result.append(entry)
	return result
func version(id: String) -> Dictionary:
	for entry in versions():
		if str(entry.get("id",""))==id: return entry
	return {}
func package_for(entry: Dictionary) -> Dictionary:
	return entry.get("packages",{}).get(platform_key(),{})
func is_installed(id: String) -> bool:
	if not installed.has(id): return false
	var relative=str(installed[id].get("executable",""))
	return safe_relative(relative) and FileAccess.file_exists(root_directory.path_join(id).path_join(relative))
func is_running(id: String) -> bool:
	if not running.has(id): return false
	if not OS.is_process_running(int(running[id])): running.erase(id); return false
	return true
func _process(delta: float) -> void:
	refresh_clock+=delta
	if auto_refresh_enabled and refresh_clock>=refresh_interval and not refreshing and not busy:
		refresh(true)
	if busy and is_instance_valid(request):
		var length=request.get_body_size()
		if length>0: progress.emit("Downloading",clampf(float(request.get_downloaded_bytes())/length,0,1))
func refresh(silent: bool=false) -> bool:
	if refreshing: return false
	refreshing=true; refresh_clock=0.0; last_catalog_check=Time.get_unix_time_from_system()
	catalog_request=HTTPRequest.new(); catalog_request.body_size_limit=2*1024*1024; catalog_request.timeout=20; catalog_request.use_threads=true; add_child(catalog_request)
	var headers=PackedStringArray(["Cache-Control: no-cache","Accept: application/json"])
	if not catalog_etag.is_empty(): headers.append("If-None-Match: "+catalog_etag)
	var err=catalog_request.request(MANIFEST_URL,headers)
	if err!=OK:
		_end_catalog_request()
		return _catalog_failure("Could not reach the version archive. Installed builds still work offline.",silent)
	var response=await catalog_request.request_completed
	_end_catalog_request()
	return accept_catalog_response(int(response[0]),int(response[1]),response[2],response[3],silent)
func _end_catalog_request() -> void:
	if is_instance_valid(catalog_request): catalog_request.queue_free()
	catalog_request=null; refreshing=false
func _catalog_failure(message: String,silent: bool) -> bool:
	last_catalog_error=message
	if not silent: failure.emit(message)
	return false
func accept_catalog_response(result: int,code: int,headers: PackedStringArray,body: PackedByteArray,silent: bool=false) -> bool:
	if result!=HTTPRequest.RESULT_SUCCESS:
		return _catalog_failure("The archive is unavailable. Using the saved version list; installed builds still work offline.",silent)
	if code==304:
		last_catalog_error=""; return true
	if code!=200:
		return _catalog_failure("The archive is unavailable. Using the saved version list; installed builds still work offline.",silent)
	var raw=JSON.parse_string(body.get_string_from_utf8())
	if not raw is Dictionary or not valid_manifest(raw): return _catalog_failure("The archive returned an invalid version list.",silent)
	var new_versions: Array=[]
	for entry in raw.versions:
		if version(str(entry.id)).is_empty(): new_versions.append(str(entry.id))
	var modified=JSON.stringify(raw)!=JSON.stringify(manifest)
	if _atomic_json(root_directory.path_join("manifest.json"),raw)!=OK:
		return _catalog_failure("Cannot save the updated version list. Check available disk space.",silent)
	manifest=raw; last_catalog_error=""
	catalog_etag=""
	for header in headers:
		if header.to_lower().begins_with("etag:"): catalog_etag=header.substr(5).strip_edges()
	_atomic_json(root_directory.path_join("catalog-meta.json"),{"etag":catalog_etag})
	if modified: catalog_updated.emit(new_versions)
	return true
func latest_version() -> String:
	var entries=versions()
	return str(entries[0].id) if not entries.is_empty() else ""
func _end_request() -> void:
	if is_instance_valid(request): request.queue_free()
	request=null; busy=false
func cancel() -> void:
	cancel_requested=true
	if is_instance_valid(request):
		request.cancel_request()
		request.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED,0,PackedStringArray(),PackedByteArray())
func install(id: String) -> bool:
	if busy: return _fail("Another installation is in progress.")
	var entry=version(id); var package=package_for(entry)
	if not safe_id(id) or package.is_empty(): return _fail("No verified package is available for this version on this system.")
	if is_running(id): return _fail("Close this game version before reinstalling it.")
	busy=true; cancel_requested=false
	var archive=root_directory.path_join(id+".download")
	var local_path=str(package.get("local_path",""))
	if not local_path.is_empty() and safe_relative(local_path) and FileAccess.file_exists("res://"+local_path):
		progress.emit("Copying bundled build",0.1)
		var copy_result=DirAccess.copy_absolute("res://"+local_path,archive)
		if copy_result!=OK: busy=false; return _fail("Could not copy the bundled build. Check available disk space.")
	else:
		var url=str(package.get("url",""))
		if not _trusted_package_url(url): busy=false; return _fail("This package has not been published to the Slopcraft archive yet.")
		request=HTTPRequest.new(); request.download_file=archive; request.body_size_limit=MAX_PACKAGE_BYTES; request.timeout=300; request.use_threads=true; add_child(request)
		var err=request.request(url)
		if err!=OK: _end_request(); return _fail("Download could not start. Check your connection.")
		var response=await request.request_completed
		_end_request(); busy=true
		if cancel_requested or response[0]!=HTTPRequest.RESULT_SUCCESS or response[1]!=200:
			DirAccess.remove_absolute(archive); busy=false
			return _fail("Download cancelled." if cancel_requested else "Download failed. Retry when connected; your existing installation is untouched.")
	progress.emit("Verifying SHA-256",0.0)
	await get_tree().process_frame
	if FileAccess.get_sha256(archive).to_lower()!=str(package.get("sha256","")).to_lower():
		DirAccess.remove_absolute(archive); busy=false; return _fail("Checksum mismatch. The download was discarded; no files were installed.")
	var zip_check=inspect_zip(archive)
	if not zip_check.get("ok",false): DirAccess.remove_absolute(archive); busy=false; return _fail(str(zip_check.get("error","Invalid package.")))
	var destination=root_directory.path_join(id)
	var staging=root_directory.path_join(id+".staging")
	_remove_tree(staging)
	if DirAccess.make_dir_recursive_absolute(staging)!=OK: busy=false; return _fail("Cannot create the installation folder.")
	var disk=DirAccess.open(root_directory)
	if disk!=null and disk.get_space_left()>0 and disk.get_space_left()<int(zip_check.bytes)+32*1024*1024:
		busy=false; return _fail("Not enough disk space to install this version.")
	var reader=ZIPReader.new()
	if reader.open(archive)!=OK: busy=false; return _fail("Cannot open the verified package.")
	var files=reader.get_files(); var done=0
	for relative in files:
		if cancel_requested:
			reader.close(); _remove_tree(staging); DirAccess.remove_absolute(archive); busy=false; return _fail("Installation cancelled.")
		if not safe_relative(relative): reader.close(); _remove_tree(staging); busy=false; return _fail("Unsafe archive path rejected.")
		var target=staging.path_join(relative)
		if relative.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
		else:
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var file=FileAccess.open(target,FileAccess.WRITE)
			if file==null: reader.close(); _remove_tree(staging); busy=false; return _fail("Could not write the installation. Check disk space and folder permissions.")
			file.store_buffer(reader.read_file(relative)); file.flush(); var error=file.get_error(); file.close()
			if error!=OK: reader.close(); _remove_tree(staging); busy=false; return _fail("The disk could not finish writing this installation.")
		done+=1; progress.emit("Installing",float(done)/files.size())
		await get_tree().process_frame
	reader.close()
	var executable=str(package.get("executable",""))
	if not safe_relative(executable) or not FileAccess.file_exists(staging.path_join(executable)):
		_remove_tree(staging); busy=false; return _fail("The package is missing its game executable.")
	if OS.get_name()!="Windows": FileAccess.set_unix_permissions(staging.path_join(executable),493)
	var backup=root_directory.path_join(id+".previous")
	_remove_tree(backup)
	if DirAccess.dir_exists_absolute(destination):
		if DirAccess.rename_absolute(destination,backup)!=OK: busy=false; return _fail("Could not replace the previous installation.")
	if DirAccess.rename_absolute(staging,destination)!=OK:
		if DirAccess.dir_exists_absolute(backup): DirAccess.rename_absolute(backup,destination)
		busy=false; return _fail("Installation could not be completed. The previous build was restored.")
	installed[id]={"executable":executable,"sha256":package.sha256,"installed_at":Time.get_datetime_string_from_system(),"save_schema":entry.get("save_schema",2),"entry":entry.duplicate(true)}
	if _atomic_json(root_directory.path_join("installed.json"),installed)!=OK:
		busy=false; return _fail("Build extracted, but installation registration failed. Retry to register it.")
	_remove_tree(backup); DirAccess.remove_absolute(archive)
	busy=false; progress.emit("Ready to play",1); changed.emit(); return true
func launch(id: String,extra_arguments: PackedStringArray=[],extra_user_arguments: PackedStringArray=[]) -> int:
	if not is_installed(id): _fail("Install this version first."); return -1
	if is_running(id): _fail("This version is already running."); return -1
	if not valid_player_name(str(settings.player_name)): _fail("Player name must contain 3–24 letters, numbers or underscores."); return -1
	var executable=ProjectSettings.globalize_path(root_directory.path_join(id).path_join(str(installed[id].executable)))
	var data=ProjectSettings.globalize_path(root_directory.path_join("game-data").path_join(id))
	DirAccess.make_dir_recursive_absolute(data)
	var arguments: PackedStringArray=[]
	if bool(settings.fullscreen): arguments.append("--fullscreen")
	arguments.append_array(extra_arguments)
	arguments.append_array(["--","--player-name",str(settings.player_name),"--data-dir",data])
	if FileAccess.file_exists(str(settings.skin_path)): arguments.append_array(["--skin",ProjectSettings.globalize_path(str(settings.skin_path))])
	arguments.append_array(extra_user_arguments)
	var pid=OS.create_process(executable,arguments,false)
	if pid<=0: _fail("The game could not start. Reinstall this build or check OS application permissions."); return -1
	running[id]=pid; changed.emit(); return pid
func uninstall(id: String) -> bool:
	if busy or not safe_id(id): return _fail("Cannot remove this version right now.")
	if is_running(id): return _fail("Close this game version before removing it.")
	if _remove_tree(root_directory.path_join(id))!=OK: return _fail("Could not remove all game files.")
	installed.erase(id); _atomic_json(root_directory.path_join("installed.json"),installed)
	changed.emit(); return true
func save_settings() -> Error:
	return _atomic_json(root_directory.path_join("settings.json"),settings)
static func valid_player_name(value: String) -> bool:
	if value.length()<3 or value.length()>24: return false
	for c in value:
		if not ((c>="A" and c<="Z") or (c>="a" and c<="z") or (c>="0" and c<="9") or c=="_"): return false
	return true
static func safe_id(value: String) -> bool:
	if value.is_empty() or value.length()>40 or value in [".","..","game-data"]: return false
	for c in value:
		if not ((c>="A" and c<="Z") or (c>="a" and c<="z") or (c>="0" and c<="9") or c in ["-","_","."]): return false
	return true
static func safe_relative(value: String) -> bool:
	if value.is_empty() or value.is_absolute_path() or "\\" in value or ":" in value or value.to_utf8_buffer().has(0): return false
	for segment in value.trim_suffix("/").split("/"):
		if segment in ["",".",".."] or segment.ends_with(".") or segment.ends_with(" "): return false
	return true
static func valid_manifest(value: Dictionary) -> bool:
	if value.get("schema",0)!=1 or not value.get("versions") is Array or value.versions.size()>2000: return false
	var seen={}
	for entry in value.versions:
		if not entry is Dictionary or not safe_id(str(entry.get("id",""))) or seen.has(entry.id): return false
		seen[entry.id]=true
		if not entry.get("category","") in ["snapshot","release","archive"] or not entry.get("packages",{}) is Dictionary: return false
		for package in entry.get("packages",{}).values():
			if not package is Dictionary or not safe_relative(str(package.get("executable",""))): return false
			var checksum=str(package.get("sha256",""))
			if checksum.length()!=64 or not checksum.is_valid_hex_number(false): return false
	return true
static func _trusted_package_url(url: String) -> bool:
	return url.begins_with("https://github.com/SloppistGames/Slopcraft2/releases/download/")
static func inspect_zip(path: String) -> Dictionary:
	var f=FileAccess.open(path,FileAccess.READ)
	if f==null: return {"ok":false,"error":"Cannot read the downloaded archive."}
	var length=f.get_length()
	if length<22 or length>MAX_PACKAGE_BYTES: return {"ok":false,"error":"Package size is invalid."}
	var start=maxi(0,length-65557); f.seek(start); var tail=f.get_buffer(length-start); var eocd=-1
	for i in range(tail.size()-22,-1,-1):
		if tail.decode_u32(i)==0x06054b50 and i+22+tail.decode_u16(i+20)==tail.size(): eocd=i; break
	if eocd<0: return {"ok":false,"error":"ZIP directory is missing."}
	var count=tail.decode_u16(eocd+10); var central_size=tail.decode_u32(eocd+12); var offset=tail.decode_u32(eocd+16)
	if count<1 or count>10000 or offset+central_size>length or tail.decode_u16(eocd+4)!=0: return {"ok":false,"error":"Unsupported ZIP directory."}
	f.seek(offset); var total=0; var names={}
	for i in count:
		if f.get_position()+46>length or f.get_32()!=0x02014b50: return {"ok":false,"error":"Damaged ZIP entry."}
		f.get_16(); f.get_16(); var flags=f.get_16(); f.get_16(); f.get_16(); f.get_16(); f.get_32(); f.get_32()
		var unpacked=f.get_32(); var name_size=f.get_16(); var extra=f.get_16(); var comment=f.get_16(); f.get_16(); f.get_16(); var attributes=f.get_32(); f.get_32()
		if flags&1 or unpacked>256*1024*1024 or ((attributes>>16)&61440)==40960: return {"ok":false,"error":"Encrypted, oversized or linked ZIP entry rejected."}
		var name=f.get_buffer(name_size).get_string_from_utf8()
		if not safe_relative(name) or names.has(name.to_lower()): return {"ok":false,"error":"Unsafe or duplicate archive path rejected."}
		names[name.to_lower()]=true; total+=unpacked
		if total>MAX_EXTRACT_BYTES: return {"ok":false,"error":"Package expands beyond the install limit."}
		f.seek(f.get_position()+extra+comment)
	f.close(); return {"ok":true,"bytes":total}
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f=FileAccess.open(path,FileAccess.READ)
	if f==null or f.get_length()>2*1024*1024: return {}
	var value=JSON.parse_string(f.get_as_text()); return value if value is Dictionary else {}
static func _atomic_json(path: String,data: Dictionary) -> Error:
	var f=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null: return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data,"\t")); f.flush(); var error=f.get_error(); f.close()
	return DirAccess.rename_absolute(path+".tmp",path) if error==OK else error
static func _remove_tree(path: String) -> Error:
	if not DirAccess.dir_exists_absolute(path): return OK
	var dir=DirAccess.open(path)
	if dir==null: return ERR_CANT_OPEN
	for file in dir.get_files():
		var result=DirAccess.remove_absolute(path.path_join(file))
		if result!=OK: return result
	for folder in dir.get_directories():
		var result=DirAccess.remove_absolute(path.path_join(folder)) if dir.is_link(folder) else _remove_tree(path.path_join(folder))
		if result!=OK: return result
	return DirAccess.remove_absolute(path)
func _fail(message: String) -> bool:
	last_error=message; failure.emit(message); return false
