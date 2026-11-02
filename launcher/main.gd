extends Control
const INK=Color("1e201e")
const PANEL=Color("292c28")
const MUTED=Color("a1ada1")
const TEXT=Color("f0f3ec")
const GREEN=Color("78d78a")
var backend: LauncherBackend
var content: VBoxContainer
var navigation: VBoxContainer
var status: Label
var progress_bar: ProgressBar
var selected=""
var page="Play"
var play_button: Button
var skin_editor: Control
var backdrop: TextureRect
var body_margin: MarginContainer
var profile_name: Label
var tabs: Dictionary = {}
func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(960,680))
	backend=LauncherBackend.new(); add_child(backend)
	backend.changed.connect(_refresh_page)
	backend.catalog_updated.connect(_catalog_changed)
	backend.auto_refresh_enabled=not "--offline" in OS.get_cmdline_user_args()
	selected=str(backend.settings.get("preferred_version","latest"))
	if selected=="latest" or backend.version(selected).is_empty(): selected=backend.latest_version()
	backend.failure.connect(func(message): status.text=message; status.modulate=Color("efba92"))
	backend.progress.connect(func(phase,amount): status.text=phase; status.modulate=MUTED; progress_bar.value=amount*100; progress_bar.visible=backend.busy; if is_instance_valid(play_button): play_button.disabled=backend.busy)
	_build_shell(); _refresh_page()
	if backend.auto_refresh_enabled: backend.refresh(true)
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_IN and is_instance_valid(backend) and backend.auto_refresh_enabled and Time.get_unix_time_from_system()-backend.last_catalog_check>30:
		backend.refresh(true)
func _catalog_changed(new_versions: Array) -> void:
	if str(backend.settings.get("preferred_version","latest"))=="latest": selected=backend.latest_version()
	# Background catalog refresh never discards unsaved skin or preference edits.
	if page in ["Play","Versions","Changelog"]: _refresh_page()
	if not new_versions.is_empty():
		status.text="New build available: "+", ".join(new_versions)+". Choose it in Installations."
		status.modulate=GREEN
func style(color: Color,border: Color=Color.TRANSPARENT,radius: int=5) -> StyleBoxFlat:
	var s=StyleBoxFlat.new(); s.bg_color=color; s.border_color=border; s.set_border_width_all(1); s.set_corner_radius_all(radius); s.content_margin_left=18; s.content_margin_right=18; s.content_margin_top=16; s.content_margin_bottom=16
	return s
func label(text: String,size: int=16,color: Color=TEXT) -> Label:
	var l=Label.new(); l.text=text; l.add_theme_font_size_override("font_size",size); l.add_theme_color_override("font_color",color); return l
func _button_style(fill: Color,border: Color=Color.TRANSPARENT,radius: int=4) -> StyleBoxFlat:
	var result=style(fill,border,radius)
	result.content_margin_left=14; result.content_margin_right=14; result.content_margin_top=8; result.content_margin_bottom=8
	return result
func button(text: String,callback: Callable,accent: bool=false) -> Button:
	var b=Button.new(); b.text=text; b.custom_minimum_size.y=42; b.add_theme_font_size_override("font_size",15)
	b.add_theme_stylebox_override("normal",_button_style(Color("148348") if accent else Color("343a33")))
	b.add_theme_stylebox_override("hover",_button_style(Color("1b9b55") if accent else Color("414b3f"),Color("657c60")))
	b.add_theme_stylebox_override("pressed",_button_style(Color("0e6636") if accent else Color("252c24"),GREEN))
	b.add_theme_stylebox_override("disabled",_button_style(Color("2c382f"),Color("405343")))
	var focus=StyleBoxFlat.new(); focus.bg_color=Color.TRANSPARENT; focus.border_color=GREEN; focus.set_border_width_all(2); focus.set_corner_radius_all(4)
	b.add_theme_stylebox_override("focus",focus)
	b.add_theme_color_override("font_color",TEXT); b.add_theme_color_override("font_hover_color",Color.WHITE); b.add_theme_color_override("font_pressed_color",TEXT)
	b.add_theme_color_override("font_disabled_color",Color("a1b0a0")); b.pressed.connect(callback); return b
