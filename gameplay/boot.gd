extends Control

const Packs := preload("res://hongyuan/content_packs.gd")
const ContentOverlay := preload("res://hongyuan/ui/content_overlay.gd")
const PrefetchNotice := preload("res://hongyuan/ui/prefetch_notice.gd")
const Checkpoint := preload("res://hongyuan/checkpoint.gd")
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")
const ASSET_ROOT := "res://hongyuan/assets/"
const SPLASH := "round1/common/splash_1108.png"
const INSCRIPTION := "round1/common/title_inscription.png"
const LOVE_COVER_HEADING := "round1/common/love_cover_heading.png"
const LOVE_COVER_NOTE := "round1/common/love_cover_note.png"
const TOWN_TITLE_SCENE := "res://scripts/title_screen.gd"

const CANVAS := Vector2(360, 640)
const PAPER := Color("#fff0d6")
const SPLASH_BG := Color("#321e2b")
const OPENING_TITLE_REGION := Rect2(184, 0, 712, 270)
const BUTTON_TYPE := "round1/common/menu_labels.png"
const ACTION_LABELS := {
	"wedding": "去婚礼现场", "replay": "回顾爱情篇", "village": "去裳泓村",
	"resume": "继续游戏", "restart": "重新开始", "cancel": "取消", "erase": "确定重新开始",
	"start": "进入游戏", "home": "回到首页", "back_cover": "返回封面",
}
const OPENING_ACTION_SIZE := Vector2(184, 50)
const MARGIN := 22.0
const RESUME_PANEL_PAD := 10.0
const RESTART_PROMPT_H := 57.0
const ALBUM_COMPACT := "round1/common/completion_album_compact.png"
const ALBUM_WIDE := "round1/common/completion_album_wide.png"
const ALBUM_NOTE := "round1/common/completion_album_note.png"
const ALBUM_BASE := Color("#261f2e")
const ALBUM_MID := Color("#332633")
const ALBUM_BUTTON := Color("#eed0a3")
const ALBUM_INK := Color("#422c32")
const ALBUM_LIGHT := Color("#f3dac1")

static var entered_web_home := false
var menu_buttons: Dictionary = {}
var opening_art_end := 0.0
var opening_title := Rect2()
var opening_heading := Rect2()
var opening_note := Rect2()
var opening_credit := Label.new()
var resume_panel := Rect2()
var album_art := Rect2()
var album_note := Rect2()
var share_button: Button

var completed := false
var busy := false
var pending_route := ""
var overlay: Control
var prefetch_notice: PrefetchNotice
var saved: Dictionary = {}
var show_menu := false
var chapter_cover := false
var confirm_restart := false
var canvas := Control.new()
var town_title: Control
var tex_cache: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.custom_minimum_size = CANVAS
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_canvas)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(canvas)
	resized.connect(_fit_canvas)

	if not ProjectSettings.get_setting("application/hongyuan/enabled", true):
		get_tree().change_scene_to_file.call_deferred("res://ayu_home/v4/phone_boot.tscn")
		return

	opening_credit.text = "—— OPC制作人 @阿鱼ayu_\n抖音 & 小红书唯一 ID"
	opening_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opening_credit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opening_credit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening_credit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	opening_credit.add_theme_font_override("font", FONT)
	opening_credit.add_theme_color_override("font_color", Color("#ffe4cd"))
	opening_credit.add_theme_constant_override("line_spacing", 4)
	opening_credit.hide()
	canvas.add_child(opening_credit)
	prefetch_notice = PrefetchNotice.new()
	prefetch_notice.custom_minimum_size.x = CANVAS.x - MARGIN * 2
	for key: String in ACTION_LABELS:
		_add_action(key, key in ["wedding", "resume", "cancel", "start"])
	canvas.add_child(prefetch_notice)
	prefetch_notice.visibility_changed.connect(_fit_canvas)
	overlay = ContentOverlay.new()
	add_child(overlay)
	overlay.hide()
	overlay.desk_button.text = "返回开屏"
	overlay.retry.connect(_retry_route)
	overlay.return_to_desk.connect(func() -> void: overlay.hide())
	saved = Checkpoint.read()
	if _has_review_controls():
		if not str(saved.get("worldRoute", "")).is_empty() or bool(saved.get("loveCompleted", false)):
			Checkpoint.clear_save()
		_launch()
		return
	completed = not bool(saved.get("reviewInProgress", false)) and (
		bool(saved.get("loveCompleted", false)) or not str(saved.get("worldRoute", "")).is_empty())
	if _is_web_play() and not entered_web_home:
		entered_web_home = true
		_show_town_home()
		return
	if _has_open_invitation():
		_launch()
		return
	if completed or _is_web_play():
		show_menu = true
		chapter_cover = not completed
		if completed:
			_show_completion()
		else:
			_set_web_menu_marker("hy-welcome-menu")
		_fit_canvas()
		return
	_launch()


