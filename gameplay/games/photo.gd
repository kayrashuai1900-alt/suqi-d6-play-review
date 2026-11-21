extends RefCounted
const AYU_STAND := "ayu_idle.png"
const TORETTO_STAND := "w2/common/toretto_neutral_r2.png"
const SHOW_TIME := 2.2
const MEMORY_SHOW_TIME := 3.6
const CAMERA_ART := "w2/hongkong/travel_camera.png"
const WALK_ON := Rect2(102, 570, 156, 44)

var r
var phase := "ready"
var t := 0.0
var ayu_x := 0.0
var toretto_x := 0.0
var _frames := 0
var caption := "B-G3-1"
var memory_art := ""
var park_photo := ""
var park_photos_before := 0
var optional := false
var _photo: Texture2D


func start(runner, beat: Dictionary) -> void:
	r = runner
	caption = str(beat.get("caption","B-G3-1"))
	memory_art = str(beat.get("photoArt", ""))
	park_photo = str(beat.get("parkPhoto", ""))
	optional = bool(beat.get("photoOptional", false))
	if not park_photo.is_empty():
		# Only the normal shutter reaches the next photo beat. The current beat
		# already lives in the checkpoint, so no separate counter can drift.
		var earlier := {}
		for previous: Dictionary in r.beats.slice(0, r.bi):
			if previous.has("parkPhoto"): earlier[previous.parkPhoto] = true
		park_photos_before = earlier.size()
	phase = "ready"
	ayu_x = r.feet.x
	toretto_x = r.comp_pos.x
	r.hint = r.t_("G-PHOTO")


func restore_checkpoint() -> void:
	# The GPU texture is deliberately excluded from JSON checkpoints. Rebuild it
	# from a clean couple frame before replaying the flash/polaroid transition.
	_photo = null
	_frames = 0
	if phase == "walk": phase = "ready"
	ayu_x = r.feet.x
	toretto_x = r.comp_pos.x
	if phase in ["prep", "flash", "show"]:
		phase = "prep"
		t = 0.0
	r.hint = r.t_("G-PHOTO") if phase == "ready" else ""


func process(dt: float) -> bool:
	t += dt
	match phase:
		"prep":
			_frames += 1
			if _frames >= 3 and t >= 0.26:
				_capture()
				phase = "flash"
				t = 0.0
				r.play("pop")
		"flash":
			if t >= 0.5:
				phase = "show"
				t = 0.0
		"show":
			if t >= (MEMORY_SHOW_TIME if not memory_art.is_empty() else SHOW_TIME):
				phase = "done"
	return phase == "done"


func _capture() -> void:
	if not memory_art.is_empty():
		_photo = r.texture(memory_art)
		if _photo:
			return
	if DisplayServer.get_name() == "headless":
		return
	var vp: Viewport = r.get_viewport()
	if vp and vp.get_texture():
		var img: Image = vp.get_texture().get_image()
		if img and img.get_width() > 8:
			_photo = ImageTexture.create_from_image(img)


func _camera_rect() -> Rect2:
	var middle: Vector2 = (r.feet+r.comp_pos)*0.5
	return Rect2(Vector2(clampf(middle.x,36,324),middle.y-r.person_height_at(middle.y)-38)-Vector2(24,24),Vector2(48,48))


func input(kind: String, pos: Vector2) -> void:
	if kind != "tap" or phase != "ready":
		return
	if optional and WALK_ON.has_point(pos):
		skip()
		return
	# 相机图标及其下方一整片都算（手指常点在图标下面）
	var zone := _camera_rect().grow(16)
	zone = zone.merge(Rect2(zone.position.x - 30, zone.position.y, zone.size.x + 60, zone.size.y + 90))
	if zone.has_point(pos):
		phase = "prep"
		t = 0.0
		_frames = 0
		r.hint = ""


func skip() -> void:
	phase = "done"
	r.hint = ""


# ---------- 画 ----------

func draw(ci) -> void:
	if phase in ["show", "flash"] and _photo:
		ci.draw_rect(ci.view_rect, Color(0.04, 0.03, 0.05, 0.6 if phase == "show" else 0.0))
	else:
		_draw_couple(ci)
	if phase == "ready":
		_draw_camera(ci)
		if optional: ci.pill(WALK_ON, "继续走走", 16, ci.INK, ci.PAPER)
	if phase == "show":
		_draw_polaroid(ci)
	if phase == "flash":
		ci.draw_rect(ci.view_rect, Color(1, 1, 1, 1.0 - clampf(t / 0.5, 0.0, 1.0)))