func _nav_button(text: String,callback: Callable,selected_game: bool=false) -> Button:
	var b=button(text,callback)
	b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y=44
	b.add_theme_font_size_override("font_size",14)
	var normal=_button_style(Color("30372e") if selected_game else Color.TRANSPARENT,Color("56654e") if selected_game else Color.TRANSPARENT,0)
	if selected_game:
		normal.border_color=GREEN; normal.border_width_left=3; normal.border_width_right=0; normal.border_width_top=0; normal.border_width_bottom=0
	b.add_theme_stylebox_override("normal",normal)
	b.add_theme_stylebox_override("hover",_button_style(Color("30372e"),Color.TRANSPARENT,0))
	return b
func _profile_avatar() -> Control:
	var frame=PanelContainer.new(); frame.custom_minimum_size=Vector2(36,36)
	var frame_style=style(Color("323e30"),Color("53634c"),0); frame_style.set_content_margin_all(3); frame.add_theme_stylebox_override("panel",frame_style)
	var skin: Image=load("res://player/player_model.gd").default_skin_image()
	var path=str(backend.settings.get("skin_path",""))
	if not path.is_empty() and FileAccess.file_exists(path):
		var supplied=Image.load_from_file(path)
		if supplied!=null and supplied.get_size()==Vector2i(64,64): skin=supplied
	var texture=ImageTexture.create_from_image(skin)
	var face=TextureRect.new(); face.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; face.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var region=AtlasTexture.new(); region.atlas=texture; region.region=Rect2(8,8,8,8); face.texture=region; frame.add_child(face)
	var outer=TextureRect.new(); outer.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; outer.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST; outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer=AtlasTexture.new(); layer.atlas=texture; layer.region=Rect2(40,8,8,8); outer.texture=layer; face.add_child(outer)
	return frame
func _build_shell() -> void:
	var bg=ColorRect.new(); bg.color=INK; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var row=HBoxContainer.new(); row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); row.add_theme_constant_override("separation",1); add_child(row)
	var rail=PanelContainer.new(); rail.custom_minimum_size.x=180
	var rail_style=style(Color("171a17"),Color("10130f"),0); rail_style.content_margin_left=12; rail_style.content_margin_right=12; rail_style.content_margin_top=18; rail_style.content_margin_bottom=14
	rail.add_theme_stylebox_override("panel",rail_style); row.add_child(rail)
	navigation=VBoxContainer.new(); navigation.add_theme_constant_override("separation",5); rail.add_child(navigation)
	var avatar_row=HBoxContainer.new(); avatar_row.add_theme_constant_override("separation",10); navigation.add_child(avatar_row)
	avatar_row.add_child(_profile_avatar())
	var profile=VBoxContainer.new(); profile.size_flags_horizontal=Control.SIZE_EXPAND_FILL; profile.add_theme_constant_override("separation",1); avatar_row.add_child(profile)
	profile_name=label(str(backend.settings.player_name),14); profile_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; profile_name.size_flags_horizontal=Control.SIZE_EXPAND_FILL; profile.add_child(profile_name)
	profile.add_child(label("Local player",11,MUTED))
	var spacer=Control.new(); spacer.custom_minimum_size.y=22; navigation.add_child(spacer)
	navigation.add_child(_nav_button("Home",func(): page="Play"; _refresh_page()))
	navigation.add_child(_nav_button("SLOPCRAFT 2",func(): page="Play"; _refresh_page(),true))
	var genre=label("VOXEL SURVIVAL",9,MUTED); genre.custom_minimum_size.y=26; genre.vertical_alignment=VERTICAL_ALIGNMENT_CENTER; navigation.add_child(genre)
	var bottom=Control.new(); bottom.size_flags_vertical=Control.SIZE_EXPAND_FILL; navigation.add_child(bottom)
	navigation.add_child(_nav_button("What’s new",func(): page="Changelog"; _refresh_page()))
	navigation.add_child(_nav_button("Settings",func(): page="Settings"; _refresh_page()))
	navigation.add_child(label("SLOPCRAFT LAUNCHER",9,MUTED.darkened(.15)))
	var right=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; right.add_theme_constant_override("separation",0); row.add_child(right)
	var header=MarginContainer.new(); header.add_theme_constant_override("margin_left",26); header.add_theme_constant_override("margin_right",20); header.add_theme_constant_override("margin_top",15); header.add_theme_constant_override("margin_bottom",0); right.add_child(header)
	var header_box=VBoxContainer.new(); header_box.add_theme_constant_override("separation",1); header.add_child(header_box)
	header_box.add_child(label("SLOPCRAFT 2  /  LAUNCHER",11,TEXT))
	var tab_row=HBoxContainer.new(); tab_row.add_theme_constant_override("separation",9); header_box.add_child(tab_row)
	for item in [["Play","Play"],["Installations","Versions"],["Skins","Skin studio"],["Patch notes","Changelog"]]:
		var destination=str(item[1]); var tab=button(str(item[0]),func(): page=destination; _refresh_page())
		tab.custom_minimum_size.y=39; tab.add_theme_font_size_override("font_size",15)
		tab.add_theme_stylebox_override("normal",_button_style(INK,Color.TRANSPARENT,0)); tab.add_theme_stylebox_override("hover",_button_style(Color("30372d"),Color.TRANSPARENT,0)); tabs[destination]=tab; tab_row.add_child(tab)
	var tab_space=Control.new(); tab_space.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tab_row.add_child(tab_space)
	var refresh=button("↻",func(): backend.refresh()); refresh.custom_minimum_size=Vector2(38,36); refresh.add_theme_font_size_override("font_size",20); refresh.tooltip_text="Refresh available versions"; tab_row.add_child(refresh)
	var scroll=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; right.add_child(scroll)
	body_margin=MarginContainer.new(); body_margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(body_margin)
	content=VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",18); body_margin.add_child(content)
	progress_bar=ProgressBar.new(); progress_bar.custom_minimum_size.y=4; progress_bar.show_percentage=false; progress_bar.visible=false; progress_bar.add_theme_stylebox_override("fill",style(Color("168b49"),Color.TRANSPARENT,0)); right.add_child(progress_bar)
	var footer=MarginContainer.new(); footer.add_theme_constant_override("margin_left",16); footer.add_theme_constant_override("margin_right",16); footer.add_theme_constant_override("margin_top",7); footer.add_theme_constant_override("margin_bottom",7); right.add_child(footer)
	status=label("Ready. Installed versions are available offline.",11,MUTED); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; footer.add_child(status)