func _exit_tree() -> void:
	_set_web_menu_marker("")


func _is_web_play() -> bool:
	return OS.has_feature("web") and not OS.has_feature("hongyuan_wechat")


func _set_web_menu_marker(marker: String) -> void:
	if _is_web_play():
		JavaScriptBridge.eval("document.body.classList.remove('hy-town-home', 'hy-welcome-menu', 'hy-return-menu', 'hy-completion-menu')", true)
		if not marker.is_empty():
			JavaScriptBridge.eval("document.body.classList.add('%s')" % marker, true)


func _has_open_invitation() -> bool:
	return bool(saved.get("invitationOpen", false)) and str(saved.get("worldRoute", "")).is_empty()


func _show_town_home() -> void:
	show_menu = false
	canvas.hide()
	_set_web_menu_marker("hy-town-home")
	if is_instance_valid(town_title):
		town_title.reopen_menu()
	else:
		town_title = load(TOWN_TITLE_SCENE).new()
		add_child(town_title)
		town_title.setup(FONT.base_font)
		town_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		town_title.start_pressed.connect(_open_love_cover)
		town_title.boot_done()
	_fit_canvas()


func _open_love_cover() -> void:
	if busy:
		return
	busy = true
	chapter_cover = true
	confirm_restart = false
	show_menu = true
	canvas.show()
	_set_web_menu_marker("hy-welcome-menu")
	_fit_canvas()
	await town_title.leave()
	busy = false
	menu_buttons["start"].grab_focus()


func _show_completion() -> void:
	chapter_cover = false
	_prepare_album()
	_set_web_menu_marker("hy-completion-menu")
	_prefetch_village.call_deferred()
	_fit_canvas()


func _has_review_controls() -> bool:
	if not OS.has_feature("web") or OS.has_feature("hongyuan_wechat"):
		return false
	return JavaScriptBridge.eval("!!window.suqiReview && window.suqiReview.feedbackOnly !== true", true) == true


func _prefetch_village() -> void:
	prefetch_notice.offer("village-entry", Packs.route_groups("village"))


func _launch() -> void:
	get_tree().change_scene_to_file.call_deferred(_story_destination())


func _story_destination() -> String:
	var destination := "res://hongyuan/player.tscn"
	if not _is_web_play() and str(saved.get("worldRoute", "")) in ["wedding", "village"]:
		destination = "res://hongyuan/world_entry.tscn"
	return destination


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SPLASH_BG)


