extends RefCounted
## 俯视竖向卷轴驾驶：左右滑动换道躲车，撞到只减速；最后等右侧空位接近，按住刹车后车头朝前泊入。
## 东方明珠的原画放在目的地面板里，路面只画交通和停车位。

const LANES := [120.0, 180.0, 240.0]
const CAR_Y := 500.0
const LENGTH := 5200.0
const CRUISE := 230.0
const PURPLE := Color("#6b3fa0")
const DESTINATION_ART := "w2/shanghai/bg_pearl_plaza.png"
const DESTINATION_CROP := Rect2(24, 0, 492, 448)
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")

var r
var phase := "drive"   # (ready →) drive → park → in → done；任务卡已经确认过一次，不再要「出发」第二次确认
var t := 0.0
var lane := 1
var car_x := 180.0
var scroll := 0.0
var speed := 0.0
var bump := 0.0
var traffic: Array = []
var spawn_at := 420.0
var rng := RandomNumberGenerator.new()
var holding := false
var bay_y := -9999.0
var park_t := 0.0
var misses := 0
var miss_note_t := 0.0
var swipe_from := Vector2.ZERO
var swiping := false
var tapped := false


func start(runner, _beat: Dictionary) -> void:
	r = runner
	rng.seed = Time.get_ticks_usec()


func process(dt: float) -> bool:
	t += dt
	car_x = move_toward(car_x, LANES[lane], 300.0 * dt)
	bump = maxf(0.0, bump - dt)
	miss_note_t = maxf(0.0, miss_note_t - dt)
	match phase:
		"drive":
			var want := CRUISE * (0.45 if bump > 0.0 else 1.0)
			speed = move_toward(speed, want, 260.0 * dt)
			scroll += speed * dt
			_traffic(dt)
			if scroll >= LENGTH:
				phase = "park"
				park_t = 0.0
				bay_y = -120.0
				lane = 2
				swiping = false
				traffic.clear()
		"park":
			park_t += dt
			if holding and _bay_in_range():
				tapped = true
			var braking := tapped or (bay_y >= CAR_Y - 40.0 and misses >= 2)
			if bay_y > CAR_Y + 150.0 and not tapped:
				misses += 1
				bay_y = -260.0
				miss_note_t = 2.4
				r.play("blip")
			var want2 := 0.0 if braking else 150.0
			speed = move_toward(speed, want2, (300.0 if braking else 90.0) * dt)
			scroll += speed * dt
			bay_y += speed * dt
			if braking and speed < 8.0:
				phase = "in"
				park_t = 0.0
				speed = 0.0
				lane = 2
				r.play("pop")
		"in":
			park_t += dt
			if park_t >= 1.2:
				phase = "done"
				return true
	return phase == "done"


func _traffic(dt: float) -> void:
	if scroll >= spawn_at and scroll < LENGTH - 500.0:
		spawn_at = scroll + rng.randf_range(300.0, 470.0)
		var l := rng.randi_range(0, 2)
		traffic.append({"lane": l, "y": -80.0, "v": rng.randf_range(80.0, 120.0), "kind": rng.randi_range(1, 3), "hit": false})
		if rng.randf() < 0.3:
			traffic.append({"lane": (l + rng.randi_range(1, 2)) % 3, "y": -230.0, "v": 100.0, "kind": rng.randi_range(1, 3), "hit": false})
	for c: Dictionary in traffic:
		c.y += (speed - float(c.v)) * dt
		if not c.hit and absf(float(c.y) - CAR_Y) < 54.0 and absf(LANES[int(c.lane)] - car_x) < 36.0:
			c.hit = true
			bump = 0.9
			speed *= 0.5
			r.play("blip")
	traffic = traffic.filter(func(c: Dictionary) -> bool: return float(c.y) < 760.0)


func input(kind: String, pos: Vector2) -> void:
	match phase:
		"ready":
			if kind == "tap" and _go_rect().grow(10).has_point(pos):
				phase = "drive"
				r.play("blip")
		"drive":
			if kind == "down":
				swipe_from = pos
				swiping = true
			elif kind == "move" and swiping and absf(pos.x - swipe_from.x) > 26.0:
				lane = clampi(lane + (1 if pos.x > swipe_from.x else -1), 0, 2)
				swipe_from = pos
			elif kind == "up":
				swiping = false
			elif kind == "tap":
				lane = clampi(lane + (1 if pos.x > car_x else -1), 0, 2)
		"park":
			match kind:
				"down": holding = true
				"up": holding = false
				"tap":
					if absf(bay_y - CAR_Y) < 95.0:
						tapped = true