func _draw_couple(ci) -> void:
	ci.sprite(TORETTO_STAND, Vector2(toretto_x, r.comp_pos.y), false, 1.0)
	ci.sprite(AYU_STAND, Vector2(ayu_x, r.feet.y), false, 1.0)


func _draw_camera(ci) -> void:
	var c: Vector2 = _camera_rect().get_center() + Vector2(0, sin(ci.time * 4.0) * 3.0)
	var a: float = 0.5 + 0.3 * sin(ci.time * 4.5)
	var ring := PackedVector2Array()
	for j in range(25):
		var ang := TAU * j / 24.0
		ring.append(c + Vector2(cos(ang), sin(ang)) * (30.0 + sin(ci.time * 4.5) * 2.0))
	ci.draw_polyline(ring, Color(1.0, 0.92, 0.65, a), 2.0)
	ci.draw_circle(c, 26.0, Color(ci.INK, 0.8))
	var art: Texture2D = ci.texture(CAMERA_ART)
	if art:
		var size := art.get_size() * minf(46.0 / art.get_width(), 38.0 / art.get_height())
		ci.draw_texture_rect(art, Rect2(c - size * 0.5, size), false)
		return
	ci.draw_rect(Rect2(c + Vector2(-15, -9), Vector2(30, 20)), Color("#e9dfd0"))
	ci.draw_rect(Rect2(c + Vector2(-15, -9), Vector2(30, 20)), ci.INK, false, 2.0)
	ci.draw_rect(Rect2(c + Vector2(-10, -14), Vector2(10, 6)), Color("#e9dfd0"))
	ci.draw_rect(Rect2(c + Vector2(-10, -14), Vector2(10, 6)), ci.INK, false, 2.0)
	ci.draw_circle(c + Vector2(0, 1), 7.0, ci.INK)
	ci.draw_circle(c + Vector2(0, 1), 4.5, Color("#5aa8d6"))
	ci.draw_circle(c + Vector2(-1.5, -0.5), 1.5, Color(1, 1, 1, 0.9))
	ci.draw_rect(Rect2(c + Vector2(9, -7), Vector2(4, 3)), ci.GOLD)


func _draw_polaroid(ci) -> void:
	var k := clampf(t / 0.28, 0.0, 1.0)
	var pop := 1.0 + (1.0 - k) * 0.16
	var center := Vector2(180, 316)
	ci.draw_set_transform(center, deg_to_rad(-2.0), Vector2(pop, pop))
	var outer := Rect2(Vector2(-134, -246), Vector2(268, 488))
	ci.draw_rect(Rect2(outer.position + Vector2(5, 7), outer.size), Color(0, 0, 0, 0.35 * k))
	ci.draw_rect(outer, Color("#fbf6ea", k))
	ci.draw_rect(outer, Color(ci.INK, 0.9 * k), false, 2.0)
	var photo := Rect2(Vector2(-122, -234), Vector2(244, 434))
	if _photo:
		var src := Rect2(Vector2.ZERO,_photo.get_size())
		var wanted := photo.size.x/photo.size.y
		if src.size.x/src.size.y > wanted:
			src.position.x = (src.size.x-src.size.y*wanted)*0.5
			src.size.x = src.size.y*wanted
		else:
			src.position.y = (src.size.y-src.size.x/wanted)*0.5
			src.size.y = src.size.x/wanted
		ci.draw_texture_rect_region(_photo, photo, src, Color(1,1,1,k))
	else:
		ci.draw_rect(photo, Color("#d8b9a2", k))
	ci.draw_rect(photo, Color(ci.WOOD, 0.8 * k), false, 2.0)
	ci.text_at(Vector2(-122, 224), ci.t_(caption), 16, Color(ci.INK, k), 244)
	ci.draw_set_transform(Vector2.ZERO)

func hud() -> Array:
	if park_photo.is_empty() or phase == "prep": return []
	return [["乐园合影", park_photos_before + (1 if phase != "ready" else 0), 3]]