func _fit_canvas() -> void:
	var safe := Rect2(Vector2.ZERO, size)
	if OS.has_feature("web"):
		var viewport_js := """[
			innerWidth, innerHeight, ...['top', 'right', 'bottom', 'left'].map(
				edge => parseFloat(getComputedStyle(document.body).getPropertyValue('--hy-' + edge)) || 0
			)
		].join(',')"""
		if OS.has_feature("hongyuan_wechat"):
			viewport_js = """(() => {
				const info = wx.getSystemInfoSync();
				const w = info.windowWidth, h = info.windowHeight;
				const safe = info.safeArea || {top:0, right:w, bottom:h, left:0};
				return [w,h,safe.top,Math.max(0,w-safe.right),Math.max(0,h-safe.bottom),safe.left].join(',');
			})()"""
		var values := str(JavaScriptBridge.eval(viewport_js, true)).split(",")
		if values.size() == 6 and float(values[0]) > 0.0 and float(values[1]) > 0.0:
			var scale_to_view := size / Vector2(float(values[0]), float(values[1]))
			safe.position = Vector2(float(values[5]), float(values[2])) * scale_to_view
			safe.size -= safe.position + Vector2(float(values[3]), float(values[4])) * scale_to_view
	var fit := minf(safe.size.x / CANVAS.x, safe.size.y / CANVAS.y)
	if fit <= 0:
		return
	canvas.scale = Vector2.ONE * fit
	canvas.size = Vector2(CANVAS.x, minf(safe.size.y / fit, 820))
	canvas.position = safe.position + (safe.size - canvas.size * fit) * 0.5
	if is_instance_valid(town_title):
		var town_fit := fit / 1.5
		town_title.scale = Vector2.ONE * town_fit
		town_title.size = Vector2(540, safe.size.y / town_fit)
		town_title.position = Vector2(canvas.position.x, safe.position.y)
	_layout_menu()
	canvas.queue_redraw()
	queue_redraw()


func _layout_menu() -> void:
	if menu_buttons.is_empty():
		return
	if show_menu and completed and not chapter_cover:
		opening_credit.hide()
		_layout_album()
		return
	var height := canvas.size.y
	var compact := height < 680.0
	opening_art_end = minf(414.0, height - 238.0)
	var gap := 4.0 if compact else clampf((height - opening_art_end - 204.0) / 5.0, 7.0, 22.0)
	var title_width := 236.0
	var title_height := title_width * OPENING_TITLE_REGION.size.y / OPENING_TITLE_REGION.size.x
	opening_title = Rect2((CANVAS.x - title_width) * 0.5, 40, title_width, title_height)
	var heading_size := Vector2(106, 37) if compact else Vector2(120, 42)
	opening_heading = Rect2(Vector2((CANVAS.x - heading_size.x) * 0.5, opening_art_end + gap), heading_size)
	opening_note = Rect2(9, opening_heading.end.y + gap, 342, 55)
	opening_credit.position = Vector2(0, opening_note.end.y + 16.0)
	opening_credit.add_theme_font_size_override("font_size", 14 if compact else 12)
	opening_credit.size = Vector2(CANVAS.x, maxf(34.0, opening_credit.get_combined_minimum_size().y))
	opening_credit.visible = show_menu
	opening_credit.modulate.a = 1.0 if chapter_cover else 0.35
	var credit_to_buttons := 6.0 if compact else 9.0
	var cover_buttons_y := maxf(opening_credit.get_rect().end.y + credit_to_buttons, height - 105.0 - gap)
	if chapter_cover:
		var upper_y := opening_credit.position.y
		opening_credit.position.y = cover_buttons_y + 50.0 - opening_credit.size.y
		cover_buttons_y = upper_y
	var action_left := (CANVAS.x - OPENING_ACTION_SIZE.x) * 0.5
	var actions := Rect2(Vector2(action_left, (height - 152.0) * 0.5), OPENING_ACTION_SIZE)
	var lower := Rect2(Vector2(action_left, actions.end.y + 2.0), OPENING_ACTION_SIZE)
	resume_panel = actions.merge(lower).grow(RESUME_PANEL_PAD)
	if confirm_restart:
		resume_panel = resume_panel.grow_side(SIDE_TOP, RESTART_PROMPT_H)
	else:
		resume_panel = resume_panel.grow_side(SIDE_BOTTOM, 50.0)
	for key: String in menu_buttons:
		var button: Button = menu_buttons[key]
		button.hide()
	if show_menu:
		if chapter_cover:
			_place("start", Rect2(45, cover_buttons_y, 152, 50))
			_place("home", Rect2(205, cover_buttons_y, 110, 50))
		else:
			_place("cancel" if confirm_restart else "resume", actions)
			_place("erase" if confirm_restart else "restart", lower)
			if not confirm_restart:
				_place("back_cover", Rect2(action_left, lower.end.y + 2, OPENING_ACTION_SIZE.x, 48))