func _go_rect() -> Rect2:
	return Rect2(120, 560, 120, 44)


func draw(ci) -> void:
	_road(ci)
	if phase in ["park", "in", "done"]:
		_bay(ci)
	for c: Dictionary in traffic:
		_car(ci, Vector2(LANES[int(c.lane)], float(c.y)), "w2/shanghai/traffic_top_%d.png" % int(c.kind), [Color("#c9ccd4"), Color("#3c6fb0"), Color("#d6a456")][int(c.kind) - 1])
	var p := Vector2(car_x, CAR_Y)
	var ang := clampf((LANES[lane] - car_x) / 120.0, -0.25, 0.25)
	if phase == "in":
		var k := smoothstep(0.0, 1.0, park_t / 1.0)
		p = Vector2(lerpf(car_x, 318.0, k), lerpf(CAR_Y, bay_y, k))
		ang = sin(k * PI) * 0.45
	if bump > 0.0:
		p.x += sin(t * 60.0) * 2.0 * bump
	_car(ci, p, "w2/shanghai/g42_top.png", PURPLE, ang)
	_draw_route(ci)
	if phase == "ready":
		ci.draw_rect(ci.view_rect, Color(0, 0, 0, 0.25))
		ci.pill(_go_rect(), ci.t_("A1-B2"), 20, ci.RED, ci.PAPER)
	elif phase == "park":
		var color: Color = ci.RED if _bay_in_range() and not tapped else Color(ci.INK, 0.94)
		ci.pill(Rect2(32, 570, 296, 38), _parking_instruction(), 15, color, ci.PAPER)


func _road(ci) -> void:
	var tile: Texture2D = ci.texture("round1/scenes/shanghai_drive.png|w2/shanghai/drive_tile.png")
	if tile:
		var h := tile.get_size().y * (360.0 / tile.get_size().x)
		var off := fposmod(scroll, h)
		var y: float = ci.view_rect.position.y + off - h
		while y < ci.view_rect.end.y:
			ci.draw_texture_rect(tile, Rect2(0, y, 360, h), false)
			y += h
		return
	# 占位：草地、人行道、三车道、虚线、路灯和行道树都跟着滚
	ci.draw_rect(Rect2(0, 0, 360, 640), Color("#6f8f4e"))
	ci.draw_rect(Rect2(66, 0, 228, 640), Color("#c9b48c"))
	ci.draw_rect(Rect2(86, 0, 188, 640), Color("#4a4550"))
	ci.draw_rect(Rect2(88, 0, 3, 640), Color("#e8e0cc"))
	ci.draw_rect(Rect2(269, 0, 3, 640), Color("#e8e0cc"))
	var off2 := fposmod(scroll, 64.0)
	for lx in [150.0, 210.0]:
		var y2 := off2 - 64.0
		while y2 < 640.0:
			ci.draw_rect(Rect2(lx - 1.5, y2, 3, 28), Color("#efe6d2"))
			y2 += 64.0
	var off3 := fposmod(scroll, 160.0)
	var y3 := off3 - 160.0
	while y3 < 700.0:
		for side in [-1, 1]:
			var tx: float = 180.0 + side * 140.0
			ci.draw_circle(Vector2(tx, y3), 20, Color("#3f6b3a"))
			ci.draw_circle(Vector2(tx - 5, y3 - 5), 12, Color("#5d8c4a"))
			ci.draw_rect(Rect2(180.0 + side * 100.0 - 3, y3 + 70, 6, 6), Color("#2d2a2e"))
			ci.draw_circle(Vector2(180.0 + side * 100.0, y3 + 73), 7, Color(1, 0.9, 0.6, 0.25))
		y3 += 160.0


