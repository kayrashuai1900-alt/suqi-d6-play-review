extends RefCounted
## 两个视角共用同一封信。寄信时看落笔，收到后才看见全文。

const LOOKS := ["01", "02", "03", "04", "05", "06", "07", "08"]
const DESK := preload("res://hongyuan/ui/desk_art.gd")
const GUEST_ATLAS := "res://assets/characters/lm/guest_atlas.png"
const GUEST_FRAME := Vector2(64, 84)
const GRIPS := [
	Vector2(45, 55), Vector2(32, 51), Vector2(29, 55), Vector2(44, 55),
	Vector2(46, 57), Vector2(28, 54), Vector2(43, 57), Vector2(32, 51),
]
const LOOK_PANEL := Rect2(22, 114, 316, 360)
const LOOK_CELL := Vector2(68, 121)
const LOOK_START := Vector2(34, 169)
const LOOK_STRIDE := Vector2(75, 130)
const INVITE_SIZE := Vector2(360, 640)
const WRITE_TIME := 3.8

var r
var phase := "read"
var closing_caption := ""
var dragging := false
var from := Vector2.ZERO
var open_progress := 0.0
var t := 0.0
var edit: LineEdit
var error := false
const SEND_TIME := 3.3   # 寄信过场：书桌窗口飞出 → 飞过江岸 → 落到收件人桌上
const LETTER := "w2/finale/invite_card.png|w2/finale/letter_closeup.png"
## GPT 重画的邀请函到位后，字写在中间留白处（顶部是插画）
const GUEST_DESK := "w2/finale/guest_first_person.png"
const ESTATE_GATE := preload("res://hongyuan/ui/travel_arrival.gd").WEDDING_ART
const TRAVEL_CHOICES := [
	{"label": "前往罗曼山庄", "scene": "res://hongyuan/world_entry.tscn"},
	{"label": "先去裳泓村", "scene": "res://hongyuan/village_entry.tscn"},
	{"label": "回首页", "scene": "res://hongyuan/boot.tscn"}
]
var error_key := "A7-E1"
const RESERVED_NAMES := ["阿鱼", "toretto", "新郎", "新娘", "主角"]
var look := -1
const SEAL_BAR := Rect2(65, 475, 230, 44)
var hold := 0.0
var holding := false
var name := ""
var name_confirmed := false
var guest_sheet: Texture2D
var keyboard_callback: JavaScriptObject
var keyboard_open := false


func start(runner, _beat: Dictionary) -> void:
	r = runner
	closing_caption = "\n".join(r.StoryCaption.chapter_coda("finale").get("pages", []))


func process(dt: float) -> bool:
	t += dt
	match phase:
		"write":
			if t >= WRITE_TIME: _set_phase("written")
		"fold":
			if t >= 1.3: _set_phase("seal")
		"seal":
			if holding:
				hold = minf(1.0, hold + dt)
				if hold >= 1.0:
					_set_phase("stamped")
					r.play("pop")
		"stamped":
			if t >= 1.2: _set_phase("ready_send")
		"send":
			if t >= SEND_TIME: _set_phase("receive")
		"opening":
			if t >= 0.8: _set_phase("read_received")
	return phase == "done"

func _set_phase(value: String) -> void:
	phase = value
	t = 0.0
	holding = false
	dragging = false
	r.play("blip")
	if value == "receive": r.music_requested.emit("prologue")

func _letter() -> String:
	# Preserve the approved signature/date spacing instead of unit-normalizing it.
	var closing: String = str(r.copy.get("A7-1e", r.t_("A7-1e"))).replace("<br>", "\n")
	return "\n".join(["亲爱的朋友：", r.t_("A7-1a"), r.t_("A7-1c"), closing])

func _ok_rect(phase_name := "") -> Rect2:
	if phase_name == "look":
		return Rect2(68, 504, 224, 48)
	return Rect2(100, 560, 160, 48)

func _look_rect(i: int) -> Rect2:
	return Rect2(LOOK_START + LOOK_STRIDE * Vector2(i % 4, floori(i / 4.0)), LOOK_CELL)

func _envelope() -> Rect2:
	return Rect2(68, 315, 224, 151) if phase in ["receive", "opening"] else Rect2(50, 218, 260, 165)

func _route_rect(i: int) -> Rect2:
	match i:
		0: return Rect2(36, 495, 288, 48)
		1: return Rect2(36, 554, 155, 44)
		_: return Rect2(201, 554, 123, 44)

