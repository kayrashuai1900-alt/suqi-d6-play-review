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

const CANVAS := Vector2(360, 640)
const PAPER := Color("#fff0d6")
const SPLASH_BG := Color("#321e2b")
const PHOTO_HEIGHT := 406.0
const BUTTON_TYPE := "round1/common/menu_labels.png"
const ACTION_LABELS := {
	"wedding": "去婚礼现场", "replay": "回顾爱情篇", "village": "去裳泓村",
	"resume": "继续游戏", "restart": "重新开始", "cancel": "取消", "erase": "确定重新开始",
}
const TYPE_STRIP := Vector2(360, 94)
const PRIMARY_H := 54.0
const SECONDARY_H := 52.0
const MARGIN := 22.0

var menu_buttons: Dictionary = {}
var photo_rect := Rect2()
var title_y := 0.0
var note_y := 0.0

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
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(canvas)
	resized.connect(_fit_canvas)

	if not ProjectSettings.get_setting("application/hongyuan/enabled", true):
		get_tree().change_scene_to_file.call_deferred("res://ayu_home/v4/phone_boot.tscn")
		return

	prefetch_notice = PrefetchNotice.new()
	prefetch_notice.custom_minimum_size.x = CANVAS.x - MARGIN * 2
	for key: String in ACTION_LABELS:
		_add_action(key, key in ["wedding", "resume", "cancel"])
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
	if bool(saved.get("invitationOpen", false)) and str(saved.get("worldRoute", "")).is_empty():
		_launch()
		return
	completed = not bool(saved.get("reviewInProgress", false)) and (
		bool(saved.get("loveCompleted", false)) or not str(saved.get("worldRoute", "")).is_empty())
	var web_trial := OS.has_feature("web") and not OS.has_feature("hongyuan_wechat")
	if completed or (web_trial and Checkpoint.has_progress(saved)):
		show_menu = true
		if web_trial:
			JavaScriptBridge.eval("document.body.classList.add('hy-return-menu')", true)
		if completed:
			_prefetch_village.call_deferred()
		_fit_canvas()
		return
	_launch()


func _exit_tree() -> void:
	if show_menu and OS.has_feature("web") and not OS.has_feature("hongyuan_wechat"):
		JavaScriptBridge.eval("document.body.classList.remove('hy-return-menu')", true)


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
	_layout_menu()
	canvas.queue_redraw()
	queue_redraw()


func _layout_menu() -> void:
	if menu_buttons.is_empty():
		return
	var height := canvas.size.y
	var extra := maxf(0, height - CANVAS.y)
	var retry_h := 58.0 if is_instance_valid(prefetch_notice) and prefetch_notice.visible else 0.0
	var primary_y := height - 128.0 - minf(extra * 0.18, 33) - retry_h
	var actions := Rect2(MARGIN, primary_y, CANVAS.x - 2 * MARGIN, PRIMARY_H)
	var lower := Rect2(MARGIN, actions.end.y + 6, actions.size.x, SECONDARY_H)
	var split := (lower.size.x - 10) * 0.5
	for key: String in menu_buttons:
		var button: Button = menu_buttons[key]
		button.hide()
	if show_menu:
		if completed:
			_place("wedding", actions)
			_place("replay", Rect2(lower.position, Vector2(split, SECONDARY_H)))
			_place("village", Rect2(lower.position + Vector2(split + 10, 0), Vector2(split, SECONDARY_H)))
		else:
			_place("cancel" if confirm_restart else "resume", actions)
			_place("erase" if confirm_restart else "restart", lower)
	if is_instance_valid(prefetch_notice):
		prefetch_notice.position = Vector2(MARGIN, lower.end.y + 7)
		prefetch_notice.size.x = actions.size.x
	# Make room for a retry notice by taking space from the sky, never from the touch targets.
	var sky_pad := minf(extra * 0.49, 82)
	var picture_bottom := minf(PHOTO_HEIGHT + sky_pad, primary_y - 130.0)
	photo_rect = Rect2(0, picture_bottom - PHOTO_HEIGHT, CANVAS.x, PHOTO_HEIGHT)
	title_y = maxf(12, photo_rect.position.y + 72)
	note_y = (picture_bottom + primary_y - TYPE_STRIP.y) * 0.5 + 2


func _place(key: String, rect: Rect2) -> void:
	var button: Button = menu_buttons[key]
	button.position = rect.position
	button.size = rect.size
	button.show()


func _draw_canvas() -> void:
	if not show_menu:
		return
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), SPLASH_BG)
	var splash := _texture(SPLASH)
	if splash:
		var ratio := splash.get_width() / CANVAS.x
		var top := maxf(0, photo_rect.position.y)
		var crop := top - photo_rect.position.y
		var area := Rect2(0, top, CANVAS.x, PHOTO_HEIGHT - crop)
		canvas.draw_texture_rect_region(splash, area, Rect2(0, crop * ratio, splash.get_width(), area.size.y * ratio))
		_fade(top, top + 68, SPLASH_BG if top > 0 else Color("#321e2b70"), Color("#321e2b00"))
		_fade(photo_rect.end.y - 22, photo_rect.end.y, Color("#321e2b00"), SPLASH_BG)
	var type_art := _texture(INSCRIPTION)
	if type_art:
		var strip := Vector2(type_art.get_width(), type_art.get_height() * 0.5)
		canvas.draw_texture_rect_region(type_art, Rect2(Vector2(0, title_y), TYPE_STRIP), Rect2(Vector2.ZERO, strip))
		if not confirm_restart:
			canvas.draw_texture_rect_region(type_art, Rect2(Vector2(0, note_y), TYPE_STRIP), Rect2(Vector2(0, strip.y), strip))
	if confirm_restart:
		_line("确定要重新开始吗？", note_y + 36, 19, PAPER)
		_line("当前进度将被清除。", note_y + 65, 15, Color("#e2bfab"))
	elif completed:
		var baseline := note_y - 4
		_line("爱情篇 · 完", baseline, 12, Color("#e7c59f"))
		canvas.draw_line(Vector2(104, baseline - 4), Vector2(140, baseline - 4), Color("#966b57"))
		canvas.draw_line(Vector2(220, baseline - 4), Vector2(256, baseline - 4), Color("#966b57"))


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
	if labels:
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
		"resume":
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
