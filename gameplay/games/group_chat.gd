extends "res://hongyuan/games/desk_chat.gd"
## 群聊和窗前微信共用底部气泡；背景由这一幕的场景指定。
var title_key := "A1-G0"
var title_suffix := " · 23"
var phone_alert := ""
const CHECK_PHONE := Rect2(78, 551, 204, 46)

func start(runner, beat: Dictionary) -> void:
	super.start(runner, beat)
	own_who = "ayu"
	li = clampi(int(beat.get("startLine", 0)), 0, maxi(0, lines.size() - 1))
	title_key = str(beat.get("title", title_key))
	title_suffix = str(beat.get("titleSuffix", title_suffix))
	phone_alert = str(beat.get("phoneAlert", ""))
	if not phone_alert.is_empty():
		phase = "alert"
	r.hint = ""

func _title(ci) -> String:
	return ci.t_(title_key) + title_suffix

func input(kind: String, pos: Vector2) -> void:
	if phase == "alert":
		if kind == "tap" and t >= 0.45 and CHECK_PHONE.has_point(pos):
			phase = "chat"
			t = 0.0
			r.play("blip")
		return
	super.input(kind, pos)

func draw(ci) -> void:
	if phase != "alert":
		super.draw(ci)
		return
	ci.StoryCaption.draw_caption(ci, ci.t_(phone_alert), "narrator")
	if t >= 0.45:
		ci.pill(CHECK_PHONE, "查看手机", 17, ci.RED, ci.PAPER)
