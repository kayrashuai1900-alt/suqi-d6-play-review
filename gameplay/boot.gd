extends Control

const Packs := preload("res://hongyuan/content_packs.gd")
const ContentOverlay := preload("res://hongyuan/ui/content_overlay.gd")
const PrefetchNotice := preload("res://hongyuan/ui/prefetch_notice.gd")
const Checkpoint := preload("res://hongyuan/checkpoint.gd")
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")
const ASSET_ROOT := "res://hongyuan/assets/"
const SPLASH := "round1/common/splash_1108.png"

const CANVAS := Vector2(360, 640)
const INK := Color("#281a1a")
const RED := Color("#5e2929")
const PAPER := Color("#fff1d5")
const WHEAT := Color("#f4d495")
const GOLD := Color("#d6a456")
const SPLASH_BG := Color("#48223a")
const SPLASH_CAPTION_END := 0.83
const MENU_BOTTOM_PAD := 28.0
const MENU_GAP := 52.0
const MENU_H := 44.0

var completed := false
var busy := false
var pending_route := ""
var overlay: Control
var prefetch_notice: PrefetchNotice
var saved: Dictionary = {}
var show_menu := false
var confirm_restart := false
var canvas := Control.new()
var tex_cache: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.custom_minimum_size = CANVAS
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_on_canvas_input)
	add_child(canvas)
	resized.connect(_fit_canvas)

	if not ProjectSettings.get_setting("application/hongyuan/enabled", true):
		get_tree().change_scene_to_file.call_deferred("res://ayu_home/v4/phone_boot.tscn")
		return

	prefetch_notice = PrefetchNotice.new()
	prefetch_notice.position = Vector2(48, 606)
	prefetch_notice.custom_minimum_size.x = 264
	canvas.add_child(prefetch_notice)
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
	if bool(saved.get("invitationOpen", false)) and str(saved.get("worldRoute", "")).is_empty():
		_launch()
		return
	completed = not bool(saved.get("reviewInProgress", false)) and (
		bool(saved.get("loveCompleted", false)) or not str(saved.get("worldRoute", "")).is_empty())
	if completed:
		show_menu = true
		_prefetch_village.call_deferred()
		_fit_canvas()
		canvas.queue_redraw()
		return
	var web_trial := OS.has_feature("web") and not OS.has_feature("hongyuan_wechat")
	if web_trial and Checkpoint.has_progress(saved):
		show_menu = true
		_fit_canvas()
		canvas.queue_redraw()
		return
	_launch()


func _has_review_controls() -> bool:
	if not OS.has_feature("web") or OS.has_feature("hongyuan_wechat"):
		return false
	var bridge := JavaScriptBridge.get_interface("suqiReview")
	return bridge != null and bridge.feedbackOnly != true


func _prefetch_village() -> void:
	prefetch_notice.offer("village-entry", Packs.route_groups("village"))


func _launch() -> void:
	get_tree().change_scene_to_file.call_deferred(_story_destination())


func _story_destination() -> String:
	var destination := "res://hongyuan/player.tscn"
	var web_trial := OS.has_feature("web") and not OS.has_feature("hongyuan_wechat")
	if not web_trial and str(saved.get("worldRoute", "")) in ["wedding", "village"]:
		destination = "res://hongyuan/world_entry.tscn"
	return destination


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SPLASH_BG)
	if not show_menu:
		return
	var splash := _texture(SPLASH)
	if not splash:
		return
	var width := size.x if size.y >= size.x else CANVAS.x * canvas.scale.x
	var height := splash.get_height() * width / splash.get_width()
	var menu_top := canvas.position.y + (456.0 if completed else _primary_rect().position.y) * canvas.scale.y
	var top := minf(0.0, menu_top - 12.0 - height * SPLASH_CAPTION_END)
	draw_texture_rect(splash, Rect2((size.x - width) * 0.5, top, width, height), false)


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
	canvas.scale = Vector2.ONE * fit
	canvas.position = safe.position + (safe.size - CANVAS * fit) * 0.5
	queue_redraw()


