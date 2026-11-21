extends RefCounted
## Deterministic trails follow the saved show clock, including after a reload.

const RISE := 0.45
const LIFE := 3.45
const PALETTE := {
	"blue": Color("#60caff"), "pink": Color("#ff8ec9"), "red": Color("#ff826d"),
	"gold": Color("#ffc56a"), "mint": Color("#7ce9bc"), "violet": Color("#bc9aff"),
}
const SHOW := [
	[0.0, Vector2(79, 134), "blue", 1.26],
	[0.45, Vector2(273, 118), "blue", 1.17],
	[0.96, Vector2(184, 191), "blue", 0.66],
	[3.07, Vector2(67, 137), "red", 1.01],
	[3.34, Vector2(158, 115), "mint", 0.99],
	[3.62, Vector2(283, 138), "gold", 1.06],
	[3.94, Vector2(105, 207), "violet", 0.83],
	[4.18, Vector2(233, 215), "pink", 0.89],
	[4.48, Vector2(315, 224), "mint", 0.72],
	[7.12, Vector2(193, 148), "gold", 1.15],
	[7.56, Vector2(78, 190), "violet", 0.73],
]

static var _glow: GradientTexture2D

static func draw(ci, elapsed: float) -> void:
	draw_sequence(ci, SHOW, fposmod(elapsed, 11.6), waterline(ci))

static func waterline(ci) -> float:
	var back: Texture2D = ci.texture(ci.bg)
	if not back:
		return 380.0
	# Match the beach plate's cover fit, including taller phones and camera offset.
	var area: Rect2 = ci.view_rect
	var height := back.get_height() * maxf(area.size.x / back.get_width(), area.size.y / back.get_height())
	var travel := maxf(0.0, (height - area.size.y) * 0.5)
	return area.get_center().y + height * (994.0 / 1672.0 - 0.5) + clampf(ci.camera_y, -travel, travel)

static func draw_sequence(ci, cues: Array, clock: float, sea: float) -> void:
	for cue: Array in cues:
		draw_burst(ci, cue[1], cue[2], clock - cue[0], cue[3], sea)

static func draw_burst(ci, at: Vector2, hue: String, age: float, size: float, sea: float) -> void:
	if age < 0.0 or age >= LIFE:
		return
	var tint: Color = PALETTE.get(hue, PALETTE.gold)
	if age < RISE:
		var source := Vector2(lerpf(at.x, 204.0, 0.25), sea - 2.0)
		var travel := ease(age / RISE, 0.65)
		var head := source.lerp(at, travel)
		var tail := source.lerp(at, maxf(0.0, travel - 0.13))
		ci.draw_line(tail, head, Color(tint, 0.24), 7.0, true)
		ci.draw_line(tail, head, Color(tint.lerp(Color.WHITE, 0.42), 0.82), 3.0, true)
		ci.draw_circle(head, 2.55, tint.lerp(Color.WHITE, 0.73))
		return
	var bloom := age - RISE
	_water_glints(ci, at.x, sea, tint, bloom, size)
	_draw_firework(ci, at, tint, bloom, size, sea, hue)

