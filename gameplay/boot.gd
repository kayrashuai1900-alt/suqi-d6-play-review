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
const ALBUM_COMPACT := "round1/common/completion_album_compact.png"
const ALBUM_WIDE := "round1/common/completion_album_wide.png"
const ALBUM_NOTE := "round1/common/completion_album_note.png"
const ALBUM_PAPER := Color("#ecdbbf")
const ALBUM_MID := Color("#e8d0ad")
const ALBUM_BUTTON := Color("#843a3b")

var menu_buttons: Dictionary = {}
var photo_rect := Rect2()
var title_y := 0.0
var note_y := 0.0
var album_art := Rect2()
var album_note := Rect2()
var album_status_y := 0.0
var share_button: Button

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
			_prepare_album()
			if web_trial:
				JavaScriptBridge.eval("document.body.classList.add('hy-completion-menu')", true)
			_prefetch_village.call_deferred()
		_fit_canvas()
		return
	_launch()


func _exit_tree() -> void:
	if show_menu and OS.has_feature("web") and not OS.has_feature("hongyuan_wechat"):
		JavaScriptBridge.eval("document.body.classList.remove('hy-return-menu', 'hy-completion-menu')", true)


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
	if show_menu and completed:
		_layout_album()
		return
	var height := canvas.size.y
	var extra := maxf(0, height - CANVAS.y)
	var retry_h := 58.0 if is_instance_valid(prefetch_notice) and prefetch_notice.visible else 0.0
	var primary_y := height - 128.0 - minf(extra * 0.18, 33) - retry_h
	var actions := Rect2(MARGIN, primary_y, CANVAS.x - 2 * MARGIN, PRIMARY_H)
	var lower := Rect2(MARGIN, actions.end.y + 6, actions.size.x, SECONDARY_H)
	for key: String in menu_buttons:
		var button: Button = menu_buttons[key]
		button.hide()
	if show_menu:
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
	if completed:
		_draw_album()
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


func _prepare_album() -> void:
	for key: String in ["wedding", "replay", "village"]:
		var button: Button = menu_buttons[key]
		for child in button.get_children():
			child.hide()
		button.text = ACTION_LABELS[key]
		button.add_theme_font_size_override("font_size", 17 if key == "wedding" else 14)
		if key == "wedding":
			_style_album_button(button, ALBUM_BUTTON, PAPER, Color("#a66955"))
		else:
			_style_album_button(button, Color.TRANSPARENT, Color("#603d32"), Color.TRANSPARENT)
	if OS.has_feature("web") and not OS.has_feature("hongyuan_wechat"):
		var bridge := JavaScriptBridge.get_interface("suqiCompletionShare")
		if bridge == null:
			return
		share_button = Button.new()
		share_button.name = "share"
		share_button.text = "分享"
		share_button.accessibility_name = "分享并邀请朋友玩"
		share_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		share_button.add_theme_font_override("font", FONT)
		share_button.add_theme_font_size_override("font_size", 13)
		_style_album_button(share_button, Color("#f8ecda"), Color("#764038"), Color("#ac8064"), 22)
		share_button.pressed.connect(_share_album)
		canvas.add_child(share_button)


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
	var action_y := minf(height * 0.643, note_top - 106.0 - retry)
	var drawing_height := lerpf(375.0, 475.0, clampf(inverse_lerp(640.0, 779.0, height), 0.0, 1.0))
	album_art = Rect2(0, 0, CANVAS.x, minf(drawing_height, action_y - 25.0))
	album_note = Rect2(0, note_top, CANVAS.x, 128)
	album_status_y = action_y - 10
	for key: String in menu_buttons:
		menu_buttons[key].hide()
	var width := 260.0
	var left := (CANVAS.x - width) * 0.5
	_place("wedding", Rect2(left, action_y, width, 49))
	_place("replay", Rect2(left, action_y + 49.0, width * 0.5, 50))
	_place("village", Rect2(left + width * 0.5, action_y + 49.0, width * 0.5, 50))
	prefetch_notice.position = Vector2(MARGIN, action_y + 101.0)
	prefetch_notice.size.x = CANVAS.x - 2.0 * MARGIN
	if is_instance_valid(share_button):
		share_button.position = Vector2(285, 10 if height < 700 else 23)
		share_button.size = Vector2(53, 50)


func _draw_album() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), ALBUM_PAPER)
	_fade(album_art.end.y - 9, canvas.size.y, ALBUM_MID, ALBUM_PAPER)
	var art := _texture(ALBUM_COMPACT if canvas.size.y < 710 else ALBUM_WIDE)
	if art:
		canvas.draw_texture_rect(art, album_art, false)
	var note := _texture(ALBUM_NOTE)
	if note:
		canvas.draw_texture_rect(note, album_note, false)
	_line("爱情篇已通关", album_status_y, 12, Color("#745447"))


func _share_album() -> void:
	if busy or overlay.visible:
		return
	var bridge := JavaScriptBridge.get_interface("suqiCompletionShare")
	if bridge == null:
		return
	# Read Godot's already-rendered frame. Browser review controls and dialogs
	# are outside the canvas and cannot be baked into a friend's poster.
	var viewport := get_viewport()
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return
	var scale_to_image := Vector2(image.get_size()) / viewport.get_visible_rect().size
	var menu_rect := canvas.get_global_rect()
	var region := Rect2i(Rect2(menu_rect.position * scale_to_image, menu_rect.size * scale_to_image))
	region = region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if region.has_area():
		bridge.open(Marshalls.raw_to_base64(image.get_region(region).save_png_to_buffer()))


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
