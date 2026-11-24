extends RefCounted
## The seal and the bottom instruction share the same hold action.
const DeskArt := preload("res://hongyuan/ui/desk_art.gd")
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
const Moments := preload("res://hongyuan/games/moments.gd")
const MOMENTS_DATA := "res://hongyuan/registry_moments.json"
const MOMENTS_IMAGE := "w2/shizuoka/registry_moments/%s.png"
const ENTRY := "w2/shizuoka/registry_door.png|round1/scenes/registry.png"
const SHARE := Rect2(179, 552, 149, 46)
const TORETTO_BACK := "w2/common/toretto_back_r2.png"
const TORETTO_STEP := "w2/common/toretto_walk_back.png|" + TORETTO_BACK
const RED := Color("#702f32")
const SHADE := Color("#23161b")
const CAPTION_BUTTON_GAP := 8.0
# Measured on the approved hall plate, relative to the uncropped image.
const SEAL_ON_HALL := Vector2(0.572, 0.499)

var r
var phase := "enter"
var t := 0.0
var hold := 0.0
var holding := false
var li := 0
var hall := ""
var memories: Array = []
var post_view: Moments
var sprite_bounds := {}

func start(runner, beat: Dictionary) -> void:
	r = runner
	hall = str(beat.get("hall", ENTRY))
	memories = beat.get("memories", [])
	r.hint = ""
	r.player_visible = false
	r.actors.clear()
	r.walkers.clear()
	r.crowd.setup([])

func _stamp_rect() -> Rect2:
	var area: Rect2 = r.view_rect
	var art: Texture2D = r.texture(hall)
	if not art: return Rect2(162, 214, 56, 29)
	var zoom := maxf(area.size.x / art.get_width(), area.size.y / art.get_height())
	var image_size := art.get_size() * zoom
	var at := area.get_center() + (SEAL_ON_HALL - Vector2(0.5, 0.5)) * image_size
	return Rect2(at - Vector2(24, 24), Vector2(48, 48))

func _next_rect() -> Rect2:
	return Rect2(32, 552, 132, 46) if phase == "memory" and li == memories.size() - 1 else Rect2(94, 552, 172, 46)
func _hold_bar() -> Rect2: return Rect2(62, 552, 236, 46)

func process(dt: float) -> bool:
	t += dt
	match phase:
		"enter":
			if t >= 2.55: _enter("consent_ayu")
		"stamp":
			if holding:
				hold = minf(1.0, hold + dt)
				if hold >= 1.0:
					holding = false
					li = 0
					_enter("memory")
					r.play("pop")
		"flash":
			if t >= 0.64: _enter("memory")
		"share":
			if post_view.process(dt):
				_enter("done")
	return phase == "done"

func _enter(next: String) -> void:
	phase = next
	t = 0

func _memory_text() -> String:
	return r.t_(str(memories[li].get("copy", ""))) if li < memories.size() else ""

func input(kind: String, pos: Vector2) -> void:
	if phase == "share":
		post_view.input(kind, pos)
		return
	if phase == "stamp":
		if kind == "down":
			holding = _stamp_rect().has_point(pos) or _hold_bar().has_point(pos)
		elif kind == "up" or (kind == "move" and not (_stamp_rect().grow(16).has_point(pos) or _hold_bar().grow(10).has_point(pos))):
			holding = false
			hold = 0
		return
	if kind == "tap" and t >= 0.32 and phase == "memory" and li == memories.size() - 1 and SHARE.has_point(pos):
		_open_post()
		return
	if kind != "tap" or not _next_rect().has_point(pos) or t < 0.32: return
	if phase == "consent_ayu":
		_enter("consent_toretto")
		r.play("blip")
	elif phase == "consent_toretto":
		_enter("stamp")
		r.play("blip")
	elif phase == "photo":
		_enter("flash")
		r.play("pop")
	elif phase == "memory":
		if li + 1 >= memories.size():
			_enter("done")
		else:
			li += 1
			_enter("photo" if li == memories.size() - 1 else "memory")

