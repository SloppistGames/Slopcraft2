extends SceneTree
class PollBackend extends LauncherBackend:
	var polls=0
	func refresh(_silent: bool=false) -> bool:
		polls+=1; refresh_clock=0; return true
var checks=0
var failures=0
var updates: Array=[]
var errors: Array=[]
func check(ok,label):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize(): call_deferred("run")
func run():
	var b=LauncherBackend.new(); b.root_directory="user://catalog-test-%d" % Time.get_ticks_usec(); b.auto_refresh_enabled=false; root.add_child(b)
	b.catalog_updated.connect(func(ids): updates.append(ids))
	b.failure.connect(func(message): errors.append(message))
	b.manifest={"schema":1,"versions":[{"id":"0.5.0f","category":"snapshot","packages":{}}]}
	var next={"schema":1,"versions":[{"id":"0.6.0","category":"release","packages":{}},{"id":"0.5.0f","category":"snapshot","packages":{}}]}
	check(b.accept_catalog_response(0,200,["ETag: test-v2"],JSON.stringify(next).to_utf8_buffer(),true),"New catalog accepted without reinstalling launcher")
	check(b.latest_version()=="0.6.0" and updates.size()==1 and updates[0]==["0.6.0"],"Latest build and new-version signal update")
	check(b.catalog_etag=="test-v2","Response ETag retained")
	check(not b.busy,"Catalog refresh leaves installation/launch state available")
	check(b.accept_catalog_response(0,304,[],PackedByteArray(),true) and updates.size()==1,"Unchanged catalog does not rebuild UI")
	check(not b.accept_catalog_response(HTTPRequest.RESULT_CANT_CONNECT,0,[],PackedByteArray(),true) and errors.is_empty(),"Offline background check is quiet")
	check(b.latest_version()=="0.6.0","Offline check keeps last catalog")
	var corrupt={"schema":1,"versions":[{"id":"../escape","category":"release","packages":{}}]}
	check(not b.accept_catalog_response(0,200,[],JSON.stringify(corrupt).to_utf8_buffer(),false) and errors.size()==1,"Malformed update is rejected visibly on manual refresh")
	check(b.latest_version()=="0.6.0","Rejected update cannot replace good catalog")
	var restart=LauncherBackend.new(); restart.root_directory=b.root_directory; restart.auto_refresh_enabled=false; root.add_child(restart)
	check(restart.latest_version()=="0.6.0" and restart.catalog_etag=="test-v2","Downloaded catalog and validator survive restart")
	var polling=PollBackend.new(); polling.root_directory=b.root_directory; root.add_child(polling)
	polling._process(299); check(polling.polls==0,"Does not poll too frequently")
	polling._process(1); check(polling.polls==1,"Automatically checks after five minutes")
	polling.busy=true; polling._process(300); check(polling.polls==1,"Waits during an active installation")
	polling.busy=false; polling._process(1); check(polling.polls==2,"Deferred poll runs when installation finishes")
	polling.auto_refresh_enabled=false; polling._process(1000); check(polling.polls==2,"Explicit offline mode does not poll")
	var path=b.root_directory
	polling.free(); restart.free(); b.free(); await process_frame
	LauncherBackend._remove_tree(path)
	print("CATALOG UPDATES: ",checks," checks, ",failures," failures"); quit(failures)