func _accept_invitation() -> void:
	look = clampi(look, 0, LOOKS.size() - 1)
	r.result = {"name": name, "look": LOOKS[look]}
	_set_phase("destination")
	r.invitation_accepted.emit()

func input(kind: String, pos: Vector2) -> void:
	match phase:
		"read":
			if kind == "tap" and t > 0.6 and _ok_rect().has_point(pos):
				_set_phase("write")
		"name":
			if kind == "tap" and _ok_rect().grow(8).has_point(pos): _submit_name()
			elif kind == "tap" and SKIP_NAME.grow(6).has_point(pos): _skip_name()
		"written":
			if kind == "tap" and _ok_rect().has_point(pos): _set_phase("fold")
		"seal":
			# 按封口，或者按底部的「按住火漆」条，都算按住
			if kind == "down" and (pos.distance_to(_envelope().get_center()) <= 60 or SEAL_BAR.grow(8).has_point(pos)):
				holding = true
			elif kind == "up":
				holding = false
				hold = 0.0
			elif kind == "move" and pos.distance_to(_envelope().get_center()) > 76 and not SEAL_BAR.grow(30).has_point(pos):
				holding = false
				hold = 0.0
		"ready_send":
			if kind == "tap" and _ok_rect().has_point(pos): _set_phase("send")
		"receive":
			if t < 0.35: return
			# 要亲手撕开（只点不算）。电脑上用鼠标也好拆：信封附近按下往右拖都算，拖过六成松手也拆开
			if kind == "down" and _envelope().grow(60).has_point(pos):
				dragging = true
				from = pos
			elif kind == "move" and dragging:
				open_progress = clampf((pos.x - from.x) / 120.0, 0, 1)
				if open_progress >= 1.0: _set_phase("opening")
			elif kind == "up":
				dragging = false
				if open_progress >= 0.6: _set_phase("opening")
				open_progress = 0.0
		"read_received":
			if kind == "tap" and t > 0.5 and _ok_rect().has_point(pos):
				if name_confirmed:
					_set_phase("look")
				else:
					_set_phase("name")
					_make_edit()
		"look":
			if kind == "tap":
				for i in range(LOOKS.size()):
					if _look_rect(i).has_point(pos):
						look = i
						r.play("blip")
						return
				if look >= 0 and _ok_rect("look").has_point(pos):
					_accept_invitation()
		"welcome":
			if kind == "tap" and t > 0.6:
				_accept_invitation()
		"destination":
			if kind != "tap" or t < 0.35: return
			for i in range(TRAVEL_CHOICES.size()):
				if _route_rect(i).has_point(pos):
					r.scene_requested.emit(TRAVEL_CHOICES[i].scene)
					return

func restore_checkpoint() -> void:
	if phase in ["welcome", "done"]:
		_accept_invitation()
	if phase in ["receive", "opening", "read_received", "name", "look", "destination"]:
		r.music_requested.emit("prologue")
	# Old sealed saves predate sending/opening: continue with the physical letter.
	if phase == "stamped" and hold >= 1.0:
		t = minf(t, 1.2)
	holding = false
	dragging = false
	open_progress = 0.0
	# 进后台时手指还按着：回来要重新按满一秒
	if phase == "seal": hold = 0.0


func _make_edit() -> void:
	edit = LineEdit.new()
	edit.text = name
	edit.placeholder_text = "例如：小林"
	edit.max_length = 12
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.position = Vector2(48, 475)
	edit.size = Vector2(264, 40)
	edit.add_theme_font_override("font", r.FONT)
	edit.add_theme_font_size_override("font_size", 18)
	edit.add_theme_color_override("font_color", r.INK)
	edit.add_theme_color_override("font_placeholder_color", Color(r.WOOD, 0.55))
	var box := StyleBoxFlat.new()
	box.bg_color = r.PAPER
	box.border_color = r.WOOD
	box.set_border_width_all(2)
	edit.add_theme_stylebox_override("normal", box)
	edit.add_theme_stylebox_override("focus", box)
	edit.text_submitted.connect(func(_s: String) -> void: _submit_name())
	edit.text_changed.connect(func(_s: String) -> void: error = false)
	r.add_child(edit)
	if OS.has_feature("web") and OS.has_feature("hongyuan_wechat"):
		edit.virtual_keyboard_enabled = false
		edit.gui_input.connect(_wechat_name_input)
	elif OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		# 手机浏览器：键盘必须在手指点下的同一时刻由浏览器自己弹出，Godot 的输入框
		# 晚一帧才处理触摸，安卓会被拦掉。改用浏览器自带的输入对话框，一定弹得出来。
		edit.virtual_keyboard_enabled = false
		edit.placeholder_text = "点这里输入名字"
		edit.gui_input.connect(_web_name_input)
	else:
		edit.grab_focus()