func _refresh_page() -> void:
	if content==null: return
	profile_name.text=str(backend.settings.player_name)
	profile_name.tooltip_text=profile_name.text
	for key in tabs:
		tabs[key].add_theme_color_override("font_color",GREEN if key==page else TEXT)
		var tab_style=_button_style(INK,Color.TRANSPARENT,0)
		if key==page:
			tab_style.border_color=GREEN; tab_style.border_width_left=0; tab_style.border_width_right=0; tab_style.border_width_top=0; tab_style.border_width_bottom=2
		tabs[key].add_theme_stylebox_override("normal",tab_style)
	for side in ["left","right","top","bottom"]: body_margin.add_theme_constant_override("margin_"+side,0 if page=="Play" else 24)
	content.add_theme_constant_override("separation",0 if page=="Play" else 18)
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	play_button=null; skin_editor=null
	match page:
		"Play": _play_page()
		"Versions": _versions_page()
		"Skin studio": _skin_page()
		"Changelog": _changelog_page()
		"Settings": _settings_page()
func card(parent: Node=content) -> VBoxContainer:
	var p=PanelContainer.new(); p.add_theme_stylebox_override("panel",style(PANEL,Color("3b4437"))); parent.add_child(p)
	var box=VBoxContainer.new(); box.add_theme_constant_override("separation",12); p.add_child(box); return box
func heading(title: String,subtitle: String) -> void:
	content.add_child(label(title,32)); var sub=label(subtitle,15,MUTED); sub.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; content.add_child(sub)
