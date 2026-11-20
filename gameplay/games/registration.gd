extends RefCounted
## The seal and the bottom instruction share the same hold action.
const DeskArt := preload("res://hongyuan/ui/desk_art.gd")
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
const ENTRY := "round1/scenes/registry.png"
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

func _next_rect() -> Rect2: return Rect2(94, 552, 172, 46)
func _hold_bar() -> Rect2: return Rect2(62, 552, 236, 46)

func process(dt: float) -> bool:
	t += dt
	match phase:
		"enter":
			if t >= 2.55: _enter("stamp")
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
	return phase == "done"

func _enter(next: String) -> void:
	phase = next
	t = 0

func _memory_text() -> String:
	return r.t_(str(memories[li].get("copy", ""))) if li < memories.size() else ""

func input(kind: String, pos: Vector2) -> void:
	if phase == "stamp":
		if kind == "down":
			holding = _stamp_rect().has_point(pos) or _hold_bar().has_point(pos)
		elif kind == "up" or (kind == "move" and not (_stamp_rect().grow(16).has_point(pos) or _hold_bar().grow(10).has_point(pos))):
			holding = false
			hold = 0
		return
	if kind != "tap" or not _next_rect().has_point(pos) or t < 0.32: return
	if phase == "photo":
		_enter("flash")
		r.play("pop")
	elif phase == "memory":
		if li + 1 >= memories.size():
			_enter("done")
		else:
			li += 1
			_enter("photo" if li == memories.size() - 1 else "memory")

func restore_checkpoint() -> void:
	holding = false
	if phase == "stamp": hold = 0

func draw(ci) -> void:
	var area: Rect2 = ci.view_rect
	match phase:
		"enter":
			DeskArt.cover(ci, ci.texture(ENTRY), area)
			_draw_hall_sign(ci, area)
			var doorway := 1.0 - smoothstep(0.45, 1.1, t)
			ci.draw_rect(Rect2(area.position, Vector2(14, area.size.y)), Color(RED, doorway))
			ci.draw_rect(Rect2(area.end.x - 14, area.position.y, 14, area.size.y), Color(RED, doorway))
			ci.draw_rect(Rect2(area.position, Vector2(area.size.x, 22)), Color(RED, doorway))
			var sill_y := area.end.y - 58.0 + 180.0 * smoothstep(0.0, 1.0, t / 1.1)
			ci.draw_rect(Rect2(area.position.x, sill_y, area.size.x, 18), Color("#44252b", doorway))
			ci.draw_line(Vector2(area.position.x, sill_y), Vector2(area.end.x, sill_y), Color("#d4af73", doorway), 4)
			ci.draw_line(Vector2(area.position.x, sill_y + 17), Vector2(area.end.x, sill_y + 17), Color("#ad7549", doorway), 3)
			var progress := smoothstep(0.0, 1.0, (t - 0.45) / 1.85)
			var foot := lerpf(minf(area.end.y - 38.0, 602.0), 343.0, progress)
			_draw_walker(ci, Vector2(148, foot), false)
			_draw_walker(ci, Vector2(211, foot + 2), true)
			ci.draw_rect(area, Color(SHADE, smoothstep(2.18, 2.55, t)))
		"stamp":
			DeskArt.cover(ci, ci.texture(hall), area)
			if hall == ENTRY: _draw_hall_sign(ci, area)
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

func _draw_memory(ci, area: Rect2) -> void:
	var page: Dictionary = memories[li] if li < memories.size() else {}
	var art: Texture2D = ci.texture(str(page.get("image", hall)))
	var portrait := li == memories.size() - 1
	var body := StoryCaption.wrap_text(_memory_text(), 312.0, 15)
	var extra_lines := body.count("\n")
	var caption_height := 27.0 + extra_lines * 18.0
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
		ci.text_at(box.position + Vector2(8, 18), body, 15, ci.PAPER, box.size.x - 16)
		var label: String = ["领取结婚证", "收好红本", "准备合影", "回到请帖"][mini(li, 3)]
		ci.pill(_next_rect(), label, 17, RED, ci.PAPER)
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
	var file := "w2/common/toretto_back_r2.png" if man else "w2/common/ayu_walk_back_%d.png" % frame
	var tex: Texture2D = ci.texture(file)
	if not tex: return
	var used: Rect2 = ci.WorldScale.visible_rect(tex)
	var height := lerpf(132, 105, smoothstep(0.0, 1.0, t / 2.3)) * (1.05 if man else 1.0)
	var size := used.size * (height / used.size.y)
	var stride := sin(t * 15 + (PI if man else 0))
	ci.draw_texture_rect_region(tex, Rect2(foot + Vector2(-size.x * 0.5 + stride, -height + absf(stride)), size), used)

func _camera_marks(ci, box: Rect2) -> void:
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			var corner := Vector2(x, y)
			ci.draw_line(corner, corner + Vector2(13 if x < 180 else -13, 0), ci.PAPER, 2)
			ci.draw_line(corner, corner + Vector2(0, 13 if y == box.position.y else -13), ci.PAPER, 2)

func _draw_hall_sign(ci, area: Rect2) -> void:
	var art: Texture2D = ci.texture(ENTRY)
	if not art: return
	var zoom := maxf(area.size.x / art.get_width(), area.size.y / art.get_height())
	var origin := area.get_center() - art.get_size() * zoom * 0.5
	# Match the blank plaque in the approved hall image, including cover cropping.
	var left := origin + Vector2(244, 406) * zoom
	ci.draw_string(ci.FONT, left, "婚姻登记处", HORIZONTAL_ALIGNMENT_CENTER, 392 * zoom, maxi(16, roundi(51 * zoom)), Color("#f5d88b"))