func _place(key: String, rect: Rect2) -> void:
	var button: Button = menu_buttons[key]
	button.position = rect.position
	button.size = rect.size
	button.show()


func _draw_canvas() -> void:
	if not show_menu:
		return
	if completed and not chapter_cover:
		_draw_album()
		return
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), SPLASH_BG)
	var splash := _texture(SPLASH)
	if splash:
		_draw_opening_backdrop(splash)
	var type_art := _texture(INSCRIPTION)
	if type_art:
		canvas.draw_texture_rect_region(type_art, opening_title, OPENING_TITLE_REGION)
	var heading := _texture(LOVE_COVER_HEADING)
	if heading:
		canvas.draw_texture_rect(heading, opening_heading, false)
	var note := _texture(LOVE_COVER_NOTE)
	if note:
		canvas.draw_texture_rect(note, opening_note, false)
	if not chapter_cover:
		canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(ALBUM_BASE, 0.65))
		canvas.draw_rect(resume_panel, Color(ALBUM_BASE, 0.91))
		canvas.draw_rect(resume_panel, Color(ALBUM_LIGHT, 0.28), false, 1.0)
	if confirm_restart:
		_line("确定要重新开始吗？", resume_panel.position.y + 27, 17, PAPER)
		_line("当前进度将被清除。", resume_panel.position.y + 48, 14, ALBUM_LIGHT)


func _draw_opening_backdrop(splash: Texture2D) -> void:
	var source_width := float(splash.get_width())
	var ratio := source_width / CANVAS.x
	canvas.draw_texture_rect_region(splash, Rect2(0, 0, CANVAS.x, opening_art_end),
		Rect2(0, 0, source_width, opening_art_end * ratio))
	_fade(opening_art_end - 9.0, opening_art_end, Color(SPLASH_BG, 0.0), SPLASH_BG)


func _prepare_album() -> void:
	for key: String in ["wedding", "replay", "village"]:
		var button: Button = menu_buttons[key]
		var primary := key == "wedding"
		var ink := ALBUM_INK if primary else ALBUM_LIGHT
		button.add_theme_font_size_override("font_size", 17 if primary else 14)
		if primary:
			_style_album_button(button, ALBUM_BUTTON, ink, Color("#c79772"))
			for child in button.get_children():
				if child is TextureRect:
					child.modulate = ink
		else:
			_style_album_button(button, Color.TRANSPARENT, ink, Color.TRANSPARENT)
		button.draw.connect(_draw_button_arrow.bind(button, primary, ink))
	if OS.has_feature("web") and not OS.has_feature("hongyuan_wechat"):
		var bridge := JavaScriptBridge.get_interface("suqiCompletionShare")
		if bridge == null:
			return
		share_button = Button.new()
		share_button.name = "share"
		share_button.accessibility_name = "分享并邀请朋友玩"
		share_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_album_button(share_button, Color.TRANSPARENT, ALBUM_LIGHT, Color.TRANSPARENT, 4)
		share_button.draw.connect(_draw_album_share)
		share_button.pressed.connect(_share_album)
		canvas.add_child(share_button)


func _draw_button_arrow(button: Button, primary: bool, ink: Color) -> void:
	var radius := 5.0 if primary else 4.0
	var x := button.size.x - 18.0 if primary else button.size.x * 0.5 + 51.0
	var tip := Vector2(x, button.size.y * 0.5)
	button.draw_polyline(PackedVector2Array([tip - Vector2(radius, radius), tip,
		tip - Vector2(radius, -radius)]), ink, 1.5, true)


func _draw_album_share() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#38242d82")
	background.set_corner_radius_all(4)
	share_button.draw_style_box(background, Rect2(3, 12, share_button.size.x - 6, 25))
	share_button.draw_polyline(PackedVector2Array([Vector2(17, 20), Vector2(12, 20),
		Vector2(12, 31), Vector2(23, 31), Vector2(23, 26)]), ALBUM_LIGHT, 1.3, true)
	share_button.draw_line(Vector2(17, 26), Vector2(24, 19), ALBUM_LIGHT, 1.3, true)
	share_button.draw_polyline(PackedVector2Array([Vector2(19, 19), Vector2(24, 19),
		Vector2(24, 24)]), ALBUM_LIGHT, 1.3, true)
	share_button.draw_string(FONT, Vector2(30, 29), "分享", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ALBUM_LIGHT)