func _play_page() -> void:
	var hero=Control.new(); hero.custom_minimum_size.y=400; content.add_child(hero)
	var dark=ColorRect.new(); dark.color=Color("304137"); dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hero.add_child(dark)
	if ResourceLoader.exists("res://assets/landscape.png"):
		backdrop=TextureRect.new(); backdrop.texture=load("res://assets/landscape.png"); backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED; backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); hero.add_child(backdrop)
	var shade=ColorRect.new(); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient=Shader.new(); gradient.code="shader_type canvas_item; void fragment(){ COLOR=vec4(0.025,0.035,0.02,0.07+smoothstep(0.35,1.0,UV.y)*0.72); }"
	var tint=ShaderMaterial.new(); tint.shader=gradient; shade.material=tint; hero.add_child(shade)
	var logo=TextureRect.new(); logo.texture=load("res://assets/logo.png"); logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.anchor_left=.25; logo.anchor_right=.75; logo.offset_top=-26; logo.offset_bottom=220; hero.add_child(logo)
	var selected_entry=backend.version(selected)
	var overline=label(str(selected_entry.get("category","snapshot")).to_upper()+" "+selected,12,GREEN); overline.position=Vector2(28,286); hero.add_child(overline)
	var headline=label(str(selected_entry.get("title","Slopcraft 2")).to_upper(),29,TEXT); headline.anchor_right=1.0; headline.offset_left=26; headline.offset_right=-26; headline.offset_top=311; headline.offset_bottom=350; headline.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; headline.tooltip_text=str(selected_entry.get("title","Slopcraft 2")); headline.add_theme_font_override("font",load("res://assets/pixel.ttf")); hero.add_child(headline)
	var subtitle=label("Deeper adventures. New horizons. Your next chapter.",15,TEXT); subtitle.position=Vector2(28,355); hero.add_child(subtitle)
	var bar=PanelContainer.new(); bar.add_theme_stylebox_override("panel",style(Color("222421"),Color("141713"),0)); content.add_child(bar)
	var row=HBoxContainer.new(); row.add_theme_constant_override("separation",18); row.alignment=BoxContainer.ALIGNMENT_CENTER; bar.add_child(row)
	var selector=OptionButton.new(); selector.custom_minimum_size=Vector2(220,48); selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL; selector.add_theme_font_size_override("font_size",14); selector.add_theme_stylebox_override("normal",_button_style(Color("1b201a"),Color("3b4537"),3)); row.add_child(selector)
	var entries=backend.versions()
	selector.add_item("Latest available  "+backend.latest_version()); selector.set_item_metadata(0,"latest")
	for i in entries.size():
		var entry: Dictionary=entries[i]; selector.add_item(str(entry.category).capitalize()+"  "+str(entry.id)); selector.set_item_metadata(i+1,str(entry.id))
		if str(entry.id)==str(backend.settings.get("preferred_version","latest")): selector.select(i+1)
	selector.item_selected.connect(func(index):
		var choice=str(selector.get_item_metadata(index)); backend.settings.preferred_version=choice; backend.save_settings()
		selected=backend.latest_version() if choice=="latest" else choice; _refresh_page()
	)
	var entry=backend.version(selected); var downloadable=not backend.package_for(entry).is_empty(); var installed=backend.is_installed(selected)
	var caption="PLAY" if installed else "DOWNLOAD" if downloadable else "IN DEVELOPMENT"
	play_button=button(caption,func():
		if backend.is_installed(selected):
			var pid=backend.launch(selected)
			if pid>0: status.text="Game launched. Your launcher stays here."; status.modulate=GREEN
		else:
			await backend.install(selected)
			_refresh_page()
	,true)
	play_button.custom_minimum_size=Vector2(248,56); play_button.add_theme_font_override("font",load("res://assets/pixel.ttf")); play_button.add_theme_font_size_override("font_size",20)
	play_button.add_theme_stylebox_override("normal",_button_style(Color("07883f"),Color("135c30"),0)); play_button.add_theme_stylebox_override("disabled",_button_style(Color("2c4031"),Color("53614f"),0)); play_button.add_theme_color_override("font_color",Color.WHITE)
	play_button.disabled=backend.busy or (not installed and not downloadable); row.add_child(play_button)
	var profile=label(str(backend.settings.player_name),13,TEXT); profile.custom_minimum_size.x=220; profile.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; profile.size_flags_horizontal=Control.SIZE_EXPAND_FILL; profile.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(profile)
	var news=MarginContainer.new(); news.add_theme_constant_override("margin_left",28); news.add_theme_constant_override("margin_right",28); news.add_theme_constant_override("margin_top",18); news.add_theme_constant_override("margin_bottom",16); content.add_child(news)
	var news_box=VBoxContainer.new(); news_box.add_theme_constant_override("separation",10); news.add_child(news_box)
	news_box.add_child(label("YOUR NEXT ADVENTURE STARTS HERE",16,TEXT))
	var description=label(str(entry.get("description","Choose a version to begin.")),14,MUTED); description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; news_box.add_child(description)
	var actions=HBoxContainer.new(); actions.add_theme_constant_override("separation",16); news_box.add_child(actions)
	actions.add_child(button("Read patch notes",func(): page="Changelog"; _refresh_page()))
	actions.add_child(button("Customize your skin",func(): page="Skin studio"; _refresh_page()))
	news_box.add_child(label("No stable release available yet. Development snapshots are clearly marked.",11,MUTED))
