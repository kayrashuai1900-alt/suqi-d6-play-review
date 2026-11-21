extends RefCounted
var r
var phase := "care"
var t := 0.0
var cleared: Array = []
var thinned: Array = []
var cloud_rounds: Array = [0,0,0,0,0,0]
var cloud_arrivals: Array = [0.0,0.8,2.5,2.9,4.6,5.0]
var cloud_words: Array = [0,1,2,3,4,5]
var dragging := false
var pointer := Vector2.ZERO
var pops: Array = []   # [中心, 剩余时间]：泡泡碎开的动画
const CENTERS := [Vector2(162,145), Vector2(72,245), Vector2(268,221), Vector2(168,258), Vector2(281,360), Vector2(75,382)]
const WORDS := ["找工作的事", "手头的项目", "今天又加班", "家里的牵挂", "异地的摩擦", "下班还在忙",
	"换工作怎么办", "见面要等多久", "两地来回跑", "以后住在哪儿"]
const DOUBLE := [2,4]
const LIMIT := 10
const PROGRESS := Rect2(112, 324, 136, 31)
const TRAY := Rect2(28,538,304,82)
const HEART_CENTER := Vector2(66, 586)
const INSTRUCTION := "往上拖动 Toretto 的爱心，消解阿鱼的愁云"
func start(runner,_beat: Dictionary) -> void:
	r = runner
	r.hint = ""
func visible_at(index: int) -> bool:
	return phase == "care" and cloud_type(index) >= 0 and t >= float(cloud_arrivals[index])

func cloud_type(index: int) -> int:
	return int(cloud_words[index])

func center(index: int) -> Vector2:
	var age := maxf(0.0,t-float(cloud_arrivals[index]))
	return CENTERS[index] + Vector2(sin(age*0.95+index)*18.0, cos(age*1.2+index)*10.0 + 12.0*exp(-age*4))
func group_count() -> int:
	var count := 0
	for rounds in cloud_rounds: count += int(rounds)
	return count
func restore_checkpoint() -> void:
	# Older saves counted each slot's clearances but had no distinct labels.
	if group_count() > 0 and cloud_words == [0,1,2,3,4,5]:
		var outstanding := LIMIT - group_count()
		for index in cloud_words.size():
			cloud_words[index] = index if index < outstanding else -1
	for index in CENTERS.size():
		if index in cleared:
			if int(cloud_rounds[index]) == 0: _renew(index)
	cleared.clear()
	_finish_if_ready()

func _finish_if_ready() -> void:
	if phase == "care" and group_count() >= LIMIT:
		phase = "settle"
		t = 0
		dragging = false

func _renew(index: int) -> void:
	cloud_rounds[index] = int(cloud_rounds[index]) + 1
	var next_word := CENTERS.size() + group_count() - 1
	cloud_words[index] = next_word if next_word < LIMIT else -1
	cloud_arrivals[index] = t + 2.2 + 0.3 * ((index + int(cloud_rounds[index])) % 4)
	thinned.erase(index)
func process(dt: float) -> bool:
	t += dt
	for p in pops: p[1] = float(p[1]) - dt
	pops = pops.filter(func(p) -> bool: return float(p[1]) > 0.0)
	if phase == "settle" and t > 1.6: phase = "done"
	return phase == "done"
func input(kind: String,pos: Vector2) -> void:
	if phase != "care": return
	if kind == "down": dragging = TRAY.has_point(pos);pointer = pos
	elif kind == "move" and dragging: pointer = pos
	elif kind == "up" and dragging:
		dragging = false
		var hit := -1
		for i in CENTERS.size():
			if visible_at(i) and pos.distance_to(center(i)) < 42: hit = i;break
		if hit >= 0:
			r.play("pop");pops.append([center(hit),0.5])
			if cloud_type(hit) in DOUBLE and hit not in thinned:
				thinned.append(hit)
				return
			_renew(hit)
			_finish_if_ready()