func _open_post() -> void:
	post_view = Moments.new()
	var published = JSON.parse_string(FileAccess.get_file_as_string(MOMENTS_DATA))
	if published is Dictionary:
		published.assetPattern = MOMENTS_IMAGE
		published.photos = [{"asset": MOMENTS_IMAGE % str(published.photo).get_basename(), "caption": "A4-REG-PHOTO"}]
	else:
		published = {"date": "A4-REG-DATE", "location": "A4-REG-LOCATION",
			"photos": [{"asset": memories.back().image, "caption": "A4-REG-PHOTO"}]}
	post_view.start(r, {"text": "A4-REG-M1", "post": published})
	_enter("share")

func restore_checkpoint() -> void:
	holding = false
	if phase == "stamp": hold = 0
	if phase == "share": _open_post()

func draw(ci) -> void:
	var area: Rect2 = ci.view_rect
	match phase:
		"enter":
			DeskArt.cover(ci, ci.texture(ENTRY), area)
			var progress := smoothstep(0.0, 1.0, (t - 0.15) / 2.4)
			var foot := lerpf(minf(area.end.y - 38.0, 602.0), 410.0, progress)
			_draw_walker(ci, Vector2(148, foot), false)
			_draw_walker(ci, Vector2(211, foot + 2), true)
			DeskArt.cover(ci, ci.texture(hall), area, 0.0, Color(1, 1, 1, smoothstep(1.89, 2.55, t)))
		"consent_ayu", "consent_toretto":
			DeskArt.cover(ci, ci.texture(hall), area)
			var box := Rect2(24, 424, 312, 93)
			ci.draw_rect(box, Color(SHADE, 0.94))
			ci.draw_rect(box, Color("#c3a16d"), false, 1.0)
			ci.text_at(Vector2(36, 450), "工作人员", 15, Color("#f6cd83"), 288, HORIZONTAL_ALIGNMENT_LEFT)
			var question: String = ci.t_("A4-REG-ASK-AYU" if phase == "consent_ayu" else "A4-REG-ASK-TORETTO")
			ci.text_at(Vector2(36, 482), question, 17, ci.PAPER, 288, HORIZONTAL_ALIGNMENT_LEFT)
			if t >= 0.32: ci.pill(_next_rect(), "我愿意", 18, RED, ci.PAPER)
		"stamp":
			DeskArt.cover(ci, ci.texture(hall), area)
			var center := _stamp_rect().get_center()
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			ci.draw_arc(center, 19 + 3 * pulse, 0, TAU, 32, Color(1, 0.88, 0.55, 0.48 + 0.35 * pulse), 2)
			if hold > 0:
				ci.draw_arc(center, 19, -PI / 2, -PI / 2 + TAU * hold, 32, ci.GOLD, 3)
			var bar := _hold_bar()
			ci.pill(bar, "一起按住印章一秒", 17, RED, ci.PAPER)
			ci.draw_rect(Rect2(bar.position + Vector2(8, bar.size.y - 6), Vector2((bar.size.x - 16) * hold, 3)), ci.GOLD)
			ci.draw_rect(area, Color(SHADE, 1.0 - smoothstep(0.0, 0.32, t)))
		"memory", "photo", "flash", "done":
			_draw_memory(ci, area)
		"share":
			post_view.draw(ci)