static func _draw_firework(ci, at: Vector2, tint: Color, bloom: float, size: float, sea: float, hue: String) -> void:
	var blue := hue == "blue"
	var gold := hue == "gold"
	var rays := 50 if blue else 36
	var ember_scale := sqrt(size)
	var seed := at.x * 0.089 + at.y * 0.041
	var width := 156.0 if blue else 104.0
	var tail := 1.09 if blue else 0.85
	var side := 1.0 if at.x < 180.0 else -1.0
	var drift := side * (13.0 if blue else -3.0)
	var opening := smoothstep(0.0, 0.14, bloom)
	var flare := opening * (1.0 - smoothstep(0.19, 0.95, bloom))
	_draw_glow(ci, at, tint, 83.0 * size, flare * 0.85)
	var fall_glow := opening * (1.0 - smoothstep(1.16, 2.68, bloom))
	var plume := at + Vector2(0, (25.0 * bloom * bloom - 13.0) * size)
	_draw_glow(ci, plume, tint, 150.0 * size, fall_glow * 0.27 * _above_sea(plume, sea))
	for ray in range(rays):
		var n := float(ray) / float(rays - 1)
		var fan := n * 2.0 - 1.0
		var wiggle := sin(ray * 3.97 + seed)
		var shoot := Vector2(fan * width + wiggle * 11.0, -19.0 - 45.0 * (1.0 - fan * fan) + wiggle * 19.0) * size
		var fall := (27.0 + 25.0 * n + wiggle * 7.0) * size
		if gold:
			var petal := Vector2.from_angle(TAU * n + seed)
			shoot = petal * Vector2(111.0, 76.0) * size * (0.86 + wiggle * 0.13)
			fall *= 0.69
		var end_time := 1.95 + 0.98 * (0.5 + 0.5 * sin(ray * 6.17 + seed))
		var strength := opening * (1.0 - smoothstep(end_time - 0.68, end_time, bloom))
		if strength <= 0.0:
			continue
		var head := _arc_point(at, shoot, fall, drift, bloom)
		var strand := tint.lerp(Color.WHITE, 0.29 + 0.24 * wiggle)
		var beam_width := (3.65 if blue else 3.15) * size * (0.92 + wiggle * 0.18)
		if ray % 9 == 0:
			_draw_glow(ci, head, tint, 51.0 * size, fall_glow * 0.50 * _above_sea(head, sea))
		var point := head
		for segment in range(1, 6):
			var fraction := segment / 5.0
			var sample_t := maxf(0.0, bloom - tail * fraction)
			var sample := _arc_point(at, shoot, fall, drift, sample_t)
			var alpha := strength * (1.16 - fraction * 0.89) * _above_sea(point, sea)
			if alpha > 0.015:
				var core := beam_width * lerpf(1.0, 0.42, fraction)
				ci.draw_line(sample, point, Color(tint, alpha * 0.28), core * 2.1)
				ci.draw_line(sample, point, Color(strand, alpha), core, true)
			point = sample
		var sparkle := (0.72 + 0.28 * sin(bloom * 24.0 + ray * 4.83)) * strength
		_spark(ci, head, sea, strand.lerp(Color.WHITE, 0.73), sparkle, 2.35 + size * 0.95)
		# Offset embers give each trail width and texture as it falls.
		for ember in range(5):
			var sample_t := maxf(0.0, bloom - 0.08 - 0.15 * ember - 0.07 * wiggle)
			var fleck := _arc_point(at, shoot, fall, drift, sample_t)
			fleck += Vector2(sin(ray * 8.13 + ember * 2.6) * 16.0, 6.0 + 8.0 * ember) * bloom
			var glimmer := 0.66 + 0.34 * sin(bloom * 29.0 + ray * 13.1 + ember * 2.9)
			var fleck_size := lerpf(1.45, 2.55, glimmer) * ember_scale
			_spark(ci, fleck, sea, strand.lerp(Color.WHITE, glimmer * 0.64), strength * glimmer * (0.88 - 0.13 * ember), fleck_size)

static func _draw_glow(ci, center: Vector2, tint: Color, size: float, alpha: float) -> void:
	if alpha <= 0.025:
		return
	if not _glow:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.68, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.82), Color(1, 1, 1, 0.37), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
	ci.draw_texture_rect(_glow, Rect2(center - Vector2.ONE * size * 0.5, Vector2.ONE * size), false, Color(tint, alpha))

static func _arc_point(at: Vector2, shoot: Vector2, fall: float, drift: float, age: float) -> Vector2:
	var elapsed_squared := age * age
	return at + shoot * (1.0 - exp(-age * 2.8)) + Vector2(drift, fall) * elapsed_squared

static func _above_sea(point: Vector2, sea: float) -> float:
	return 1.0 - smoothstep(sea - 29.0, sea - 3.0, point.y)

static func _spark(ci, p: Vector2, sea: float, tint: Color, alpha: float, size: float) -> void:
	var visible := alpha * _above_sea(p, sea)
	if visible > 0.025:
		ci.draw_rect(Rect2(p.round(), Vector2.ONE * size), Color(tint, visible))

static func _water_glints(ci, x: float, sea: float, tint: Color, bloom: float, size: float) -> void:
	var energy := smoothstep(0.0, 0.23, bloom) * (1.0 - smoothstep(1.15, LIFE - RISE, bloom))
	# Short, broken strokes follow the water, under the onshore silhouettes.
	var shore := lerpf(40.0, 20.0, clampf(x / 360.0, 0.0, 1.0))
	for row in range(11):
		var depth := row / 10.0
		var y := sea + 3.0 + depth * shore
		for piece in range(2):
			var wave := sin(bloom * 3.7 + row * 2.59 + piece * 1.42)
			var center := x + (wave * 14.0 + (piece - 0.5) * lerpf(13.0, 39.0, depth)) * size
			var span := lerpf(4.0, 15.0, depth) * (0.65 + absf(wave) * 0.35) * size
			var alpha := energy * (0.25 + 0.34 * absf(wave)) * (1.0 - 0.70 * depth)
			ci.draw_line(Vector2(center - span, y), Vector2(center + span, y), Color(tint.lerp(Color.WHITE, 0.26), alpha), lerpf(2.0, 1.4, depth))
