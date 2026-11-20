extends RefCounted
const PhoneShell := preload("res://hongyuan/ui/phone_shell.gd")
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
const DeskArt := preload("res://hongyuan/ui/desk_art.gd")
const SPLIT := "round1/people/call_split.png"
const HEADS := {"ayu": Vector2(507, 390), "toretto": Vector2(501, 1121)}
const SPLIT_Y := 901.0
## 来电：手机拿起来，显示「Toretto 来电」，阿鱼嘀咕一句，玩家亲手按接听；
## 接通后按住手机才播放字幕；松手保留当前句和进度。

const LETTERS_PER_SECOND := 12.0
const LINE_REST := 0.6

var r
var phase := "ring"   # wechat remains a legacy checkpoint key for spoken recollection.
var t := 0.0
var lines: Array = []
var li := 0
var reveal := 0.0
var aside := ""
var holding := false
var birthday_seen := false
var birthday_flash := 0.0
var call_time := 0.0
var hint_t := 0.0
var speaker_on := false
# 保留原先半夜消息的情节，以通话画面上的回忆旁白呈现；不中断语音通话。
var wechat: Array = []
var wi := 0
var wechat_done := false


func start(runner, beat: Dictionary) -> void:
	r = runner
	lines = beat.get("lines", [])
	aside = r.t_(str(beat.get("aside", "")))
	wechat = beat.get("wechat", [])
	r.play("blip")


func process(dt: float) -> bool:
	birthday_flash = maxf(0.0, birthday_flash - dt)
	if phase in ["talk", "birthday", "reply"]:
		call_time += dt
	if phase == "wechat":
		if holding:
			t += dt
			if t >= float(r.t_(str(wechat[wi].get("say", ""))).length()) / LETTERS_PER_SECOND + LINE_REST:
				wi += 1
				t = 0.0
				if wi >= wechat.size():
					wechat_done = true
					phase = "talk"
	elif phase == "ring":
		t += dt
		if fmod(t, 1.2) < dt:
			r.play("blip")
	elif phase == "talk":
		if not holding:
			hint_t += dt
			return false
		hint_t = 0.0
		t += dt
		var length := _line_text().length()
		reveal = minf(float(length), reveal + dt * LETTERS_PER_SECOND)
		if str(lines[li].get("say", "")) == "A3-2d" and reveal >= length:
			phase = "birthday"
			birthday_flash = 0.3 if not birthday_seen else 0.0
			birthday_seen = true
			r.pose = "surprised"
			r.play("pop")
			t = 0.0
			holding = false
		elif t >= float(length) / LETTERS_PER_SECOND + LINE_REST:
			li += 1
			reveal = 0.0
			t = 0.0
			if li == 1 and not wechat_done and not wechat.is_empty():
				phase = "wechat"
				wi = 0
				r.play("pop")
	elif phase == "birthday":
		t += dt
		if t >= LINE_REST:
			li += 1
			phase = "reply"
			reveal = _line_text().length()
			t = 0.0
	elif phase == "reply":
		t += dt
	elif phase == "hangup":
		t += dt
		if t >= 0.6:
			phase = "done"
	return phase == "done"


func restore_checkpoint() -> void:
	# Refresh replays the current sentence from its beginning, never a held finger.
	if phase == "wechat":
		wi = clampi(wi, 0, maxi(0, wechat.size() - 1))
	if phase == "wechat" and wechat.is_empty():
		var old_ids := ["A3-W1","A3-W2","A3-W3","A3-W4","A3-W5"]
		li = _line_index(old_ids[clampi(wi,0,4)])
		phase = "talk"
		wechat_done = true
	if phase == "talk" and li > _line_index("A3-2d"):
		phase = "reply" if li < lines.size() else "hangup"
	holding = false
	t = 0.0
	hint_t = 0.0
	birthday_flash = 0.0
	if phase == "talk": reveal = 0.0
	if phase == "reply": reveal = _line_text().length()
	if birthday_seen or li >= _line_index("A3-2d"): r.pose = "surprised"


func _accept_rect() -> Rect2:
	return Rect2(146, 400, 68, 68)  # 接听键放在头像下面，不压住 Toretto 的脸


func _listen_rect() -> Rect2:
	return r.view_rect


func _speaker_rect() -> Rect2:
	return Rect2(252, 402, 54, 54)


func input(kind: String, pos: Vector2) -> void:
	if phase == "wechat":
		if kind == "down": holding = _listen_rect().has_point(pos)
		elif kind == "up": holding = false
		return
	if phase == "talk":
		if kind == "down":
			holding = _listen_rect().has_point(pos)
		elif kind == "up":
			holding = false
		# A release can also generate a tap. Neither event skips a line.
		return
	if phase == "reply" and kind == "tap" and t >= 0.12:
		if str(lines[li].get("say", "")) == "A3-2g":
			speaker_on = true
			r.play("pop")
		li += 1
		t = 0.0
		if li >= lines.size():
			phase = "hangup"
		else:
			reveal = _line_text().length()
		return
	if phase == "ring" and kind == "tap":
		if _accept_rect().grow(12).has_point(pos):
			phase = "talk"
			t = 0.0
			li = 0
			reveal = 0.0
			r.play("pop")


