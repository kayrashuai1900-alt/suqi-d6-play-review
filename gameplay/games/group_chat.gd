extends "res://hongyuan/games/desk_chat.gd"
## 群聊和窗前微信共用底部气泡；背景由这一幕的场景指定。
var title_key := "A1-G0"
var title_suffix := " · 23"

func start(runner, beat: Dictionary) -> void:
	super.start(runner, beat)
	own_who = "ayu"
	li = clampi(int(beat.get("startLine", 0)), 0, maxi(0, lines.size() - 1))
	title_key = str(beat.get("title", title_key))
	title_suffix = str(beat.get("titleSuffix", title_suffix))
	r.hint = ""

func _title(ci) -> String:
	return ci.t_(title_key) + title_suffix
