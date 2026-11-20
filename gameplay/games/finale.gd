extends RefCounted
## 两个视角共用同一封信。寄信时看落笔，收到后才看见全文。

const LOOKS := ["01", "02", "03", "04", "05", "06", "07", "08"]

var r
var phase := "read"
var read_index := 0
var send_caption := ""
var typed := 0.0
var dragging := false
var from := Vector2.ZERO
var open_progress := 0.0
var t := 0.0
var edit: LineEdit
var error := false
const SEND_TIME := 3.3   # 寄信过场：书桌窗口飞出 → 飞过江岸 → 落到收件人桌上
const LETTER := "w2/finale/invite_card.png|w2/finale/letter_closeup.png"
## GPT 重画的邀请函到位后，字写在中间留白处（顶部是插画）
const NEW_CARD := "w2/finale/invite_card.png"
const GUEST_DESK := "w2/finale/guest_first_person.png"
const TRAVEL_CHOICES := [
	{"label": "去婚礼现场", "scene": "res://hongyuan/world_entry.tscn"},
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
var tex_cache := {}
var keyboard_callback: JavaScriptObject
var keyboard_open := false


func start(runner, _beat: Dictionary) -> void:
	r = runner
	send_caption = "\n".join(r.StoryCaption.chapter_coda("finale").get("pages", []))


func process(dt: float) -> bool:
	t += dt
	match phase:
		"write":
			if t > 2.3: _set_phase("written")
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
	var salutation: String = "亲爱的朋友：" if name == SKIP_NAME_AS or name.strip_edges().is_empty() else r.t_("A7-LETTER-TO").replace("{名字}", name)
	# Preserve the approved signature/date spacing instead of unit-normalizing it.
	var closing: String = str(r.copy.get("A7-1e", r.t_("A7-1e"))).replace("<br>", "\n")
	return "\n".join([salutation, r.t_("A7-1a"), r.t_("A7-1c"), closing])

func _ok_rect(phase_name := "") -> Rect2:
	if phase_name == "look":
		return Rect2(100, 603, 160, 36)
	return Rect2(100, 560, 160, 48)

const LOOK_PANEL_Y := 50.0
const LOOK_CELL_W := 180.0
const LOOK_CELL_H := 138.0

func _look_rect(i: int) -> Rect2:
	return Rect2((i % 2) * LOOK_CELL_W, LOOK_PANEL_Y + (i / 2) * LOOK_CELL_H, LOOK_CELL_W, LOOK_CELL_H)

func _envelope() -> Rect2:
	return Rect2(68, 315, 224, 151) if phase in ["receive", "opening"] else Rect2(50, 218, 260, 165)

func _route_rect(i: int) -> Rect2:
	return Rect2(48, 463 + i * 52, 264, 45)

func _accept_invitation() -> void:
	look = clampi(look, 0, LOOKS.size() - 1)
	r.result = {"name": name, "look": LOOKS[look]}
	_set_phase("destination")
	r.invitation_accepted.emit()

func input(kind: String, pos: Vector2) -> void:
	match phase:
		"read":
			if kind == "tap" and t > 0.6:
				if read_index < 2:
					read_index += 1
					t = 0.0
				else:
					_set_phase("name")
					_make_edit()
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
			if kind == "tap" and t > 0.5: _set_phase("look")
		"look":
			if kind == "tap":
				for i in range(LOOKS.size()):
					if _look_rect(i).has_point(pos):
						look = i
						r.play("blip")
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
	if phase in ["receive", "opening", "read_received", "look", "destination"]:
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
	error = false
	keyboard_open = false
	phase = "write"
	typed = 0.0
	t = 0.0
	r.play("pop")


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
	error = false
	edit.queue_free()
	edit = null
	phase = "write"
	typed = 0.0
	t = 0.0
	r.play("pop")


func _guest(i: int) -> Texture2D:
	var id: String = LOOKS[i]
	if not tex_cache.has(id):
		var path := "res://hongyuan/assets/w2/finale/chr_LM-GUEST-07.png" if id == "07" else "res://assets/characters/lm/chr_LM-GUEST-%s.png" % id
		tex_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return tex_cache[id]


func draw(ci) -> void:
	var desk = preload("res://hongyuan/ui/desk_art.gd")
	if phase == "welcome":
		# 新欢迎图把两人画在门里，整张铺满，不再叠旧人物
		desk.cover(ci, ci.texture("round1/common/welcome_entrance_r2.png"), r.view_rect)
	elif phase == "send":
		_send_frames(ci)
		ci.StoryCaption.draw_low_narration(ci, send_caption, send_caption.length())
		return
	elif phase in ["receive", "opening", "read_received", "look", "destination"]:
		desk.cover(ci, ci.texture(GUEST_DESK), r.view_rect)
	else:
		desk.draw(ci, r.materials, r.view_rect, "", t, false, phase in ["write", "written"])
	match phase:
		"read":
			var copy_id: String = ["R1-I02-REUNION", "R1-I02-YOU", "A7-2b"][read_index]
			ci.StoryCaption.draw_caption(ci, ci.t_(copy_id), "ayu", -1, false, desk.head(r.view_rect))
			ci.pill(_ok_rect(), "写下名字" if read_index == 2 else "轻点继续", 18, ci.RED, ci.PAPER)
		"name":
			ci.draw_rect(Rect2(30,432,300,112),Color(ci.PAPER,0.96))
			ci.text_at(Vector2(42,458),ci.t_("A7-I1"),16,ci.INK,276)
			ci.text_at(Vector2(42,533),ci.t_(error_key) if error else ci.t_("A7-I2"),13,ci.WOOD,276)
			ci.pill(_ok_rect(), ci.t_("G-19"), 18, ci.RED, ci.PAPER)
			ci.pill(SKIP_NAME, "键盘没弹出来？点这里先跳过", 13, Color(ci.INK, 0.72), ci.PAPER)
		"write", "written":
			_draw_desk_words(ci, minf(1.0, t / 2.3) if phase == "write" else 1.0)
			var ink_alpha := minf(1.0, t / 0.6) if phase == "write" else 1.0
			ci.draw_rect(Rect2(66, 478, 228, 42), Color(ci.INK, ink_alpha * 0.82))
			ci.text_at(Vector2(70, 504), "收件人 · " + name, 17, Color(ci.PAPER, ink_alpha), 220)
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
				ci.pill(_ok_rect(), "寄出邀请函", 18, ci.RED, ci.PAPER)
		"receive":
			var rect := _envelope()
			ci.draw_set_transform(Vector2(24 * open_progress, 0))
			_envelope_art(ci, true)
			ci.draw_set_transform(Vector2.ZERO)
			ci.StoryCaption.draw_caption(ci, "你收到了一封邀请函", "narrator")
			if dragging:
				ci.draw_line(Vector2(rect.position.x, rect.end.y + 8), Vector2(rect.position.x + rect.size.x * open_progress, rect.end.y + 8), ci.GOLD, 3)
			ci.pill(Rect2(48, 525, 264, 44), "按住信封，向右拖动拆开", 16, ci.RED, ci.PAPER)
		"opening":
			var k := clampf(t / 0.8, 0, 1)
			var open_art: Texture2D = ci.texture("round1/finale/mail_02_open.png" if k < 0.5 else "round1/finale/mail_03_pull.png")
			if open_art: ci.draw_texture_rect_region(open_art, Rect2(68, 279 - k * 52, 224, 257), Rect2(27, 5, 306, 351))
		"read_received":
			_paper(ci, _letter().length())
			ci.pill(_ok_rect(), "收下这份邀请", 18, ci.RED, ci.PAPER)
		"look":
			ci.text_at(Vector2(30, 22), ci.t_("G-CHOOSE-LOOK"), 18, ci.PAPER, 300)
			var panel: Texture2D = ci.texture("round1/people/choose_look_panel.png")
			if panel:
				# Panel 720×1100 → 360×550 at 0.5×
				ci.draw_texture_rect(panel, Rect2(0, LOOK_PANEL_Y, 360, 550), false)
				var hi: Texture2D = ci.texture("round1/people/choose_look_highlight.png")
				if hi and look >= 0:
					var rr := _look_rect(look)
					ci.draw_texture_rect(hi, Rect2(rr.position + Vector2(2, 2), rr.size - Vector2(4, 4)), false)
			else:
				for i in range(LOOKS.size()):
					var rr := _look_rect(i)
					ci.draw_rect(rr, ci.PAPER if i != look else Color("#ffe6a8"))
					ci.draw_rect(rr, ci.GOLD if i == look else ci.WOOD, false, 3 if i == look else 2)
					var guest := _guest(i)
					if guest: ci.draw_texture_rect_region(guest, Rect2(rr.position + Vector2(1, 0), Vector2(64, 84)), Rect2(0, 0, 64, 84))
			if look >= 0: ci.pill(_ok_rect("look"), ci.t_("G-19"), 16, ci.RED, ci.PAPER)
		"destination":
			var curtain := 1.0 - smoothstep(0.0, 0.35, t)
			var opened: Texture2D = ci.texture("round1/finale/mail_03_pull.png")
			if opened:
				ci.draw_texture_rect_region(opened, Rect2(108, 203, 144, 165), Rect2(27, 5, 306, 351))
			ci.text_at(Vector2(24, 126), "赴约", 28, ci.PAPER, 312)
			for i in range(TRAVEL_CHOICES.size()):
				ci.pill(_route_rect(i), TRAVEL_CHOICES[i].label, 17 if i < 2 else 14,
					ci.RED if i < 2 else Color(ci.INK, 0.83), ci.PAPER)
			if curtain > 0: ci.draw_rect(r.view_rect, Color(0, 0, 0, 0.55 * curtain))

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

func _paper(ci, length: int) -> void:
	var desk = preload("res://hongyuan/ui/desk_art.gd")
	# 正面信纸特写占满屏幕，字一行一行写上去，手机上也看得清
	if phase == "read_received":
		desk.cover(ci, ci.texture(LETTER), r.view_rect)
	var fancy: bool = ci.texture(NEW_CARD) != null
	var fs := 15 if fancy else 18
	var width := 220.0 if fancy else 248.0
	var origin := Vector2(72, 304) if fancy else Vector2(56, 120)
	var step := 23.0 if fancy else 30.0
	var letter := _letter()
	# Layout the full letter before revealing a character so lines never reflow while typing.
	while fs > 11 and _letter_lines(ci, letter, fs, width).size() * step > 238:
		fs -= 1
		step = fs + 5.0
	var row := 0
	var remaining := length
	for paragraph: String in letter.split("\n"):
		for line in _letter_lines(ci, paragraph, fs, width):
			if remaining <= 0:
				return
			ci.draw_string(ci.FONT, origin + Vector2(0, row * step), line.left(remaining), HORIZONTAL_ALIGNMENT_LEFT, width, fs, ci.INK)
			remaining -= line.length()
			row += 1
		remaining -= 1

func _envelope_art(ci, sealed: bool, at := Rect2()) -> void:
	var rect: Rect2 = at if at.has_area() else _envelope()
	var art: Texture2D = ci.texture("round1/finale/mail_01_closed.png")
	if art:
		ci.draw_texture_rect_region(art, rect, Rect2(27, 137, 306, 219))
	ci.text_at(rect.position + Vector2(15, rect.size.y - 18), name, 17, ci.INK, rect.size.x - 30)
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


func _draw_desk_words(ci, progress: float) -> void:
	var desk = preload("res://hongyuan/ui/desk_art.gd")
	ci.draw_set_transform_matrix(desk.paper_transform(r.view_rect))
	_draw_sheet_words(ci, Vector2(4, 21), 205, 12, 16, int(_letter().length() * progress))
	ci.draw_set_transform(Vector2.ZERO)

func _draw_sheet_words(ci, origin: Vector2, width: float, font_size: int, line_step: float, length: int) -> void:
	var remaining := length
	var row := 0
	for paragraph: String in _letter().split("\n"):
		for line: String in _letter_lines(ci, paragraph, font_size, width):
			if remaining <= 0: return
			ci.draw_string(ci.FONT, origin + Vector2(0, row * line_step), line.left(remaining), HORIZONTAL_ALIGNMENT_LEFT, width, font_size, ci.INK)
			remaining -= line.length()
			row += 1
		remaining -= 1

func _draw_folding_letter(ci) -> void:
	var desk = preload("res://hongyuan/ui/desk_art.gd")
	_envelope_art(ci, false)
	var k := smoothstep(0.0, 1.0, clampf(t / 1.3, 0.0, 1.0))
	var page := Rect2(Vector2(70, 130).lerp(Vector2(75, 280), k), Vector2(210, 260).lerp(Vector2(210, 95), k))
	# Paper and ink share one transform. Folded backs and the envelope front
	# occlude both, rather than replacing the written letter with a blank sheet.
	ci.draw_set_transform(page.position, 0, page.size / Vector2(210, 260))
	desk.paper_art(ci, Rect2(0, 0, 210, 260))
	_draw_sheet_words(ci, Vector2(14, 28), 182, 11, 15, _letter().length())
	var fold := smoothstep(0.12, 0.62, k)
	if fold > 0:
		ci.draw_rect(Rect2(1, 88, 208, 82 * fold), Color("#e8d5ae"))
		ci.draw_line(Vector2(1, 88), Vector2(209, 88), Color("#b89c71"), 1)
	ci.draw_set_transform(Vector2.ZERO)
	var art: Texture2D = ci.texture("round1/finale/mail_01_closed.png")
	if art:
		var rect := _envelope()
		var front_y := rect.position.y + rect.size.y * 0.42
		ci.draw_texture_rect_region(art, Rect2(rect.position.x, front_y, rect.size.x, rect.end.y - front_y), Rect2(27, 137 + 219 * 0.42, 306, 219 * 0.58))