var _last_name_tap := -10000

func _web_name_input(event: InputEvent) -> void:
	# 触摸松开和模拟出来的鼠标松开都收，同一下点按只弹一次框
	var released: bool = event is InputEventScreenTouch and not event.pressed and not event.canceled
	if event is InputEventMouseButton:
		released = event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	if not released or keyboard_open or phase != "name" or not is_instance_valid(edit):
		return
	if Time.get_ticks_msec() - _last_name_tap < 500:
		return
	_last_name_tap = Time.get_ticks_msec()
	keyboard_open = true
	var answer = JavaScriptBridge.eval("window.prompt(%s, %s)" % [JSON.stringify("请输入你的名字（2–12 个字）"), JSON.stringify(edit.text)], true)
	keyboard_open = false
	if answer == null or not is_instance_valid(edit):
		return
	edit.text = str(answer).strip_edges().substr(0, edit.max_length)
	error = false


func _wechat_name_input(event: InputEvent) -> void:
	var released: bool = event is InputEventScreenTouch and not event.pressed and not event.canceled
	if event is InputEventMouseButton:
		released = event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	if not released or keyboard_open or phase != "name":
		return
	var bridge := JavaScriptBridge.get_interface("hongyuanContent")
	if bridge == null:
		edit.placeholder_text = "输入框没连上，请退出小游戏再进"
		return
	keyboard_open = true
	keyboard_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
		keyboard_open = false
		if phase == "name" and is_instance_valid(edit) and not args.is_empty():
			edit.text = str(args[0])
	)
	bridge.editGuestName(edit.text, edit.max_length, keyboard_callback)


## 手机键盘偶尔拉不起来：允许先跳过，用「来做客的你」当名字，照样能写信、入席
const SKIP_NAME := Rect2(56, 612, 226, 24)
const SKIP_NAME_AS := "来做客的你"
func _skip_name() -> void:
	if is_instance_valid(edit):
		edit.queue_free()
	edit = null
	name = SKIP_NAME_AS
	_finish_name()


func _submit_name() -> void:
	var s := edit.text.strip_edges()
	if s.length() < 2 or s.length() > 12:
		error = true
		error_key = "A7-E1"
		r.play("blip")
		return
	# 主角的名字留给主角：婚礼现场服务端也会拒，这里先拦下，免得进场后没有退路
	if s.to_lower().replace(" ", "") in RESERVED_NAMES:
		error = true
		error_key = "A7-E2"
		r.play("blip")
		return
	name = s
	edit.queue_free()
	edit = null
	_finish_name()

func _finish_name() -> void:
	name_confirmed = true
	error = false
	keyboard_open = false
	_set_phase("look")

func _guest_frame(i: int) -> Rect2:
	return Rect2(Vector2(0, i * GUEST_FRAME.y), GUEST_FRAME)

func _draw_guest(ci, i: int, frame: Rect2) -> void:
	if guest_sheet == null and ResourceLoader.exists(GUEST_ATLAS):
		guest_sheet = load(GUEST_ATLAS)
	if guest_sheet:
		ci.draw_texture_rect_region(guest_sheet, frame, _guest_frame(i))