func _hold_hint(who: String) -> String:
	if who == "ayu": return "按住，听她说"
	if who == "toretto": return r.t_("G-HOLD")
	return "按住，继续听"

func _line_index(id: String) -> int:
	for i in range(lines.size()):
		if str(lines[i].get("say", "")) == id: return i
	return 0

func _line_text() -> String:
	if li >= lines.size():
		return ""
	return r.t_(str(lines[li].get("say", "")))


func draw(ci) -> void:
	if phase == "wechat":
		var back: Texture2D = ci.texture(SPLIT)
		DeskArt.cover(ci, back, ci.view_rect)
		var line: Dictionary = wechat[wi]
		_draw_line(ci, back, str(line.get("who", "narrator")), ci.t_(str(line.say)), int(t * LETTERS_PER_SECOND))
		ci.pill(Rect2(88,572,184,34),ci.t_("G-HOLD"),15,Color(ci.WOOD,0.75),ci.PAPER)
		return
	var who := str(lines[li].get("who", "narrator")) if li < lines.size() else "narrator"
	var bg: Texture2D = ci.texture(SPLIT) if phase != "ring" else null
	DeskArt.cover(ci, bg, ci.view_rect)
	if phase == "ring":
		PhoneShell._round_box(ci,Rect2(55,293,250,177),Color(0.10,0.16,0.22,0.92),18)
		ci.text_at(Vector2(70,330),ci.t_("A3-C1"),20,ci.PAPER,220)
		var face: Texture2D = ci.texture("toretto_avatar.png")
		if face: ci.draw_texture_rect(face,Rect2(156,342,48,48),false)
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		ci.draw_circle(_accept_rect().get_center(),25 + 3 * pulse,Color("#4b995c"))
		ci.draw_arc(_accept_rect().get_center(),31 + 5 * pulse,0,TAU,32,Color(0.6,0.95,0.65,0.6 * (1 - pulse)),2)
		ci.text_at(Vector2(145,443),"接听",16,ci.PAPER,70)
		StoryCaption.draw_caption(ci,aside,"narrator")
	elif phase in ["talk","birthday","reply"] and li < lines.size():
		_draw_line(ci, bg, who, _line_text(), int(reveal))
		ci.pill(Rect2(88,572,184,34),_hold_hint(who) if phase == "talk" else "轻点继续",15,Color(ci.WOOD,0.75),ci.PAPER)
		if holding:
			for i in range(5):
				var h := 3+absf(sin(call_time*8+i))*7
				ci.draw_rect(Rect2(163+i*7,550-h*.5,3,h),ci.GOLD)
	elif phase == "hangup":
		ci.pill(Rect2(90,555,180,36),"通话结束",16,Color(ci.INK,clampf(1-t/0.6,0,1)),ci.PAPER)
	if birthday_flash > 0:ci.draw_rect(ci.view_rect,Color(1,1,1,birthday_flash))

func _draw_line(ci, art: Texture2D, who: String, line: String, shown: int) -> void:
	if not art or not HEADS.has(who):
		StoryCaption.draw_caption(ci, line, who, shown)
		return
	var area: Rect2 = ci.view_rect
	var zoom := maxf(area.size.x / art.get_width(), area.size.y / art.get_height())
	var origin := area.get_center() - art.get_size() * zoom * 0.5
	var head: Vector2 = origin + HEADS[who] * zoom
	var box := _line_box(ci, art, who, line)
	var font_size := 14
	var width := box.size.x
	var tail := PackedVector2Array([Vector2(head.x - 7, box.end.y - 2), Vector2(head.x, head.y - 2), Vector2(head.x + 7, box.end.y - 2)])
	ci.draw_colored_polygon(tail, ci.PAPER)
	PhoneShell._round_box(ci, box, ci.PAPER, 9)
	ci.text_at(box.position + Vector2(12, 21), line.substr(0, shown), font_size, ci.INK, width - 24, HORIZONTAL_ALIGNMENT_LEFT)

func _line_box(ci, art: Texture2D, who: String, line: String) -> Rect2:
	var area: Rect2 = ci.view_rect
	var zoom := maxf(area.size.x / art.get_width(), area.size.y / art.get_height())
	var origin := area.get_center() - art.get_size() * zoom * 0.5
	var head: Vector2 = origin + HEADS[who] * zoom
	var font_size := 14
	var width := clampf(ci.FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 24, 88, 316)
	var wrapped := StoryCaption.wrap_text(line, width - 24, font_size)
	var height := 18.0 + (wrapped.count("\n") + 1) * 17.0
	var min_y := StoryCaption.safe_top + 20.0 if who == "ayu" else origin.y + SPLIT_Y * zoom + 8.0
	return Rect2(clampf(head.x - width * 0.5, 22, 338 - width), maxf(min_y, head.y - height - 14), width, height)

func hud() -> Array:
	# The accept key and listening hint already explain this action. A 1/1
	# objective panel obscured the narration and kept covering the phone call.
	return []