func _bay(ci) -> void:
	var lot: Texture2D = ci.texture("w2/shanghai/parking_lot.png")
	for slot in range(-2, 3):
		var y := bay_y + slot * 92.0
		var space := Rect2(280, y - 45, 76, 92)
		if not space.intersects(ci.view_rect):
			continue
		if lot:
			# Reuse one unmarked bay without the old baked target rectangle.
			ci.draw_texture_rect_region(lot, space, Rect2(0, lot.get_height() * 0.14, lot.get_width(), lot.get_height() * 0.142))
		else:
			ci.draw_rect(space, Color("#595158"))
			ci.draw_rect(space, Color("#e8d9a6"), false, 2.0)
		if slot == 0:
			if phase == "park":
				var in_range := _bay_in_range()
				ci.draw_rect(space.grow(-4), Color(0.98, 0.82, 0.42, 0.28 if in_range else 0.10))
				ci.draw_rect(space.grow(-4), ci.GOLD, false, 3.0 if in_range else 1.5)
				ci.text_at(Vector2(284, y + 5), "空位", 13, ci.PAPER, 68)
		else:
			var model := posmod(slot + 3, 3) + 1
			_car(ci, Vector2(318, y), "w2/shanghai/traffic_top_%d.png" % model, [Color("#c9ccd4"), Color("#3c6fb0"), Color("#d6a456")][model - 1])



func _car(ci, p: Vector2, tex_name: String, color: Color, ang := 0.0) -> void:
	var tex: Texture2D = ci.texture(tex_name)
	ci.draw_set_transform(p, ang, Vector2.ONE)
	if tex:
		var sz: Vector2 = tex.get_size() * ci.S
		# The alpha of this exact model is its shadow silhouette.
		ci.draw_texture_rect(tex, Rect2(-sz * 0.5 + Vector2(3, 5), sz), false, Color(0, 0, 0, 0.65))
		ci.draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false)
	else:
		ci.draw_set_transform(p + Vector2(3, 5), ang, Vector2(21, 35))
		ci.draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, 0.65))
		ci.draw_set_transform(p, ang, Vector2.ONE)
		ci.draw_rect(Rect2(-19, -34, 38, 68), color)
		ci.draw_rect(Rect2(-15, -18, 30, 14), Color("#20283a"))
		ci.draw_rect(Rect2(-15, 14, 30, 10), Color("#20283a"))
		ci.draw_rect(Rect2(-12, -6, 24, 18), color.lightened(0.15))
		ci.draw_rect(Rect2(-17, -36, 8, 4), Color("#fff2c0"))
		ci.draw_rect(Rect2(9, -36, 8, 4), Color("#fff2c0"))
		ci.draw_rect(Rect2(-17, 33, 8, 3), Color("#d83a3a"))
		ci.draw_rect(Rect2(9, 33, 8, 3), Color("#d83a3a"))
	ci.draw_set_transform(Vector2.ZERO)


func _draw_route(ci) -> void:
	var y := maxf(14.0, StoryCaption.safe_top + 10.0)
	var panel := Rect2(12, y, 230, 74)
	ci.draw_rect(panel, Color(ci.INK, 0.94))
	ci.draw_rect(panel, Color(ci.GOLD, 0.72), false, 1.0)
	var landmark: Texture2D = ci.texture(DESTINATION_ART)
	if landmark:
		ci.draw_texture_rect_region(landmark, Rect2(19, y + 8, 64, 58), DESTINATION_CROP)
	var on_road := phase in ["ready", "drive"]
	var title := "前往东方明珠" if on_road else "抵达东方明珠"
	var instruction := "左右滑动，换道避车"
	match phase:
		"park": instruction = "右侧金框是空车位"
		"in": instruction = "正在泊入右侧车位"
		"done": instruction = "已停进右侧车位"
	ci.text_at(Vector2(92, y + 25), title, 17, ci.PAPER, 141, HORIZONTAL_ALIGNMENT_LEFT)
	ci.text_at(Vector2(92, y + 45), instruction, 13, ci.PAPER, 141, HORIZONTAL_ALIGNMENT_LEFT)
	var progress := clampf(scroll / LENGTH, 0.0, 1.0)
	ci.draw_rect(Rect2(93, y + 57, 140, 4), Color("#584634"))
	ci.draw_rect(Rect2(93, y + 57, 140 * progress, 4), ci.GOLD)


func _bay_in_range() -> bool:
	return bay_y >= CAR_Y - 115.0 and bay_y <= CAR_Y + 60.0


func _parking_instruction() -> String:
	if tapped: return "正在刹车，准备泊入右侧"
	if _bay_in_range(): return "现在按住屏幕刹车"
	if holding: return "继续按住，空位正在靠近"
	if miss_note_t > 0.0: return "错过车位，等下一个空位"
	return "右侧空位靠近时，按住刹车"