func _draw_canvas() -> void:
	if not show_menu:
		return
	var title := "苏七镇奇缘"
	for offset: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 3)]:
		canvas.draw_string(FONT, Vector2(0, 88) + offset, title, HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 34, Color("#642e32"))
	canvas.draw_string(FONT, Vector2(0, 88), title, HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 34, WHEAT)
	canvas.draw_string(FONT, Vector2(0, 112), "爱情篇 · 宴席篇 · 裳泓篇", HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 15, PAPER)
	_draw_dedication()
	if completed:
		_pill(Rect2(48, 456, 264, MENU_H), "回顾爱情篇", 19, RED, PAPER)
		_pill(Rect2(48, 508, 264, MENU_H), "去婚礼现场", 19, RED, PAPER)
		_pill(Rect2(48, 560, 264, MENU_H), "去裳泓村", 19, RED, PAPER)
		return
	var panel := Rect2(30, 492, 300, 133)
	if confirm_restart:
		panel.position.y = 440
		panel.size.y = 185
	canvas.draw_rect(panel, Color(INK, 0.94))
	canvas.draw_rect(panel, Color(GOLD, 0.6), false, 2.0)
	if confirm_restart:
		canvas.draw_multiline_string(
			FONT,
			Vector2(40, panel.position.y + 31),
			StoryCaption.wrap_text("确定要重新开始吗？当前进度将被清除。", 280, 17),
			HORIZONTAL_ALIGNMENT_LEFT,
			280,
			17,
			-1,
			WHEAT
		)
		_pill(_primary_rect(), "确定重新开始", 19, RED, PAPER)
		_pill(_secondary_rect(), "取消", 19, Color(INK, 0.85), PAPER)
	else:
		_pill(_primary_rect(), "继续游戏", 19, RED, PAPER)
		_pill(_secondary_rect(), "重新开始", 19, Color(INK, 0.85), PAPER)


func _draw_dedication() -> void:
	canvas.draw_rect(Rect2(42, 122, 276, 68), Color(INK, 0.76))
	canvas.draw_string(FONT, Vector2(0, 139), "谨以此篇献给所有爱我和我爱的人们，", HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 13, PAPER)
	canvas.draw_string(FONT, Vector2(0, 155), "来日并不方长，愿各位都珍惜当下", HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 13, PAPER)
	canvas.draw_string(FONT, Vector2(0, 172), "—— OPC制作人 @阿鱼ayu_", HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 11, WHEAT)
	canvas.draw_string(FONT, Vector2(0, 185), "抖音 & 小红书唯一 ID", HORIZONTAL_ALIGNMENT_CENTER, CANVAS.x, 10, PAPER)


func _secondary_rect() -> Rect2:
	var y := CANVAS.y - MENU_BOTTOM_PAD - MENU_H
	return Rect2(48, y, 264, MENU_H)


func _primary_rect() -> Rect2:
	var secondary := _secondary_rect()
	return Rect2(48, secondary.position.y - MENU_GAP, 264, MENU_H)


func _on_canvas_input(event: InputEvent) -> void:
	if not show_menu or busy:
		return
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
		pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		pos = event.position
	else:
		return
	if not pressed:
		return
	if completed:
		if Rect2(48, 456, 264, MENU_H).has_point(pos):
			saved.erase("invitationOpen")
			saved["replayLove"] = true
			saved["reviewInProgress"] = true
			saved.revision = int(saved.get("revision", 0)) + 1
			Checkpoint.write(saved)
			get_tree().change_scene_to_file.call_deferred("res://hongyuan/player.tscn")
		elif Rect2(48, 508, 264, MENU_H).has_point(pos):
			_open_route("wedding")
		elif Rect2(48, 560, 264, MENU_H).has_point(pos):
			_open_route("village")
		return
	if confirm_restart:
		if _primary_rect().grow(6).has_point(pos):
			Checkpoint.clear_save()
			saved = {}
			confirm_restart = false
			get_tree().change_scene_to_file.call_deferred("res://hongyuan/player.tscn")
		elif _secondary_rect().grow(6).has_point(pos):
			confirm_restart = false
			canvas.queue_redraw()
		return
	if _primary_rect().grow(6).has_point(pos):
		_launch()
	elif _secondary_rect().grow(6).has_point(pos):
		confirm_restart = true
		canvas.queue_redraw()


func _pill(r: Rect2, text: String, font_size: int, fill: Color, fg: Color) -> void:
	canvas.draw_rect(r, fill)
	canvas.draw_rect(r, Color(GOLD, 0.6), false, 2.0)
	var asc := FONT.get_ascent(font_size)
	var desc := FONT.get_descent(font_size)
	canvas.draw_string(
		FONT,
		Vector2(r.position.x, r.position.y + (r.size.y + asc - desc) * 0.5),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x,
		font_size,
		fg
	)


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
