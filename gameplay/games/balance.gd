extends RefCounted
## Balancing daily demands. Full bars wait; there is no failure.
var r
var phase := "active"
var t := 0.0
var levels := [0.25,0.4,0.2]
var touches := 0
var tended: Array = []
var glow := [0.0,0.0,0.0]
const LABELS := ["工作的压力","家人的相处","异地的摩擦"]
func start(runner,_beat: Dictionary) -> void:
	r = runner
	r.hint = ""
func rect(i: int) -> Rect2: return Rect2(28,494+i*39,304,34)  # 三张并排压在最下沿，只挡到小腿，不再从腰盖到腿
func process(dt: float) -> bool:
	t += dt
	if phase == "active":
		for i in range(3):
			if i not in tended: levels[i] = minf(1, levels[i] + dt * (0.08 + i * 0.01))
			glow[i] = maxf(0, glow[i] - dt)
		if tended.size() == LABELS.size() and glow.max() <= 0:
			phase = "done"
			r.hint = ""
	return phase == "done"
func input(kind: String,pos: Vector2) -> void:
	if kind!="tap" or phase!="active":return
	for i in range(3):
		if i in tended or not rect(i).has_point(pos): continue
		levels[i] = 0.0
		glow[i] = 0.5
		if i not in tended:
			tended.append(i)
			touches = maxi(touches, tended.size())
		r.play("pop")
		return
const ICON_COLOR := [Color("#5f7ea8"), Color("#c9824f"), Color("#d0607a")]

static func _box(fill: Color, border: Color, radius: int, bw: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(bw)
	b.set_corner_radius_all(radius)
	b.anti_aliasing = true
	return b

## 小图标：公文包、房子、爱心，用几笔画出来，跟像素风一致
func _icon(ci, i: int, c: Vector2, col: Color) -> void:
	match i:
		0:
			ci.draw_rect(Rect2(c + Vector2(-8, -4), Vector2(16, 11)), col)
			ci.draw_rect(Rect2(c + Vector2(-3, -7), Vector2(6, 3)), col, false, 1.5)
			ci.draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), Color(1, 1, 1, 0.6), 1)
		1:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, 0), c + Vector2(0, -8), c + Vector2(9, 0)]), col)
			ci.draw_rect(Rect2(c + Vector2(-6, 0), Vector2(12, 8)), col)
			ci.draw_rect(Rect2(c + Vector2(-2, 3), Vector2(4, 5)), Color(1, 1, 1, 0.7))
		2:
			ci.draw_circle(c + Vector2(-4, -2), 4.4, col)
			ci.draw_circle(c + Vector2(4, -2), 4.4, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8.2, -0.5), c + Vector2(8.2, -0.5), c + Vector2(0, 8)]), col)

func draw(ci) -> void:
	var panel := Rect2(18, 438, 324, 190)
	ci.draw_style_box(_box(Color(0.10, 0.08, 0.10, 0.91), Color("#ba9767"), 12, 1), panel)
	ci.text_at(Vector2(30, 462), "一起度过忙碌的日子", 16, ci.PAPER, 312)
	ci.text_at(Vector2(30, 483), "每件事都照顾一次，不用抢时间", 13, Color("#efd4ae"), 312)
	for i in range(3):
		var box:=rect(i)
		var lift: float = glow[i] * 4.0
		box.position.y -= lift
		# 投影 + 半透明纸面圆角卡片，细金边
		ci.draw_style_box(_box(Color(0, 0, 0, 0.28), Color(0, 0, 0, 0), 10, 0), Rect2(box.position + Vector2(0, 3), box.size))
		ci.draw_style_box(_box(Color("#fff7ea", 0.93), Color("#c9a15a") if levels[i] <= .8 else Color("#d9775a"), 10, 2), box)
		_icon(ci, i, box.position + Vector2(20, 18), ICON_COLOR[i])
		ci.text_at(box.position + Vector2(34, 22), LABELS[i], 14, ci.INK, 126, HORIZONTAL_ALIGNMENT_LEFT)
		if i in tended:
			ci.text_at(box.position + Vector2(166, 22), "已照顾", 13, Color("#426b51"), 126)
			continue
		var track := Rect2(box.position + Vector2(166, 13), Vector2(126, 8))
		ci.draw_style_box(_box(Color("#e5d6bf"), Color(0, 0, 0, 0), 4, 0), track)
		var full: bool = levels[i] > .8
		if levels[i] > 0.02:
			ci.draw_style_box(_box(Color("#e07a5f") if full else Color("#7fb08e"), Color(0, 0, 0, 0), 4, 0), Rect2(track.position, Vector2(maxf(8, track.size.x * levels[i]), 8)))
		if full:
			var pulse := 0.5 + 0.5 * sin(t * 8.0)
			ci.draw_style_box(_box(Color(0, 0, 0, 0), Color("#e07a5f", 0.5 * pulse), 12, 2), box.grow(3))
	ci.text_at(Vector2(30, 618), "%d / 3 项已照顾" % touches, 12, ci.PAPER, 110, HORIZONTAL_ALIGNMENT_LEFT)
	var progress := float(tended.size()) / LABELS.size()
	ci.draw_style_box(_box(Color("#533e42"), Color.TRANSPARENT, 2, 0), Rect2(149, 610, 140, 5))
	ci.draw_style_box(_box(Color("#b79260"), Color.TRANSPARENT, 2, 0), Rect2(149, 610, 140 * progress, 5))