func draw(ci) -> void:
	if phase == "send":
		_send_frames(ci)
		return
	if phase in ["destination", "welcome"]:
		DESK.cover(ci, ci.texture(ESTATE_GATE), r.view_rect)
	elif phase in ["receive", "opening", "read_received", "name", "look"]:
		DESK.cover(ci, ci.texture(GUEST_DESK), r.view_rect)
	else:
		DESK.draw(ci, r.materials, r.view_rect, "", t, true, phase in ["write", "written"])
	match phase:
		"read":
			ci.StoryCaption.draw_caption(ci, ci.t_("A7-SENDER"), "ayu", -1, false, DESK.head(r.view_rect))
			ci.pill(_ok_rect(), "写邀请函", 18, ci.RED, ci.PAPER)
		"name":
			ci.draw_rect(Rect2(30,432,300,112),Color(ci.PAPER,0.96))
			ci.text_at(Vector2(42,458),ci.t_("A7-I1"),16,ci.INK,276)
			ci.text_at(Vector2(42,533),ci.t_(error_key) if error else ci.t_("A7-I2"),13,ci.WOOD,276)
			ci.pill(_ok_rect(), ci.t_("G-19"), 18, ci.RED, ci.PAPER)
			ci.pill(SKIP_NAME, "键盘没弹出来？点这里先跳过", 13, Color(ci.INK, 0.72), ci.PAPER)
		"write", "written":
			if phase == "write":
				DESK.move_writing_wrist(ci, r.view_rect, t, WRITE_TIME)
			if phase == "written":
				ci.pill(_ok_rect(), "装进信封", 18, ci.RED, ci.PAPER)
		"fold":
			_draw_folding_letter(ci)
		"seal", "stamped", "ready_send":
			_envelope_art(ci, phase != "seal" or hold > 0.0)
			var c := _envelope().get_center()
			if phase == "seal":
				var pulse := 0.5 + 0.5 * sin(t * 5.0)
				ci.draw_arc(c, 44 + 4 * pulse, 0, TAU, 40, Color(1, 0.88, 0.5, 0.4 + 0.4 * pulse), 2)
				ci.draw_arc(c, 38, -PI / 2, -PI / 2 + TAU * maxf(0.02, hold), 40, ci.GOLD, 4)
				ci.pill(SEAL_BAR, "按住火漆一秒", 18, ci.RED, ci.PAPER)
				if hold > 0: ci.draw_rect(Rect2(SEAL_BAR.position + Vector2(8, SEAL_BAR.size.y - 6), Vector2((SEAL_BAR.size.x - 16) * hold, 3)), ci.GOLD)
			elif phase == "ready_send":
				ci.pill(_ok_rect(), "帮她寄出", 18, ci.RED, ci.PAPER)
		"receive":
			var rect := _envelope()
			ci.draw_set_transform(Vector2(24 * open_progress, 0))
			_envelope_art(ci, true)
			ci.draw_set_transform(Vector2.ZERO)
			ci.StoryCaption.draw_caption(ci, "桌上落了一封信", "narrator")
			if dragging:
				ci.draw_line(Vector2(rect.position.x, rect.end.y + 8), Vector2(rect.position.x + rect.size.x * open_progress, rect.end.y + 8), ci.GOLD, 3)
			ci.pill(Rect2(48, 525, 264, 44), "按住信封，向右拖动拆开", 16, ci.RED, ci.PAPER)
		"opening":
			var k := clampf(t / 0.8, 0, 1)
			var open_art: Texture2D = ci.texture("round1/finale/mail_02_open.png")
			if open_art:
				ci.draw_texture_rect_region(open_art, Rect2(68, 235, 224, 257), Rect2(27, 5, 306, 351))
			var pull := smoothstep(0.30, 0.92, k)
			if pull > 0.0:
				_draw_invitation(ci, Rect2(Vector2(104, 328).lerp(Vector2(63, 88), pull), INVITE_SIZE * lerpf(0.42, 0.65, pull)), false)
				_draw_envelope_front(ci, Rect2(68, 341, 224, 151))
		"read_received":
			_draw_invitation(ci, Rect2(Vector2.ZERO, INVITE_SIZE))
			_draw_plaque(ci, Rect2(30, 34, 300, 42))
			ci.text_at(Vector2(36, 61), ci.t_("G-12"), 17, ci.PAPER, 288)
			ci.pill(_ok_rect(), "收下这份邀请", 18, ci.RED, ci.PAPER)
		"look":
			_draw_look(ci)
		"destination", "welcome":
			_draw_coda(ci)

func _draw_plaque(ci, rect: Rect2) -> void:
	ci.draw_rect(rect, Color("#381e18", 0.94))
	ci.draw_rect(rect.grow(-2), Color("#be9059"), false, 1.0)

