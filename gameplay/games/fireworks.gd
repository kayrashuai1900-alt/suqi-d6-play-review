extends RefCounted
const CoastShow := preload("res://hongyuan/coast_show.gd")
const CUE_COLORS := ["blue", "red", "gold"]
const SIDE_COLORS := ["blue", "mint", "violet"]
const FINALE := [
	[0.07, Vector2(71, 129), "blue", 1.21],
	[0.35, Vector2(282, 114), "blue", 1.15],
	[0.81, Vector2(108, 177), "red", 0.89],
	[1.02, Vector2(258, 166), "mint", 0.87],
	[1.28, Vector2(161, 120), "violet", 0.83],
	[1.57, Vector2(226, 206), "pink", 0.77],
	[2.08, Vector2(67, 109), "gold", 1.16],
	[2.27, Vector2(293, 126), "gold", 1.12],
	[2.82, Vector2(75, 213), "gold", 0.63],
	[3.03, Vector2(287, 220), "gold", 0.68],
]
const FINALE_LENGTH := 5.4
const HEART_START := 3.05
const CENTER := Vector2(180, 200)

var r
var t := 0.0
var bursts: Array = []
var count := 0
var need := 5
var phase := "play"
var finale_t := 0.0

func start(runner, beat: Dictionary) -> void:
	r = runner
	need = int(beat.get("count", 5))
	r.hint = "点一下夜空，在那里放一簇烟花"

func restore_checkpoint() -> void:
	if phase != "play":
		r.hint = ""

func _cluster(at: Vector2, k: int) -> void:
	var index := k % CUE_COLORS.size()
	bursts.append({"at": at, "color": CUE_COLORS[index], "t": 0.0, "size": 192.0})
	var offset := 86.0 if at.x < 180.0 else -86.0
	var side := Vector2(at.x + offset, at.y - 35.0).clamp(Vector2(40, 54), Vector2(320, 283))
	bursts.append({"at": side, "color": SIDE_COLORS[index], "t": -0.36, "size": 128.0})
	r.play("pop")

func process(dt: float) -> bool:
	t += dt
	for burst: Dictionary in bursts:
		burst.t += dt
	bursts = bursts.filter(func(burst: Dictionary) -> bool: return burst.t < CoastShow.LIFE)
	match phase:
		"play":
			if count >= need:
				r.hint = ""
				phase = "finale"
				finale_t = 0.0
		"finale":
			finale_t += dt
			if finale_t >= HEART_START and finale_t - dt < HEART_START:
				r.play("pop")
			if finale_t >= FINALE_LENGTH:
				phase = "wax"
				finale_t = 0.0
		"wax":
			finale_t += dt
			if finale_t > 2.4:
				phase = "done"
	return phase == "done"

func input(kind: String, pos: Vector2) -> void:
	if phase == "play" and kind == "down" and pos.y >= 0 and pos.y < 440 and count < need:
		_cluster(Vector2(clampf(pos.x, 40, 320), clampf(pos.y, 50, 320)), count)
		count += 1

func draw_coast(ci, ambient_clock: float) -> void:
	if phase == "play" and ambient_clock >= 0.0:
		CoastShow.draw(ci, ambient_clock)
	var sea := CoastShow.waterline(ci)
	for burst: Dictionary in bursts:
		# Older saves can include a separate finale heart in this list.
		if not burst.get("big", false):
			CoastShow.draw_burst(ci, burst.at, burst.color, burst.t, float(burst.size) / 192.0, sea)
	if phase == "finale":
		CoastShow.draw_sequence(ci, FINALE, finale_t, sea)
		if finale_t >= HEART_START:
			_draw_heart(ci, finale_t - HEART_START)

func draw(ci) -> void:
	if phase == "wax":
		var frame := mini(4, 1 + int(finale_t / 0.4))
		var wax: Texture2D = ci.texture("w2/hainan/firework_wax_%d.png" % frame)
		if wax:
			var size: Vector2 = wax.get_size() * ci.S
			ci.draw_texture_rect(wax, Rect2(CENTER - size * 0.5, size), false)
	if phase == "play" and count == 0:
		var alpha := 0.6 + 0.4 * sin(t * 5.0)
		ci.draw_arc(CENTER, 14 + fmod(t * 20.0, 14.0), 0, TAU, 24, Color(ci.PAPER, alpha * 0.6), 2.0)
		ci.draw_circle(CENTER, 8, Color(ci.PAPER, alpha))

func _draw_heart(ci, age: float) -> void:
	var growth := 1.0 - exp(-age * 3.2)
	var alpha := smoothstep(0.0, 0.28, age) * (1.0 - smoothstep(1.35, 2.37, age))
	var pink: Color = CoastShow.PALETTE.pink
	for ray in range(108):
		var angle := TAU * ray / 108.0
		var x := sin(angle)
		var y := -(13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle)) / 16.0
		var dir := Vector2(x * x * x, y)
		var point := CENTER + dir * 98.0 * growth + Vector2(0, age * age * 3.0)
		var grain := sin(ray * 2.43)
		var trail := point - dir * (7.5 + 9.0 * (1.0 - growth) + grain * 3.0)
		var twinkle := (0.75 + 0.25 * sin(age * 21.0 + ray * 2.9)) * alpha
		ci.draw_line(trail, point, Color(pink, twinkle * 0.28), 6.8)
		ci.draw_line(trail, point, Color(pink.lerp(Color.WHITE, 0.38), twinkle * 0.73), 2.8, true)
		var sparkle := 3.15 if ray % 3 == 0 else 2.45
		ci.draw_rect(Rect2(point.round() - Vector2.ONE * sparkle * 0.5, Vector2.ONE * sparkle), Color(pink.lerp(Color.WHITE, 0.76), twinkle))
		var ember := point + dir * (4.0 + 9.0 * grain) + Vector2.from_angle(angle + PI * 0.5) * grain * 5.0
		ci.draw_rect(Rect2(ember.round(), Vector2.ONE * 1.7), Color(pink.lerp(Color.WHITE, 0.48), twinkle * 0.72))
