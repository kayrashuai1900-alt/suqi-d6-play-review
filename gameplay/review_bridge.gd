extends RefCounted
## The local review server supplies this object before Godot starts.

const GAME_NAMES := {
	"desk_intro": "书桌", "drive": "开车与停车", "pandas": "喂熊猫",
	"group_chat": "群聊", "call": "生日来电", "desk_chat": "办公桌消息",
	"care": "消解愁云", "balance": "照顾三件事", "song": "唱歌",
	"moments": "朋友圈", "fishing": "钓鱼", "onsen": "温泉",
	"registration": "领证与快门", "ringtoss": "套圈", "fireworks": "烟花",
	"offer": "录取信", "photo": "合照", "finale": "写信与收请帖",
}
const MATERIALS := {"pen": "钢笔", "ink": "墨水", "paper": "信纸", "stamp": "印章", "wax": "火漆", "envelope": "信封"}
var player_ref: WeakRef
var api: Variant
var callback: Variant
var froze_tree := false
var jumping := false

func attach(player: Control) -> void:
	if not OS.has_feature("web") or OS.has_feature("hongyuan_wechat"):
		return
	api = JavaScriptBridge.get_interface("suqiReview")
	if api == null:
		return
	player_ref = weakref(player)
	callback = JavaScriptBridge.create_callback(_command)
	var scenes: Array[Dictionary] = []
	for step: Dictionary in player.playlist:
		if step.type == "terminal":
			continue
		var entries: Array[Dictionary] = [{"beat": 0, "label": "场景开头"}]
		var beats: Array = step.get("scene", {}).get("beats", [])
		for i in range(beats.size()):
			var beat: Dictionary = beats[i]
			var label := ""
			if beat.has("game"):
				label = str(GAME_NAMES.get(beat.game, beat.game))
			elif beat.has("goal"):
				label = "任务卡 · " + str(beat.goal.get("目标", ""))
			elif beat.has("material"):
				label = "奖励 · " + str(MATERIALS.get(beat.material, beat.material))
			elif beat.has("narrate") or beat.has("say"):
				label = player._text(str(beat.get("narrate", beat.get("say", "")))).split("\n")[0].strip_edges()
			elif beat.has("button"):
				label = player._text(str(beat.button))
			elif beat.has("go"):
				label = "走向 · " + str(beat.go)
			elif beat.has("caption"):
				label = player._text(str(beat.caption))
			if not label.is_empty():
				entries.append({"beat": i, "label": label.left(46)})
		var first_line: String = player._text(str(step.get("copyId", ""))).strip_edges().split("\n")[0]
		var label: String = str(entries[1].label) if entries.size() > 1 else first_line
		scenes.append({"id": step.fullId, "chapter": player._text(str(step.titleId)), "label": label.left(34), "entries": entries})
	api.attachPlayer(callback, JSON.stringify(scenes))

func detach() -> void:
	if api == null:
		return
	var player: Control = player_ref.get_ref()
	if player and froze_tree:
		player.get_tree().paused = false
	api.detachPlayer(callback)
	api = null
	callback = null

func _command(args: Array) -> void:
	var player: Control = player_ref.get_ref()
	if player == null or args.is_empty():
		return
	var request: Variant = JSON.parse_string(str(args[0]))
	if not request is Dictionary:
		return
	match str(request.get("action", "")):
		"freeze":
			var runner: Control = player.runner
			if not player.get_tree().paused:
				froze_tree = true
				player.get_tree().paused = true
			var details := {"step": player.shot.get("fullId", ""), "chapter": player._text(str(player.shot.get("titleId", ""))), "beat": -1, "mode": "", "phase": ""}
			if is_instance_valid(runner):
				details.beat = runner.bi
				details.mode = runner.mode
				if runner.game and "phase" in runner.game:
					details.phase = str(runner.game.phase)
			api.receiveContext(JSON.stringify(details))
		"play":
			if froze_tree:
				froze_tree = false
				player.get_tree().paused = false
		"next":
			_skip_current(player)
		"jump":
			if jumping or player.loading_content or player.fading or player.get_tree().paused:
				api.jumpDone(false, "此时正在转场，请等画面稳定后再跳转。")
				return
			var key := str(request.get("step", ""))
			if not player.step_indices.has(key):
				api.jumpDone(false, "找不到这个场景。")
				return
			var index: int = player.step_indices[key]
			var target: Dictionary = player.playlist[index]
			var beats: Array = target.get("scene", {}).get("beats", [])
			var beat := clampi(int(request.get("beat", 0)), 0, maxi(0, beats.size() - 1))
			jumping = true
			# Rebuild only the review save. This origin is separate from the public trial.
			var collected := {}
			for i in range(index):
				for prior: Dictionary in player.playlist[i].get("scene", {}).get("beats", []):
					if prior.has("material"):
						collected[prior.material] = true
			player.state = {"version": 1, "revision": player.state.get("revision", 0),
				"runId": player.state.get("runId", ""), "stepId": key,
				"materials": {}, "sceneMaterials": collected, "sceneBeat": beat,
				"sceneSig": str(JSON.stringify(beats).hash())}
			player.interludes_shown.clear()
			await player._enter_step(index, true)
			jumping = false
			if api != null:
				api.jumpDone(player.pending_index < 0 or not player.loading_content, "")


func _skip_current(player: Control) -> void:
	if player.coda_active:
		player.coda_continue = true
		return
	if jumping or player.loading_content or player.fading:
		api.nextNotice("正在换场，等新画面出现。")
		return
	var runner: Control = player.runner
	if not is_instance_valid(runner):
		player._advance()
		return
	if runner.mode in ["transition", "finished"]:
		api.nextNotice("正在换场，等新画面出现。")
		return
	if runner.mode == "choice" or (runner.mode == "game" and runner.beats[runner.bi].get("game") == "finale"):
		api.nextNotice("这一环节会决定赴约去向，请在画面里继续。")
		return
	if runner.mode == "go" and runner.hotspots.has(runner.go_id):
		runner._trigger(runner.go_id)
		return
	if runner.mode == "material" and not runner.materials.get(runner.material_id, false):
		runner.materials[runner.material_id] = true
		runner.material_applied.emit(runner.material_id)
	runner._next()