func _draw_look(ci) -> void:
	ci.draw_rect(LOOK_PANEL.grow(3), Color("#351b17", 0.88))
	ci.draw_rect(LOOK_PANEL, Color("#f6e7c9"))
	ci.draw_rect(LOOK_PANEL.grow(-4), Color("#b48a59"), false, 1.0)
	ci.text_at(Vector2(34, 148), ci.t_("G-CHOOSE-LOOK"), 16, ci.INK, 292)
	for i in range(LOOKS.size()):
		var cell := _look_rect(i)
		var selected := i == look
		ci.draw_rect(cell, Color("#fff0bd") if selected else Color("#e8d5b3"))
		ci.draw_rect(cell, ci.RED if selected else Color("#b48a59"), false, 2.0 if selected else 1.0)
		var portrait_size := GUEST_FRAME * 1.23
		var portrait_at := cell.get_center() - portrait_size * 0.5
		_draw_guest(ci, i, Rect2(portrait_at, portrait_size))
	ci.pill(_ok_rect("look"), "确认形象", 17, ci.RED if look >= 0 else Color("#57433a"), ci.PAPER)

func _draw_coda(ci) -> void:
	var index := clampi(look, 0, LOOKS.size() - 1)
	var guest := Rect2(Vector2(62, 82), GUEST_FRAME * 3.68)
	ci.draw_rect(r.view_rect, Color("#301c1a", 0.14))
	_draw_plaque(ci, Rect2(103, 35, 154, 38))
	ci.text_at(Vector2(106, 60), "爱情篇 · 完", 18, ci.PAPER, 148)
	_draw_guest(ci, index, guest)
	var grip: Vector2 = GRIPS[index]
	var hand := guest.position + grip * guest.size / GUEST_FRAME
	var paper_size := INVITE_SIZE * 0.17
	var paper_at := hand - Vector2(8.0 if grip.x > 36.0 else paper_size.x * 0.5, 8.0)
	ci.draw_rect(Rect2(paper_at + Vector2(3, 4), paper_size), Color(ci.INK, 0.32))
	_draw_invitation(ci, Rect2(paper_at, paper_size))
	# The pixels around the original grip sit in front of the paper.
	if guest_sheet:
		var patch := Rect2(grip - Vector2(2, 1), Vector2(5, 4))
		var zoom := guest.size / GUEST_FRAME
		ci.draw_texture_rect_region(guest_sheet, Rect2(guest.position + patch.position * zoom, patch.size * zoom),
			Rect2(_guest_frame(index).position + patch.position, patch.size))
	_draw_plaque(ci, Rect2(26, 406, 308, 69))
	ci.text_at(Vector2(34, 433), closing_caption, 16, ci.PAPER, 292)
	for i in range(TRAVEL_CHOICES.size()):
		ci.pill(_route_rect(i), TRAVEL_CHOICES[i].label, 17 if i == 0 else 15,
			ci.RED if i == 0 else Color(ci.INK, 0.91), ci.PAPER)
	var curtain := 1.0 - smoothstep(0.0, 0.35, t)
	if curtain > 0.0:
		ci.draw_rect(r.view_rect, Color(ci.INK, 0.40 * curtain))

const LETTER_WORDS := ["四川乐山", "苏七镇", "罗曼山庄", "幸福的日子"]
const LETTER_TRAILING := "，。！？、；：）」』…"