func draw(ci) -> void:
	var relief: Texture2D = ci.texture("w2/call/office_relief.png")
	if relief and group_count() > 0:
		var area: Rect2 = ci.view_rect
		var k := maxf(area.size.x / relief.get_width(), area.size.y / relief.get_height())
		var origin := area.get_center() - relief.get_size() * k * 0.5
		var strength := minf(1.0, float(group_count()) / 5.0)
		ci.draw_texture_rect_region(relief, area, Rect2((area.position - origin) / k, area.size / k), Color(1, 1, 1, strength))
	for i in CENTERS.size():
		if not visible_at(i): continue
		var c: Vector2 = center(i).round()
		if cloud_type(i) in DOUBLE and i not in thinned:
			_bubble(ci,c+Vector2(12,-13),43)
		_bubble(ci,c,43)
		ci.text_at(c-Vector2(47,-5),WORDS[cloud_type(i)],13,ci.PAPER,94)
		if cloud_type(i) in DOUBLE and i not in thinned:
			ci.pill(Rect2(c+Vector2(23,-35),Vector2(42,20)),"两层",12,ci.INK,ci.PAPER)
	for p in pops:
		var k := 1.0 - float(p[1]) / 0.5
		var pop_tex: Texture2D = ci.texture("w2/call/worry_pop_%d.png" % mini(3, 1 + int(k * 3.0)))
		if pop_tex:
			ci.draw_texture_rect(pop_tex, _bubble_rect(p[0]), false)
			continue
		for j in range(8):
			var a := TAU * j / 8.0
			var q: Vector2 = (p[0] as Vector2) + Vector2(cos(a),sin(a)) * (30 + 30 * k)
			ci.draw_rect(Rect2(q.round() - Vector2(3,3),Vector2(6,6)),Color(0.62,0.72,0.95,1.0 - k))
	ci.pill(PROGRESS, "已消除 %d/%d" % [mini(group_count(), LIMIT), LIMIT], 15, Color(ci.INK, 0.84), ci.PAPER)
	if phase != "care": return
	ci.pill(TRAY, "", 16, Color("#f5dfbe"), ci.INK)
	ci.text_at(Vector2(105, 566), INSTRUCTION, 14, ci.INK, 212)
	_heart(ci, HEART_CENTER, 2.8)
	if group_count() == 0 and not dragging:
		# 往上拖提示：GPT 画的手形图标（64×96）优先，没有就退回箭头
		var rise := fposmod(t, 1.1) / 1.1
		var a := HEART_CENTER + Vector2(0, -69 - rise * 34)
		var tint := Color(1, 1, 1, 1.0 - rise)
		var hand_tex: Texture2D = ci.texture("w2/call/care_hand.png")
		if hand_tex:
			ci.draw_texture_rect(hand_tex, Rect2(a - Vector2(16, 24), Vector2(32, 48)), false, tint)
		else:
			ci.draw_colored_polygon(PackedVector2Array([a + Vector2(0, -12), a + Vector2(12, 4), a + Vector2(5, 4), a + Vector2(5, 16), a + Vector2(-5, 16), a + Vector2(-5, 4), a + Vector2(-12, 4)]), Color(PIXEL_HEART, 1.0 - rise))
	if dragging:
		_heart(ci, pointer, 4.0)

const PIXEL_HEART := Color("#e5484d")
const HEART_ROWS := ["01100110", "11111111", "11111111", "11111111", "01111110", "00111100", "00011000"]

## 像素爱心：优先用 GPT 的 care_heart.png，没有就按点阵画。c 是中心，px 是每个方块的边长。
func _heart(ci, c: Vector2, px: float) -> void:
	var tex: Texture2D = ci.texture("w2/call/care_heart.png|")
	if tex:
		ci.draw_texture_rect(tex, Rect2(c - Vector2(8, 8) * px, Vector2(16, 16) * px), false)
		return
	var origin := c - Vector2(HEART_ROWS[0].length(), HEART_ROWS.size()) * px * 0.5
	for y in range(HEART_ROWS.size()):
		for x in range(HEART_ROWS[y].length()):
			if HEART_ROWS[y][x] == "1":
				var shade := PIXEL_HEART.lightened(0.35) if (y <= 1 and x in [1, 2]) else PIXEL_HEART
				ci.draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px, px)), shade)

## GPT 像素泡泡 64×64，云朵本体中心在 (32,29)，按 3 倍最近邻放大，本体约 102×54
func _bubble_rect(c: Vector2) -> Rect2:
	return Rect2(c - Vector2(32, 29) * 3.0, Vector2(192, 192))

## 没有图时退回画的泡泡：深色圆 + 2px 浅色描边 + 左上角方块高光
func _bubble(ci, c: Vector2, rad: float) -> void:
	var tex: Texture2D = ci.texture("w2/call/worry_bubble.png")
	if tex:
		ci.draw_texture_rect(tex, _bubble_rect(c), false)
		return
	ci.draw_circle(c,rad,Color(0.20,0.24,0.36,0.88))
	ci.draw_arc(c,rad-1,0,TAU,24,Color(0.55,0.62,0.82,0.9),2)
	ci.draw_rect(Rect2(c + Vector2(-rad*0.55,-rad*0.6),Vector2(8,8)),Color(0.85,0.9,1.0,0.7))
	ci.draw_rect(Rect2(c + Vector2(-rad*0.55+10,-rad*0.6+2),Vector2(4,4)),Color(0.85,0.9,1.0,0.5))