func _style_album_button(button: Button, fill: Color, ink: Color, edge: Color, radius := 2) -> void:
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = edge
		box.set_corner_radius_all(radius)
		box.set_border_width_all(1)
		if state == "hover":
			box.bg_color = Color("#c9806625") if fill.a == 0.0 else fill.lightened(0.07)
		elif state == "pressed":
			box.bg_color = Color("#8e473934") if fill.a == 0.0 else fill.darkened(0.12)
		elif state == "focus":
			box.draw_center = false
			box.set_border_width_all(2)
			box.border_color = Color("#a76a50")
		button.add_theme_stylebox_override(state, box)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)


func _layout_album() -> void:
	var height := canvas.size.y
	var retry := 55.0 if prefetch_notice.visible else 0.0
	var note_top := height - 128.0
	var action_y := minf(height * 0.684, note_top - 101.0 - retry)
	var drawing_height := lerpf(394.0, 511.0, clampf(inverse_lerp(640.0, 779.0, height), 0.0, 1.0))
	album_art = Rect2(0, 0, CANVAS.x, minf(drawing_height, action_y - 15.0))
	album_note = Rect2(0, note_top, CANVAS.x, 128)
	for key: String in menu_buttons:
		menu_buttons[key].hide()
	var width := 236.0
	var left := (CANVAS.x - width) * 0.5
	_place("wedding", Rect2(left, action_y, width, 50))
	_place("replay", Rect2(left, action_y + 50.0, width * 0.5, 50))
	_place("village", Rect2(left + width * 0.5, action_y + 50.0, width * 0.5, 50))
	prefetch_notice.position = Vector2(MARGIN, action_y + 103.0)
	prefetch_notice.size.x = CANVAS.x - 2.0 * MARGIN
	if is_instance_valid(share_button):
		share_button.position = Vector2(279, 14 if height < 700 else 24)
		share_button.size = Vector2(58, 50)


func _draw_album() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), ALBUM_BASE)
	_fade(album_art.end.y - 1, canvas.size.y, ALBUM_MID, ALBUM_BASE)
	var art := _texture(ALBUM_COMPACT if canvas.size.y < 710 else ALBUM_WIDE)
	if art:
		canvas.draw_texture_rect(art, album_art, false)
	var note := _texture(ALBUM_NOTE)
	if note:
		canvas.draw_texture_rect(note, album_note, false)


func _share_album() -> void:
	if busy or overlay.visible:
		return
	var bridge := JavaScriptBridge.get_interface("suqiCompletionShare")
	if bridge == null:
		return
	bridge.open()


func _line(value: String, baseline: float, font_size: int, color: Color) -> void:
	canvas.draw_string(FONT, Vector2(0, baseline), value, HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, font_size, color)


func _fade(top: float, bottom: float, first: Color, last: Color) -> void:
	canvas.draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(CANVAS.x, top),
		Vector2(CANVAS.x, bottom), Vector2(0, bottom)]), PackedColorArray([first, first, last, last]))