func _letter_lines(ci, text: String, font_size := 20, width := 205.0) -> Array[String]:
	var result: Array[String] = []
	for paragraph: String in text.split("\n"):
		var line := ""
		var index := 0
		while index < paragraph.length():
			var unit := paragraph[index]
			for word: String in LETTER_WORDS:
				if paragraph.substr(index, word.length()) == word:
					unit = word
					break
			index += unit.length()
			while index < paragraph.length() and paragraph[index] in LETTER_TRAILING:
				unit += paragraph[index]
				index += 1
			if not line.is_empty() and ci.FONT.get_string_size(line + unit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				result.append(line)
				line = ""
			line += unit
		result.append(line)
	return result

## The recipient's close-up and the guest portrait use the same card.
func _draw_invitation(ci, frame: Rect2, readable := true) -> void:
	var paper: Texture2D = ci.texture(LETTER)
	if paper:
		ci.draw_texture_rect(paper, frame, false)
	else:
		ci.draw_rect(frame, ci.PAPER)
	if not readable:
		return
	ci.draw_set_transform(frame.position, 0.0, frame.size / INVITE_SIZE)
	var lines := _letter_lines(ci, _letter(), 16, 240.0)
	for row in range(lines.size()):
		ci.draw_string(ci.FONT, Vector2(60, 306 + row * 21), lines[row], HORIZONTAL_ALIGNMENT_LEFT, 240.0, 16, ci.INK)
	ci.draw_set_transform(Vector2.ZERO)

func _envelope_art(ci, sealed: bool, at := Rect2()) -> void:
	var rect: Rect2 = at if at.has_area() else _envelope()
	var art: Texture2D = ci.texture("round1/finale/mail_01_closed.png")
	if art:
		ci.draw_texture_rect_region(art, rect, Rect2(27, 137, 306, 219))
	if sealed:
		var file := "round1/finale/wax_03_seal.png"
		if phase == "seal": file = "round1/finale/wax_01_melt.png" if hold < 0.45 else "round1/finale/wax_02_press.png"
		var wax: Texture2D = ci.texture(file)
		if wax:
			ci.draw_texture_rect(wax, Rect2(rect.get_center() - Vector2(26,26), Vector2(52,52)), false)
		if phase == "seal" and hold >= 0.45:
			var stamp: Texture2D = ci.texture("round1/desk_r3/object_stamp.png")
			var lift := 9.0 * (1.0 - clampf((hold - 0.45) / 0.3, 0, 1))
			if stamp: ci.draw_texture_rect(stamp, Rect2(rect.get_center() - Vector2(25, 48 + lift), Vector2(50,50)), false)


## Follow the same sealed envelope into the recipient's hands; the last frame
## already uses the receive desk, so changing phase does not change the camera.
func _send_frames(ci) -> void:
	var span := SEND_TIME / 3.0
	if t < span:
		_cover_alpha(ci, "w2/finale/send_transition_1.png", 1.0)
	elif t < span * 2.0:
		_cover_alpha(ci, "w2/finale/send_transition_2.png", 1.0)
		var blend := smoothstep(0.0, 0.4, t - span)
		if blend < 1.0: _cover_alpha(ci, "w2/finale/send_transition_1.png", 1.0 - blend)
	else:
		_cover_alpha(ci, GUEST_DESK, 1.0)
		var elapsed := t - span * 2.0
		var blend := smoothstep(0.0, 0.35, elapsed)
		if blend < 1.0: _cover_alpha(ci, "w2/finale/send_transition_2.png", 1.0 - blend)
		var land := smoothstep(0.0, span - 0.18, elapsed)
		var rect := Rect2(Vector2(124, 155).lerp(Vector2(68, 315), land), Vector2(112, 75.5).lerp(Vector2(224, 151), land))
		_envelope_art(ci, true, rect)

func _cover_alpha(ci, file: String, alpha: float) -> void:
	var tex: Texture2D = ci.texture(file)
	if not tex: return
	var area: Rect2 = r.view_rect
	var scale := maxf(area.size.x / tex.get_width(), area.size.y / tex.get_height())
	var size := tex.get_size() * scale
	var rect := Rect2(area.get_center() - size * 0.5, size)
	ci.draw_texture_rect_region(tex, area, Rect2((area.position - rect.position) / scale, area.size / scale), Color(1, 1, 1, alpha))


func _draw_folding_letter(ci) -> void:
	_envelope_art(ci, false)
	var k := smoothstep(0.0, 1.0, clampf(t / 1.3, 0.0, 1.0))
	var page := Rect2(Vector2(76, 170).lerp(Vector2(80, 302), k), Vector2(208, 180).lerp(Vector2(200, 69), k))
	ci.draw_rect(page.grow(2.0), Color(ci.INK, 0.28))
	ci.draw_rect(page, Color("#f5e1b9"))
	var fold_y := page.position.y + page.size.y * lerpf(0.68, 0.48, k)
	ci.draw_rect(Rect2(page.position.x, fold_y, page.size.x, page.end.y - fold_y), Color("#e8cda0"))
	ci.draw_line(Vector2(page.position.x, fold_y), Vector2(page.end.x, fold_y), Color("#c8aa7b"))
	_draw_envelope_front(ci, _envelope())

func _draw_envelope_front(ci, rect: Rect2) -> void:
	var art: Texture2D = ci.texture("round1/finale/mail_01_closed.png")
	if art:
		var front_y := rect.position.y + rect.size.y * 0.42
		ci.draw_texture_rect_region(art, Rect2(rect.position.x, front_y, rect.size.x, rect.end.y - front_y), Rect2(27, 137 + 219 * 0.42, 306, 219 * 0.58))