func _draw_memory(ci, area: Rect2) -> void:
	var page: Dictionary = memories[li] if li < memories.size() else {}
	var art: Texture2D = ci.texture(str(page.get("image", hall)))
	var portrait := li == memories.size() - 1
	var thought: bool = page.get("copy") == "A4-REG-M1"
	var body := StoryCaption.wrap_text(_memory_text(), 258.0 if thought else 312.0, 15)
	var extra_lines := body.count("\n")
	var caption_height := 27.0 + extra_lines * 18.0
	if thought: caption_height += 14
	var caption_bottom := _next_rect().position.y - CAPTION_BUTTON_GAP
	var photo_box := Rect2()
	if portrait and art and phase == "photo":
		_draw_live_portrait(ci, art, area)
		photo_box = Rect2(24, 86, 312, 420)
	elif portrait and art:
		# Keep the whole photo, including the date plaque, clear of the safe
		# area, navigation and subtitles. The plaque appears once, inside the frame.
		ci.draw_rect(area, SHADE)
		var top := maxf(StoryCaption.safe_top + 14, area.position.y + 28)
		var bottom := minf(507.0, caption_bottom - caption_height - 10.0)
		var zoom := minf(322.0 / art.get_width(), (bottom - top) / art.get_height())
		var photo_size := art.get_size() * maxf(0.1, zoom)
		photo_box = Rect2(Vector2(180 - photo_size.x * 0.5, top), photo_size)
		ci.draw_rect(photo_box.grow(5), Color("#b8935f"))
		ci.draw_rect(photo_box.grow(3), Color("#e8d6b1"))
		ci.draw_texture_rect(art, photo_box, false)
	else:
		DeskArt.cover(ci, art, area)
	if phase == "photo":
		_camera_marks(ci, photo_box.grow(-10))
		ci.pill(_next_rect(), "拍下这一刻", 17, RED, ci.PAPER)
	elif phase == "flash":
		ci.draw_rect(area, Color(1, 0.97, 0.91, 1.0 - smoothstep(0.0, 0.56, t)))
	elif phase == "memory":
		var subtitle_top := caption_bottom - caption_height
		if portrait: subtitle_top = minf(subtitle_top, 513.0)
		var box := Rect2(16, subtitle_top, 328, caption_height)
		ci.draw_rect(box, Color(SHADE, 0.94))
		ci.draw_line(box.position, box.position + Vector2(box.size.x, 0), Color("#bc9867"), 1)
		if thought:
			var head := StoryCaption.avatar("ayu")
			if head: ci.draw_texture_rect(head, Rect2(box.position + Vector2(9, 12), Vector2(38, 38)), false)
			ci.text_at(box.position + Vector2(56, 18), "阿鱼", 13, Color("#f6cd83"), 258, HORIZONTAL_ALIGNMENT_LEFT)
			ci.text_at(box.position + Vector2(56, 34), body, 15, ci.PAPER, 258, HORIZONTAL_ALIGNMENT_LEFT)
		else:
			ci.text_at(box.position + Vector2(8, 18), body, 15, ci.PAPER, box.size.x - 16)
		var label: String = ["领取结婚证", "收好红本", "准备合影", "继续回忆"][mini(li, 3)]
		ci.pill(_next_rect(), label, 17, RED, ci.PAPER)
		if portrait: ci.pill(SHARE, "帮她发朋友圈", 16, ci.RED, ci.PAPER)
		ci.draw_rect(area, Color(SHADE, 0.52 * (1.0 - smoothstep(0.0, 0.32, t))))

func _draw_live_portrait(ci, art: Texture2D, area: Rect2) -> void:
	# The date plaque and the keepsake frame belong to the finished photo.
	var source_size := Vector2(art.get_width(), art.get_height() * 0.68)
	var zoom := maxf(area.size.x / source_size.x, area.size.y / source_size.y)
	var crop_size := area.size / zoom
	var source := Rect2(Vector2((source_size.x - crop_size.x) * 0.5, 0), crop_size)
	ci.draw_texture_rect_region(art, area, source)

func _draw_walker(ci, foot: Vector2, man: bool) -> void:
	var frame := 1 + int(t * 7) % 4
	var file := "w2/common/ayu_walk_back_%d.png" % frame
	if man:
		file = TORETTO_STEP if frame % 2 == 1 else TORETTO_BACK
	var tex: Texture2D = ci.texture(file)
	if not tex: return
	if not sprite_bounds.has(tex): sprite_bounds[tex] = ci.WorldScale.visible_rect(tex)
	var used: Rect2 = sprite_bounds[tex]
	var height := lerpf(132, 105, smoothstep(0.0, 1.0, t / 2.3)) * (1.05 if man else 1.0)
	var size := used.size * (height / used.size.y)
	ci.draw_set_transform(foot, 0.0, Vector2(-1, 1) if man and frame == 3 else Vector2.ONE)
	ci.draw_texture_rect_region(tex, Rect2(Vector2(-size.x * 0.5, -height), size), used)
	ci.draw_set_transform(Vector2.ZERO)

func _camera_marks(ci, box: Rect2) -> void:
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			var corner := Vector2(x, y)
			ci.draw_line(corner, corner + Vector2(13 if x < 180 else -13, 0), ci.PAPER, 2)
			ci.draw_line(corner, corner + Vector2(0, 13 if y == box.position.y else -13), ci.PAPER, 2)