func _add_action(key: String, primary: bool) -> void:
	var label: String = ACTION_LABELS[key]
	var button := Button.new()
	button.name = key
	button.accessibility_name = label
	var labels := _texture(BUTTON_TYPE)
	if labels and key not in ["start", "home", "back_cover"]:
		var artwork := AtlasTexture.new()
		artwork.atlas = labels
		artwork.region = Rect2(0, ACTION_LABELS.keys().find(key) * 96, 432, 96)
		var caption := TextureRect.new()
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.texture = artwork
		caption.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		button.add_child(caption)
		caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		caption.offset_left = -72
		caption.offset_right = 72
		caption.offset_top = -16
		caption.offset_bottom = 16
		button.button_down.connect(func() -> void: caption.offset_top = -15; caption.offset_bottom = 17)
		button.button_up.connect(func() -> void: caption.offset_top = -16; caption.offset_bottom = 16)
	else:
		button.text = label
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 20 if primary else 16)
	for state: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(3)
		box.set_border_width_all(1)
		box.border_width_bottom = 2 if primary else 1
		box.bg_color = Color("#874739") if primary else Color("#412832")
		box.border_color = Color("#ce9b65") if primary else Color("#8e6b58")
		if state == "pressed":
			box.bg_color = box.bg_color.darkened(0.20)
			box.content_margin_top = 3
		elif state == "hover":
			box.bg_color = box.bg_color.lightened(0.07)
		button.add_theme_stylebox_override(state, box)
		var color_key := "font_color" if state == "normal" else "font_" + state + "_color"
		button.add_theme_color_override(color_key, PAPER if primary else Color("#edd4b5"))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_corner_radius_all(3)
	focus.set_border_width_all(2)
	focus.border_color = Color("#ffda92")
	button.add_theme_stylebox_override("focus", focus)
	if key in ["start", "home", "resume", "restart", "cancel", "erase", "back_cover"]:
		var ink := ALBUM_INK if primary else ALBUM_LIGHT
		var fill := ALBUM_BUTTON if primary else Color.TRANSPARENT
		_style_album_button(button, fill, ink, Color("#c79772") if primary else Color.TRANSPARENT)
		button.add_theme_font_size_override("font_size", 17 if primary else 15)
		for child in button.get_children():
			if child is TextureRect:
				child.modulate = ink
		if key in ["start", "home", "resume"]:
			button.draw.connect(_draw_button_arrow.bind(button, true, ink))
	button.pressed.connect(_act.bind(key))
	canvas.add_child(button)
	button.hide()
	menu_buttons[key] = button


func _act(key: String) -> void:
	if busy or not show_menu or overlay.visible:
		return
	match key:
		"wedding", "village":
			_open_route(key)
		"replay":
			saved.erase("invitationOpen")
			saved["replayLove"] = true
			saved["reviewInProgress"] = true
			saved.revision = int(saved.get("revision", 0)) + 1
			Checkpoint.write(saved)
			get_tree().change_scene_to_file.call_deferred("res://hongyuan/player.tscn")
		"home":
			_show_town_home()
		"back_cover":
			chapter_cover = true
			_set_web_menu_marker("hy-welcome-menu")
			_fit_canvas()
			menu_buttons["start"].grab_focus()
		"start":
			if _has_open_invitation() or not Checkpoint.has_progress(saved) and not completed:
				busy = true
				_launch()
			elif completed:
				_show_completion()
			else:
				chapter_cover = false
				_set_web_menu_marker("hy-return-menu")
				_fit_canvas()
				menu_buttons["resume"].grab_focus()
		"resume":
			busy = true
			_launch()
		"restart", "cancel":
			confirm_restart = key == "restart"
			_fit_canvas()
			var next: Button = menu_buttons["cancel" if confirm_restart else "restart"]
			next.grab_focus()
		"erase":
			Checkpoint.clear_save()
			saved = {}
			get_tree().change_scene_to_file.call_deferred("res://hongyuan/player.tscn")


func _texture(name: String) -> Texture2D:
	if name.is_empty():
		return null
	if not tex_cache.has(name):
		var path := ASSET_ROOT + name
		if not ResourceLoader.exists(path) and not name.begins_with("w2/"):
			path = ASSET_ROOT + "w2/" + name
		tex_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return tex_cache[name]

func _retry_route() -> void:
	_open_route(pending_route)

func _open_route(route: String) -> void:
	if busy or route.is_empty(): return
	busy = true
	pending_route = route
	var title := "正在前往裳泓村" if route == "village" else "正在前往婚礼现场"
	if not await overlay.prepare(title, Packs.route_groups(route)):
		busy = false
		return
	saved["worldRoute"] = route
	saved["loveCompleted"] = true
	saved.revision = int(saved.get("revision", 0)) + 1
	Checkpoint.write(saved)
	get_tree().change_scene_to_file.call_deferred("res://hongyuan/world_entry.tscn")