func _versions_page() -> void:
	heading("Your version library","Install snapshots side by side. Removing a build keeps its worlds and player data.")
	for category in ["release","snapshot","archive"]:
		content.add_child(label({"release":"LATEST RELEASE","snapshot":"DEVELOPMENT SNAPSHOTS","archive":"ARCHIVED VERSIONS"}[category],13,GREEN))
		var entries=backend.versions(category)
		if entries.is_empty(): content.add_child(label("No stable release available yet." if category=="release" else "No archived builds have been published yet.",14,MUTED))
		for entry in entries:
			var box=card(); var row=HBoxContainer.new(); box.add_child(row)
			var title=label(str(entry.id)+"  /  "+str(entry.get("title","Slopcraft 2")),21); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(title)
			row.add_child(button("Select",func(): selected=str(entry.id); page="Play"; _refresh_page()))
			if backend.is_installed(str(entry.id)):
				row.add_child(button("Remove",func(): _confirm_remove(str(entry.id))))
			box.add_child(label(str(entry.get("date",""))+" · "+("Installed" if backend.is_installed(str(entry.id)) else "Available" if not backend.package_for(entry).is_empty() else "Not yet published"),13,MUTED))
func _confirm_remove(id: String) -> void:
	var dialog=ConfirmationDialog.new(); dialog.title="Remove "+id+"?"; dialog.dialog_text="Only this build’s program files will be removed. Your worlds and skins are kept."; add_child(dialog)
	dialog.confirmed.connect(func(): backend.uninstall(id); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(500,160))
func _changelog_page() -> void:
	heading("The changelog","A record of the things that changed. Select another build from Installations to see its history.")
	var entry=backend.version(selected); content.add_child(label("SLOPCRAFT 2  /  "+selected,21,GREEN))
	var changes: Dictionary=entry.get("changelog",{})
	for category in changes:
		var box=card(); box.add_child(label(str(category),19))
		for note in changes[category]:
			var text=label("•  "+str(note),14,MUTED); text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(text)
	if changes.is_empty(): content.add_child(label("No changelog has been published for this version.",14,MUTED))
func _settings_page() -> void:
	heading("Make it yours","Local player settings. No online account required.")
	var box=card(); box.add_child(label("PLAYER NAME",13,GREEN))
	var name_input=LineEdit.new(); name_input.text=str(backend.settings.player_name); name_input.max_length=24; name_input.custom_minimum_size.y=46; box.add_child(name_input)
	box.add_child(label("3–24 letters, numbers or underscores",12,MUTED))
	var fullscreen=CheckButton.new(); fullscreen.text="Start game in fullscreen"; fullscreen.button_pressed=bool(backend.settings.fullscreen); box.add_child(fullscreen)
	box.add_child(button("Save preferences",func():
		if not LauncherBackend.valid_player_name(name_input.text): status.text="Use 3–24 letters, numbers or underscores."; return
		backend.settings.player_name=name_input.text; backend.settings.fullscreen=fullscreen.button_pressed
		status.text="Preferences saved." if backend.save_settings()==OK else "Could not save preferences. Check disk space."
	,true))
	var storage=card(); storage.add_child(label("WORLD STORAGE",13,GREEN))
	var note=label("Each version has its own world folder to protect saves when switching between incompatible versions. Use the game’s Export / Import tools to move a world safely.",14,MUTED); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; storage.add_child(note)
	storage.add_child(label("New builds are checked at startup, every five minutes, and when you return to the launcher.",13,MUTED))
	storage.add_child(button("Open library folder",func(): OS.shell_open(ProjectSettings.globalize_path(backend.root_directory))))
func _skin_page() -> void:
	heading("Skin studio","Every pixel tells a story. Your saved skin appears in the game.")
	if ResourceLoader.exists("res://skin_editor.gd"):
		skin_editor=load("res://skin_editor.gd").new(); content.add_child(skin_editor); skin_editor.setup(backend)
	else: content.add_child(label("Skin studio is still being integrated into this development build.",14,MUTED))
