extends Control
## 一段可操控的场景：背景、人物、摇杆/点地走路、靠近出互动按钮、对白、小游戏。
## 内容全部来自章节 JSON 里 type="scene" 那一步的 "scene" 字段，代码不写剧情。
## 图按文件名找：先找 assets/w2/<名字>，再找 assets/<名字>；找不到就画占位，不报错。

signal finished
signal beat_reached(index: int)
signal material_applied(id: String)
signal scene_requested(path: String)
signal invitation_accepted
signal music_requested(cue: String)

const CANVAS := Vector2(360, 640)
const S := 2.0 / 3.0
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
const WorldScale := preload("res://hongyuan/world_scale.gd")
const CoastShow := preload("res://hongyuan/coast_show.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")
const ROOT := "res://hongyuan/assets/"
## 走路：速度和步幅都跟着人在画面里的高度走（128 高≈1.65 米）。
## 105 像素/秒 ≈ 1.3 米/秒的正常步行；4 帧行走图是一个完整步态（两步），一帧走 0.2 个身高，
## 这样脚步和地面移动对得上，不会原地小碎步或滑行。
const SPEED := 105.0
const STRIDE_K := 0.2
const NEAR := 40.0
const GOAL_DELAY := 1.2
const INK := Color("#281a1a")
const SceneWipe := preload("res://hongyuan/ui/scene_wipe.gd")
const WIPE_OUT := 0.28
const WOOD := Color("#50332a")
const RED := Color("#5e2929")
const GOLD := Color("#d6a456")
const PAPER := Color("#fff1d5")
const WHEAT := Color("#f4d495")
const GRASS := Color("#59764e")
const NAMES := {"ayu": "阿鱼", "toretto": "Toretto", "axiao": "阿晓"}
const AVATARS := {"ayu": "ayu_avatar.png", "toretto": "toretto_avatar.png", "axiao": "axiao_avatar.png"}
const CARD := Vector2(56, 120)
const SLOTS := {"pen": Vector2(75, 305), "ink": Vector2(180, 305), "paper": Vector2(285, 305), "stamp": Vector2(77, 390), "wax": Vector2(180, 390), "envelope": Vector2(284, 393)}
const GAMES := {
	"registration": preload("res://hongyuan/games/registration.gd"),
	"group_chat": preload("res://hongyuan/games/group_chat.gd"),
	"care": preload("res://hongyuan/games/care.gd"),
	"balance": preload("res://hongyuan/games/balance.gd"),
	"desk_intro": preload("res://hongyuan/games/desk_intro.gd"),
	"desk_chat": preload("res://hongyuan/games/desk_chat.gd"),
	"pandas": preload("res://hongyuan/games/pandas.gd"),
	"fishing": preload("res://hongyuan/games/fishing.gd"),
	"ringtoss": preload("res://hongyuan/games/ringtoss.gd"),
	"fireworks": preload("res://hongyuan/games/fireworks.gd"),
	"call": preload("res://hongyuan/games/call.gd"),
	"mail": preload("res://hongyuan/games/mail.gd"),
	"finale": preload("res://hongyuan/games/finale.gd"),
	"drive": preload("res://hongyuan/games/drive.gd"),
	"seat": preload("res://hongyuan/games/seat.gd"),
	"onsen": preload("res://hongyuan/games/onsen.gd"),
	"photo": preload("res://hongyuan/games/photo.gd"),
	"offer": preload("res://hongyuan/games/offer.gd"),
	"invite_mail": preload("res://hongyuan/games/invite_mail.gd"),
	"song": preload("res://hongyuan/games/song.gd"),
	"moments": preload("res://hongyuan/games/moments.gd"),
}

var copy: Dictionary
var spec: Dictionary
var beats: Array = []
var materials: Dictionary = {}
var bi := -1
var mode := ""
var t := 0.0
var time := 0.0

# 世界
var view_rect := Rect2(0, 0, 360, 640)
var camera_y := 0.0
var camera_moved := false
var camera_drag := false
var camera_start := 0.0
var pending_setup: Dictionary = {}
var transition_applied := false
var bg := ""
var bg_fit := false
var player_role := "ayu"
var scale_profile := ""
var atmosphere := ""
var atmosphere_elapsed := 0.0
var world_elapsed := 0.0
var cast_shadows := true
var location_sign := ""
const G42Art := preload("res://hongyuan/ui/g42_art.gd")
var bg_fill := Color("#2a1c18")
var night := 0.0
var sky := Color.TRANSPARENT
var ground := Color.TRANSPARENT
var horizon := 360.0
var decor: Array = []
var walk_area := PackedVector2Array()
var hotspots: Dictionary = {}
var actors: Dictionary = {}
var feet := Vector2(180, 520)
var facing := 1.0
var pose := ""
var player_visible := true
var walk_dist := 0.0
var moving := false
var move_dir := Vector2.ZERO
var target := Vector2.ZERO
var target_hot := ""
var follower := ""
var companion := ""        # 同行的人（和玩家并排走）：目前只有 "toretto"
var comp_pos := Vector2.ZERO
var comp_walk := 0.0
var comp_moving := false
var walkers: Array = []
static var _scene_crowds: Dictionary = {}
var npc_reply := -1
var npc_reply_t := 0.0
var crowd := preload("res://hongyuan/crowd_motion.gd").new()
static var _ambient_dialogue: Dictionary = {}
var sheet_cache: Dictionary = {}
var sheet_rects: Dictionary = {}
var trail: Array[Vector2] = []
var badge := ""

# 输入
var pointer_input := preload("res://hongyuan/pointer_input.gd").new()
var down := false
var down_pos := Vector2.ZERO
var down_ms := 0
var dragged := false
var stick := Vector2.ZERO
var stick_pointer := false

# 文字
var goal_data: Dictionary = {}
var hint := ""
var say_who := ""
var say_text := ""
var reveal := 0.0
var go_id := ""
var button_text := ""
var button_coda := ""
var button_rect := Rect2()
var choice_texts: Array = []
var choice_to: Array = []
var choice_note := ""
var choice_note_t := 0.0
var choice_fallback := false
var material_id := ""
# Keep the memory's last rendered frame while it fades to a token close-up.
var transition_frame: Texture2D
var material_leaving := false
var material_exit_t := 0.0
const MATERIAL_FADE := 0.4
const DeskArt := preload("res://hongyuan/ui/desk_art.gd")
const MATERIAL_READ_TIME := 2.8
# Detail plates on the original painted writing desk, in its 841 × 1870 artwork.
const MATERIAL_DETAILS := {
	"pen": Rect2(437,695,186,150), "ink": Rect2(478,450,172,139),
	"paper": Rect2(327,567,376,303), "stamp": Rect2(669,520,153,123),
	"wax": Rect2(657,609,151,122), "envelope": Rect2(554,484,237,191),
}
const MATERIAL_LINES := {
	"pen":"钢笔，写邀请函用", "ink":"墨水，让邀请函上的字显现",
	"paper":"信纸，让彼此的心意留下来", "stamp":"印章，盖在邀请函上",
	"wax":"火漆，留到最后封上邀请函", "envelope":"信封，让这份邀请能够寄出",
}
const MATERIAL_NAMES := {"pen": "钢笔", "ink": "墨水", "paper": "信纸", "stamp": "印章", "wax": "火漆", "envelope": "信封"}
var game: RefCounted
var result: Dictionary = {}
var tex_cache: Dictionary = {}
var used_rects: Dictionary = {}
var person_height := 128.0
var sfx := AudioStreamPlayer.new()
var blip: AudioStreamWAV
var pop: AudioStreamWAV


func setup(scene: Dictionary, copy_table: Dictionary, applied: Dictionary) -> void:
	spec = scene
	copy = copy_table
	materials = applied.duplicate()
	beats = spec.get("beats", [])


func _ready() -> void:
	size = CANVAS
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	blip = _tone(520.0, 660.0, 0.07)
	pop = _tone(330.0, 880.0, 0.16)
	sfx.volume_db = -14.0
	add_child(sfx)


## 从第 start 拍开始。前面的布景拍（换背景、摆人、提示）瞬间执行，保证续档时画面对。
func begin(start := 0) -> void:
	_apply_world(spec)
	for i in range(mini(start, beats.size())):
		var beat: Dictionary = beats[i]
		if _is_setup(beat):
			_run_setup(beat)
		elif beat.has("material"):
			materials[beat.material] = true
		elif beat.has("go"):
			_arrive_at(str(beat.go), true)
	bi = start - 1
	_next()


func _apply_world(d: Dictionary) -> void:
	if d.has("player"):
		player_role = str(d.player)
	if d.has("personHeight"):
		person_height = float(d.personHeight)
	if d.has("bg"):
		bg = str(d.bg)
		cast_shadows = bool(d.get("castShadows", true))
		location_sign = str(d.get("locationSign", ""))
		world_elapsed = 0.0
		bg_fit = bool(d.get("bgFit", false))
		scale_profile = WorldScale.profile("", bg)
		atmosphere = ""
		atmosphere_elapsed = 0.0
	if d.has("scaleProfile"):
		scale_profile = str(d.scaleProfile)
	if d.has("atmosphere"):
		atmosphere = str(d.atmosphere)
		atmosphere_elapsed = 0.0
	if d.has("fill"):
		bg_fill = Color(str(d.fill))
	if d.has("sky"):
		sky = Color(str(d.sky))
		ground = Color(str(d.get("ground", d.sky)))
		horizon = float(d.get("horizon", 360))
	if d.has("decor"):
		decor = d.decor
	if d.has("night"):
		night = float(d.night)
	if d.has("badge"):
		badge = _text(str(d.badge))
	if d.has("walkArea"):
		walk_area = PackedVector2Array()
		for p: Array in d.walkArea:
			walk_area.append(Vector2(float(p[0]), float(p[1])))
	if d.has("start"):
		feet = _v(d.start)
		trail.clear()
	if d.has("hotspots"):
		hotspots.clear()
		for h: Dictionary in d.hotspots:
			hotspots[str(h.id)] = h
	if d.has("actors"):
		actors.clear()
		for a: Dictionary in d.actors:
			actors[str(a.id)] = a.duplicate()
	if d.has("pose"):
		pose = str(d.pose)
	if d.has("hideAyu"):
		player_visible = not bool(d.hideAyu)
	if d.has("bg") or d.has("walkers"):
		var authored: Array = d.get("walkers", [])
		_place_walkers(authored, d.has("bg") or not authored.is_empty())
	if d.has("companion"):
		companion = str(d.companion)
		if companion != "":
			comp_pos = feet + Vector2(36 * facing, -10)
		comp_walk = 0.0


func _place_walkers(authored: Array, include_layout: bool) -> void:
	if _scene_crowds.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://hongyuan/scene_crowds.json"))
		if data is Dictionary:
			_scene_crowds = data
	var layout: Dictionary = _scene_crowds.get(bg, {}) if include_layout else {}
	var replies: Dictionary = layout.get("talk", {})
	walkers = authored.duplicate(true)
	for person: Dictionary in layout.get("standing", []):
		var walker := person.duplicate()
		walker.merge({"a": person.at, "b": person.at, "speed": 0})
		walkers.append(walker)
	for route: Dictionary in layout.get("walkers", []):
		walkers.append(route.duplicate(true))
	for walker: Dictionary in walkers:
		var npc_id := str(walker.get("npc", ""))
		if replies.has(npc_id):
			walker["reply"] = replies[npc_id]
		if layout.get("singlePass", false) and float(walker.get("speed", 0)) > 0.0:
			walker["once"] = true
			walker.erase("phase")
		if walker.has("chatBank"):
			var turns := _ambient_lines(str(walker.chatBank), int(walker.get("chatSide", 0)))
			if not turns.is_empty():
				walker["chat"] = turns
		if not walker.has("reply") and not walker.get("chat", []).is_empty():
			walker["reply"] = [_text(str(walker.chat[0]))]
			walker["nextChat"] = 0
	crowd.setup(walkers)


static func _ambient_lines(bank: String, side: int) -> Array:
	if _ambient_dialogue.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://hongyuan/npc_dialogue.json"))
		if data is Dictionary:
			_ambient_dialogue = data
		else:
			return []
	var turns: Array = _ambient_dialogue.get(bank, [])
	var lines: Array = []
	for turn: Array in turns:
		if side >= 0 and side < turn.size():
			lines.append(str(turn[side]))
	return lines


func _is_setup(beat: Dictionary) -> bool:
	for key in ["say", "card", "go", "game", "wait", "material", "button", "choice", "narrate", "goal"]:
		if beat.has(key):
			return false
	return true


func _run_setup(beat: Dictionary) -> void:
	_apply_world(beat)
	if beat.has("hint"):
		hint = _text(str(beat.hint)) if str(beat.hint) != "" else ""
	if beat.has("actor"):
		var a: Dictionary = beat.actor
		actors[str(a.id)] = actors.get(str(a.id), {}).merged(a, true)
	if beat.has("remove"):
		actors.erase(str(beat.remove))
	if beat.has("follow"):
		follower = str(beat.follow)
		trail.clear()
	if beat.has("place"):
		feet = _v(beat.place)
		trail.clear()
		if companion != "":
			comp_pos = feet + Vector2(36 * facing, -10)


func _next() -> void:
	if mode == "finished":
		return
	if bi + 1 >= beats.size():
		mode = "finished"
		set_process(false)
		suspend_input()
		finished.emit()
		return
	bi += 1
	t = 0.0
	mode = ""
	camera_y = 0.0
	npc_reply = -1
	npc_reply_t = 0.0
	game = null
	_reset_input()
	if bi >= beats.size():
		finished.emit()
		return
	var beat: Dictionary = beats[bi]
	if not beat.has("material"):
		material_id = ""
	if _is_setup(beat):
		if beat.has("bg") and str(beat.bg) != bg:
			pending_setup = beat
			transition_applied = false
			mode = "transition"
			transition_frame = SceneWipe.capture(self)
			beat_reached.emit(bi)
			return
		_run_setup(beat)
		_next()
		return
	beat_reached.emit(bi)
	if beat.has("goal"):
		mode = "goal"
		goal_data = beat.goal
	elif beat.has("say") or beat.has("narrate"):
		mode = "say"
		say_who = str(beat.get("who", "narrator"))
		if beat.has("chapterCaption"):
			say_text = "\n".join(StoryCaption.chapter_coda(str(beat.chapterCaption)).get("pages", []))
		else:
			say_text = _text(str(beat.get("say", beat.get("narrate", ""))))
		if say_text.strip_edges() == "" and not beat.has("say"):
			# 定稿里标明「不显示」的旁白：留着这一拍的位置（存档不会错位），但直接略过。
			_next()
			return
		reveal = 0.0
		if beat.has("auto"):
			mode = "auto"
	elif beat.has("card"):
		mode = "card"
		say_text = _text(str(beat.card))
	elif beat.has("go"):
		mode = "go"
		go_id = str(beat.go)
		if beat.has("hint"):
			hint = _text(str(beat.hint))
	elif beat.has("game"):
		mode = "game"
		game = GAMES[str(beat.game)].new()
		game.start(self, beat)
	elif beat.has("wait"):
		mode = "wait"
	elif beat.has("material"):
		mode = "material"
		material_id = str(beat.material)
		material_leaving = false
		material_exit_t = 0.0
		sfx.stream = pop
		sfx.play()
	elif beat.has("button"):
		mode = "button"
		button_text = _text(str(beat.button))
		button_coda = ""
		if bi == beats.size() - 1 and spec.has("codaAtLastButton"):
			var lines: Array = StoryCaption.chapter_coda(spec.codaAtLastButton).get("pages", [])
			button_coda = StoryCaption.wrap_text("\n".join(lines), 292, 19)
		button_rect = Rect2(100, 470, 160, 46)
	elif beat.has("choice"):
		# 终章二选一：第一项接着往下走；其余项切到 beat.to 里对应的场景（如村子）
		mode = "choice"
		choice_texts = []
		for id in beat.choice:
			choice_texts.append(_text(str(id)))
		choice_to = beat.get("to", [])
	queue_redraw()


func _process(dt: float) -> void:
	dt = minf(dt, 0.08)
	t += dt
	if choice_note_t > 0.0:
		choice_note_t = maxf(0.0, choice_note_t - dt)
		if choice_note_t == 0.0 and choice_fallback and mode == "choice":
			choice_fallback = false
			_next()
	time += dt
	npc_reply_t = maxf(0.0, npc_reply_t - dt)
	world_elapsed += dt
	crowd.advance(dt, feet, player_visible)
	if atmosphere != "": atmosphere_elapsed += dt
	var beat: Dictionary = beats[bi] if bi >= 0 and bi < beats.size() else {}
	match mode:
		"transition":
			if not transition_applied:
				_run_setup(pending_setup)
				transition_applied = true
			if t >= WIPE_OUT:
				transition_frame = null
				_next()
		"say", "auto":
			if t >= float(beat.get("captionDelay", 0.0)):
				reveal += dt * 26.0
			if mode == "auto" and t >= float(beat.get("auto", 2.4)):
				_next()
		"card":
			if t >= float(beat.get("duration", 1.8)):
				_next()
		"wait":
			if t >= float(beat.wait):
				_next()
		"material":
			if material_leaving:
				material_exit_t += dt
				if material_exit_t >= MATERIAL_FADE:
					_next()
			if t >= 2.0 and not materials.get(material_id, false):
				materials[material_id] = true
				material_applied.emit(material_id)
		"go":
			_walk(dt)
		"game":
			if game and game.process(dt):
				_next()
	queue_redraw()


# ---------- 走路 ----------

func _stride(y := NAN) -> float:
	return maxf(6.0, person_height_at(feet.y if is_nan(y) else y) * STRIDE_K)


func _walk(dt: float) -> void:
	var before := feet
	var speed := SPEED * clampf(person_height_at(feet.y) / 128.0, 0.3, 1.15)
	if stick.length() > 0.08:
		target_hot = ""
		moving = false
		feet = _clamp(feet + stick * speed * dt)
	elif moving:
		feet = feet.move_toward(target, speed * dt)
		feet = _clamp(feet)
		if feet.distance_to(target) < 0.5 or (target_hot != "" and _near_hotspot() == target_hot and feet.distance_to(target) < 2.0):
			moving = false
			var arrived := target_hot
			target_hot = ""
			if arrived != "" and _near_hotspot() == arrived:
				_trigger(arrived)
				return
	var step := feet - before
	move_dir = step
	_update_companion(dt)
	if absf(step.x) > 0.05:
		facing = signf(step.x)
	walk_dist += step.length()
	if step.length() > 0.01 and follower != "":
		trail.push_front(feet)
		if trail.size() > 40:
			trail.resize(40)


func _update_companion(dt: float) -> void:
	if companion == "":
		return
	var want := _clamp(feet + Vector2(36 * facing, -10))  # 同伴也不能走出可走区域（比如走到水面上）
	var before := comp_pos
	comp_pos = comp_pos.lerp(want, 1.0 - exp(-6.0 * dt))
	var moved := comp_pos.distance_to(before)
	comp_moving = moved > 0.12
	comp_walk += moved


func _clamp(p: Vector2) -> Vector2:
	if walk_area.size() < 3 or Geometry2D.is_point_in_polygon(p, walk_area):
		return p
	var best := walk_area[0]
	for i in range(walk_area.size()):
		var c := Geometry2D.get_closest_point_to_segment(p, walk_area[i], walk_area[(i + 1) % walk_area.size()])
		if c.distance_squared_to(p) < best.distance_squared_to(p):
			best = c
	return best


func _near_hotspot() -> String:
	if mode != "go" or not hotspots.has(go_id):
		return ""
	return go_id if feet.distance_to(_v(hotspots[go_id].at)) <= NEAR else ""


func _trigger(id: String) -> void:
	if mode != "go" or id != go_id:
		return
	sfx.stream = blip
	sfx.play()
	_arrive_at(id, false)
	hint = ""
	_next()


func _arrive_at(id: String, _instant: bool) -> void:
	var h: Dictionary = hotspots.get(id, {})
	if h.has("snap"):
		feet = _v(h.snap)
	if h.has("pose"):
		pose = str(h.pose)
	if h.has("face"):
		facing = float(h.face)
	if h.has("companionSnap") and companion != "":
		comp_pos = _clamp(_v(h.companionSnap))


func _icon_rect(id: String) -> Rect2:
	var h: Dictionary = hotspots[id]
	var at := _v(h.at)
	if h.has("iconAt"):
		return Rect2(_v(h.iconAt) - Vector2(22, 22), Vector2(44, 44))
	# 图标放在站到该点的人物头顶上方，不压在身上
	var snap := _v(h.get("snap", h.at))
	var top := snap.y - person_height_at(snap.y) - 30.0
	return Rect2(at.x - 22, maxf(60.0, top - 22.0), 44, 44)


# ---------- 输入 ----------

func _has_point(point: Vector2) -> bool:
	return view_rect.has_point(point)


func _gui_input(event: InputEvent) -> void:
	event = pointer_input.normalize(event)
	if event == null:
		return
	if event.get_meta("pointer_cancelled", false):
		suspend_input()
		return
	var pos := Vector2.ZERO
	var kind := ""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		kind = "down" if event.pressed else "up"
	elif event is InputEventMouseMotion and down:
		pos = event.position
		kind = "move"
	else:
		return
	accept_event()
	if mode == "go":
		if kind == "down":
			# 只有背景比屏幕高、按在上半屏、又不是按在目标上时，才可能是拖镜头；
			# 真正拖动超过 12px 才算拖镜头，否则松手时照常当点击处理
			var world_pos := pos - Vector2(0, camera_y)
			camera_drag = pos.y < 320 and _camera_extent() > 0.0 and not _on_target(world_pos)
			camera_moved = false
			camera_start = camera_y
		elif camera_drag and kind == "move":
			if pos.distance_to(down_pos) > 12 or camera_moved:
				camera_moved = true
				camera_y = clampf(camera_start + pos.y - down_pos.y, -_camera_extent(), _camera_extent())
				queue_redraw()
				return
		elif camera_drag and kind == "up":
			camera_drag = false
			if camera_moved:
				camera_moved = false
				_reset_input()
				return
	if kind == "down":
		down = true
		down_pos = pos
		down_ms = Time.get_ticks_msec()
		dragged = false
		stick_pointer = mode == "go" and pos.y > 320 and not _on_target(pos - Vector2(0, camera_y))
	elif kind == "move":
		if pos.distance_to(down_pos) > 12:
			dragged = true
	var tap := kind == "up" and down and not dragged and Time.get_ticks_msec() - down_ms < 350
	if kind == "up":
		down = false
	if tap and _skip_visible() and SKIP_RECT.grow(6).has_point(down_pos) and SKIP_RECT.grow(6).has_point(pos):
		_skip()
		return
	match mode:
		"goal":
			var button: Rect2 = _goal_layout().button
			if tap and t >= GOAL_DELAY + 0.3 and button.has_point(down_pos) and button.has_point(pos):
				_next()
		"material":
			if tap and t >= MATERIAL_READ_TIME and not material_leaving:
				material_leaving = true
				material_exit_t = 0.0
		"game":
			if game:
				game.input(kind, pos)
				if tap:
					game.input("tap", pos)
		"say":
			if t < float(beats[bi].get("captionDelay", 0.0)): return
			if _night_bridge() and not (tap and t >= 0.45 and LISTEN_RECT.has_point(down_pos) and LISTEN_RECT.has_point(pos)):
				return
			if tap or (kind == "up" and down_pos.distance_to(pos) < 30):
				if reveal < say_text.length():
					reveal = say_text.length()
				elif t > 0.25:
					_next()
		"card":
			if tap and t > 0.6:
				_next()
		"choice":
			# 已经在出发（提示 30 秒）时不再接受第二次点击，免得连点切两次场景
			if tap and t > 0.4 and choice_note_t <= 3.0:
				for i in range(choice_texts.size()):
					if _choice_rect(i).grow(6).has_point(pos):
						sfx.stream = blip
						sfx.play()
						var to := str(choice_to[i]) if i < choice_to.size() and choice_to[i] != null else ""
						if to == "":
							_next()
						elif not ResourceLoader.exists(to):
							# 缺失资源时留在选择页，允许玩家重试或选另一条路线
							choice_note = _text("G-VILLAGE-LATER")
							choice_note_t = 3.0
							choice_fallback = false
							push_error("Choice destination is missing: " + to)
						else:
							choice_note = "正在出发…"
							choice_note_t = 30.0
							scene_requested.emit(to)
						return
		"button":
			if tap and button_rect.grow(8).has_point(pos):
				sfx.stream = blip
				sfx.play()
				_next()
		"go":
			_go_input(kind, pos, tap)


func _go_input(kind: String, pos: Vector2, tap: bool) -> void:
	var screen_pos := pos
	pos.y -= camera_y
	if kind == "move" and dragged and stick_pointer:
		npc_reply_t = 0.0
		stick = ((screen_pos - down_pos) / 36.0).limit_length()
	elif kind == "up":
		stick = Vector2.ZERO
	if not tap:
		return
	var near := _near_hotspot()
	if near != "" and _icon_rect(near).grow(10).has_point(pos):
		_trigger(near)
		return
	# 点目标本身（图标、光圈或它周围）：走过去，到了自动触发，不用再点第二次
	if hotspots.has(go_id):
		var h: Dictionary = hotspots[go_id]
		if _on_target(pos):
			npc_reply_t = 0.0
			target = _clamp(_v(h.get("snap", h.at)))
			target_hot = go_id
			moving = true
			return
	if _talk_to_npc(pos):
		return
	npc_reply_t = 0.0
	# 其他地面点击只走路
	if Geometry2D.is_point_in_polygon(pos, walk_area):
		target = _clamp(pos)
		target_hot = ""
		moving = true


func _camera_extent() -> float:
	var image := texture(bg)
	return maxf(0, image.get_height() * 360.0 / image.get_width() - view_rect.size.y) * 0.5 if image else 0.0


## 玩家点在目标附近就算点到：光圈 56px 以内、图标、或者站到目标上的那个人身上
func _on_target(pos: Vector2) -> bool:
	if not hotspots.has(go_id):
		return false
	var h: Dictionary = hotspots[go_id]
	var at := _v(h.at)
	if pos.distance_to(at) <= 40.0 or _icon_rect(go_id).grow(14).has_point(pos):
		return true
	# 目标是一个人或一件东西（热点上站着角色或摆着道具）时，点到它的身体也算点中
	for id: String in actors:
		var a: Dictionary = actors[id]
		if a.get("hidden", false) or not a.has("at"): continue
		var foot := _v(a.at)
		if foot.distance_to(at) > 110.0: continue
		var height := person_height_at(foot.y)
		if Rect2(foot.x - height * 0.35, foot.y - height, height * 0.7, height).has_point(pos):
			return true
	return false


func _reset_input() -> void:
	camera_moved = false
	down = false
	dragged = false
	stick_pointer = false
	stick = Vector2.ZERO
	moving = false
	target_hot = ""


# ---------- 画 ----------

func _draw() -> void:
	# A material is a self-contained memory insert, including its final frame.
	# Player advances deferred, so revealing the world at finished leaks one frame.
	if mode == "material" or (mode == "finished" and not material_id.is_empty()):
		_draw_material()
		return
	draw_rect(view_rect, bg_fill)
	_draw_bg()
	if atmosphere == "coast": CoastShow.draw(self, atmosphere_elapsed)
	elif atmosphere != "": preload("res://hongyuan/ui/ambient_scene.gd").draw(self, atmosphere, atmosphere_elapsed)
	draw_set_transform(Vector2(0, camera_y))
	_draw_world()
	if bool(spec.get("pandaPreview", false)) and mode != "game":
		preload("res://hongyuan/games/pandas.gd").draw_preview(self)
	draw_set_transform(Vector2.ZERO)
	if night > 0.0:
		draw_rect(Rect2(Vector2.ZERO, CANVAS), Color(0.05, 0.04, 0.12, night))
	if mode == "game" and game:
		game.draw(self)
		_draw_hud()
	if mode == "go":
		draw_set_transform(Vector2(0, camera_y))
		_draw_go_ui()
		draw_set_transform(Vector2.ZERO)
		_draw_walk_stick()
	if badge != "":
		var badge_top := maxf(StoryCaption.safe_top + 8.0, minf(12.0, StoryCaption.narration_top - 30.0))
		_pill(Rect2(250, badge_top, 100, 22), badge, 12, Color(RED, 0.85), PAPER)
	if hint != "" and mode in ["go", "game"]:
		_hint(hint)
	if _skip_visible():
		_pill(SKIP_RECT, _skip_label(), 13, Color(INK, 0.7), WHEAT)
	match mode:
		"goal":
			if t >= GOAL_DELAY:
				var alpha := clampf((t - GOAL_DELAY) / 0.3, 0, 1)
				draw_rect(view_rect, Color(INK, 0.18 * alpha))
				var layout := _goal_layout()
				var box: Rect2 = layout.box
				_panel(box, Color(PAPER, alpha), Color(GOLD, alpha))
				var label_color := Color(RED, alpha)
				var text_color := Color(INK, alpha)
				draw_string(FONT, Vector2(42, 110), "目标", HORIZONTAL_ALIGNMENT_LEFT, 52, 15, label_color)
				draw_string(FONT, Vector2(98, 110), str(goal_data.get("目标", "")), HORIZONTAL_ALIGNMENT_LEFT, 164, 19, text_color)
				draw_line(Vector2(42, 131), Vector2(318, 131), Color(GOLD, alpha), 1)
				draw_string(FONT, Vector2(42, 155), "任务", HORIZONTAL_ALIGNMENT_LEFT, 52, 15, label_color)
				draw_multiline_string(FONT, Vector2(98, 155), layout.task, HORIZONTAL_ALIGNMENT_LEFT, 216, 16, -1, text_color)
				_draw_goal_reward(layout.reward, alpha)
				var button: Rect2 = layout.button
				_pill(button, "开始任务", 16, Color(RED, alpha), Color(PAPER, alpha), true)
				draw_rect(button.grow(-3), Color(GOLD, alpha), false, 1.0)
		"wait":
			if beats[bi].has("caption"):
				var caption := _text(str(beats[bi].caption))
				StoryCaption.draw_low_narration(self, caption, caption.length())
		"say", "auto":
			_draw_say()
		"card":
			_draw_card()
		"choice":
			if "res://hongyuan/world_entry.tscn" in choice_to and "res://hongyuan/village_entry.tscn" in choice_to:
				DeskArt.cover(self, texture("round1/common/welcome_bg.png"), view_rect)
				var welcome := texture("round1/common/welcome.png")
				if welcome: draw_texture_rect(welcome, Rect2(42, 166, 276, 386.4), false)
			draw_rect(view_rect, Color(0, 0, 0, 0.35))
			for i in range(choice_texts.size()):
				_pill(_choice_rect(i), choice_texts[i], 19, RED if i == 0 else Color(INK, 0.85), PAPER)
			if choice_note_t > 0.0:
				_pill(Rect2(16, 392, 328, 56), choice_note, 16, Color(INK, 0.94), WHEAT)
		"button":
			draw_rect(view_rect, Color(INK, 0.35))
			if not button_coda.is_empty():
				draw_multiline_string(FONT, Vector2(34, 308), button_coda, HORIZONTAL_ALIGNMENT_CENTER, 292, 19, -1, Color(PAPER, smoothstep(0.0, 0.5, t)))
			_pill(button_rect, button_text, 20, RED, PAPER)

	if mode == "transition":
		_draw_wipe()


## 左上角目标栏：本关要做什么、做到哪了（游戏里实现 hud()）。
func _draw_hud() -> void:
	if not game.has_method("hud"):
		return
	var lines: Array = game.hud()
	if lines.is_empty():
		return
	var h := 10.0 + lines.size() * 22.0
	var top := 54.0 if hint.is_empty() else 88.0
	var panel := Rect2(8, top, 168, h)
	draw_rect(panel, Color(INK, 0.78))
	draw_rect(panel, Color(WHEAT, 0.55), false, 1.0)
	for i in range(lines.size()):
		var row: Array = lines[i]
		var done: bool = int(row[1]) >= int(row[2])
		var y := top + 20.0 + i * 22.0
		var color := Color("#9fd18b") if done else PAPER
		draw_string(FONT, Vector2(16, y), ("✓ " if done else "· ") + str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, 120, 13, color)
		draw_string(FONT, Vector2(panel.end.x - 8 - 44, y), "%d/%d" % [row[1], row[2]], HORIZONTAL_ALIGNMENT_RIGHT, 44, 13, color)

## A remembered frame dissolves into the new artwork.
func _draw_wipe() -> void:
	var alpha := 1.0 - smoothstep(0.0, WIPE_OUT, t)
	if transition_frame:
		draw_set_transform_matrix(get_global_transform_with_canvas().affine_inverse())
		SceneWipe.paint(self, get_viewport_rect(), alpha, transition_frame)
		draw_set_transform(Vector2.ZERO)
	else:
		SceneWipe.paint(self, view_rect, alpha)

func _draw_bg() -> void:
	if sky.a > 0.0:
		for i in range(12):
			var k := i / 12.0
			draw_rect(Rect2(0, horizon * k, 360, horizon / 12.0 + 1), sky.lerp(sky.lightened(0.25), k))
		draw_rect(Rect2(0, horizon, 360, 640 - horizon), ground)
		for y in range(int(horizon) + 16, 640, 24):
			draw_line(Vector2(0, y), Vector2(360, y), ground.darkened(0.06), 1.0)
	for dd: Dictionary in decor:
		var rr: Array = dd.r
		draw_rect(Rect2(float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3])), Color(str(dd.c)))
	if bg == "":
		return
	if bg == "round1/desk_r4/writing.png":
		DeskArt.draw(self, materials, view_rect, "", 2.0, true, true)
		return
	var tex := texture(bg)
	if not tex:
		return
	DeskArt.cover(self, tex, view_rect, camera_y)
	if bg == "round1/scenes/hk_street.png":
		var plate_scale := maxf(view_rect.size.x/tex.get_width(),view_rect.size.y/tex.get_height())
		var plate_size := tex.get_size()*plate_scale
		var travel := maxf(0,(plate_size.y-view_rect.size.y)*0.5)
		var origin := view_rect.get_center()-plate_size*0.5+Vector2(0,clampf(camera_y,-travel,travel))
		draw_set_transform(origin,0,plate_size/Vector2(198,440))
		draw_string(FONT,Vector2(119,92),"九龍冰室",HORIZONTAL_ALIGNMENT_CENTER,52,11,Color("#fff1bc"))
		draw_string(FONT,Vector2(70,100),"茶記",HORIZONTAL_ALIGNMENT_CENTER,34,11,Color("#fff0a4"))
		draw_string(FONT,Vector2(71,122),"餅家",HORIZONTAL_ALIGNMENT_CENTER,30,10,Color("#492016"))
		draw_string(FONT,Vector2(158,126),"麵",HORIZONTAL_ALIGNMENT_CENTER,25,12,Color("#62251d"))
		draw_set_transform(Vector2.ZERO)
	if not location_sign.is_empty():
		var zoom := maxf(view_rect.size.x / tex.get_width(), view_rect.size.y / tex.get_height())
		var full: Vector2 = tex.get_size() * zoom
		var free_y := maxf(0.0, full.y - view_rect.size.y) * 0.5
		var art_y := view_rect.get_center().y - full.y * 0.5 + clampf(camera_y, -free_y, free_y)
		if location_sign == "香港國際機場":
			var x := view_rect.get_center().x - full.x * 0.5 + full.x * 0.644
			var y := art_y + full.y * 0.302
			var width := minf(360.0, view_rect.end.x) - x - 7.0
			text_at(Vector2(x, y + full.y * 0.020), location_sign, 13, Color("#ffe3a0"), width)
			text_at(Vector2(x, y + full.y * 0.0295), "Hong Kong", 10, Color("#ffe3a0"), width)
			text_at(Vector2(x, y + full.y * 0.0385), "International Airport", 10, Color("#ffe3a0"), width)
			var exit_sign := Rect2(x + 1, y + full.y * 0.057, width - 2.0, 20)
			draw_rect(exit_sign, Color("#101727"))
			text_at(exit_sign.position + Vector2(0, 14), "抵達香港 · Arrivals", 11, PAPER, exit_sign.size.x)
		else:
			var baseline := art_y + tex.get_height() * zoom * 0.257
			text_at(Vector2(59, baseline + 2.0), location_sign, 22, Color("#311e14"), 242)
			text_at(Vector2(59, baseline), location_sign, 22, Color("#ffe4b0"), 242)


func _draw_world() -> void:
	var items: Array = []
	var ring_glow: Array = []
	for id: String in actors:
		var a: Dictionary = actors[id]
		if a.get("hidden", false):
			continue
		if a.has("appearAfter") and world_elapsed < float(a.appearAfter):
			continue
		var pos := _v(a.at)
		var sc := float(a.get("scale", 1.0))
		if a.has("moveFrom"):
			var move_clock := maxf(0.0, world_elapsed - float(a.get("appearAfter", 0.0)))
			var k := smoothstep(0,1,move_clock/float(a.get("moveTime",2)))
			pos = _v(a.moveFrom).lerp(pos,k)
			# 车从镜头前往里开：越远越小
			if a.has("scaleFrom"): sc = lerpf(float(a.scaleFrom), sc, k)
		var tex_name := str(a.tex)
		if a.has("walkFrames"):
			var elapsed := world_elapsed - float(a.get("appearAfter", 0.0))
			if elapsed < float(a.get("moveTime", 2.0)):
				tex_name = str(a.walkFrames) % (1 + int(elapsed * 7.0) % 4)
		if a.get("ring", false) and mode == "go":
			# 正在响的手机：两帧交替、左右震动、外圈光晕，一眼看得出在响
			tex_name = tex_name.replace("_ring_1", "_ring_%d" % (1 + int(time * 8.0) % 2))
			pos.x += sin(time * 60.0) * 1.5 * (1.0 if fmod(time, 1.2) < 0.7 else 0.0)
			ring_glow.append(pos - Vector2(0, 10.0 * float(a.get("scale", 1.0))))
		items.append({"y": pos.y + float(a.get("z", 0)), "tex": tex_name, "at": pos, "flip": bool(a.get("flip", false)), "scale": sc,
			"plate": int(a.get("plate", -1)), "door": float(a.get("doorTime", 0.0))})
	if player_visible:
		items.append({"y": feet.y, "player": true})
	if companion == "toretto" and player_visible:
		var cf := "w2/common/toretto_neutral_r2.png"
		# This beach memory is viewed together from behind, before the fireworks.
		if bg == "w2/hainan/bg_wenchang_memory_r2.png" and pose == "back":
			cf = "w2/common/toretto_back_r2.png"
		if mode == "game" and game and game.has_method("companion_frame"):
			cf = game.companion_frame()
		elif mode == "go" and comp_moving and int(comp_walk / _stride(comp_pos.y)) % 2 == 0:
			cf = "w2/common/toretto_walk.png"
		items.append({"y": comp_pos.y, "tex": cf, "at": comp_pos, "flip": facing < 0, "scale": 1.0})
	for i in range(walkers.size()):
		items.append({"y": _walker_pos(walkers[i]).y, "walker": i})
	if follower != "" and player_visible:
		# 箱子拉杆握在手里：贴着身后走，不再落后一截
		var k := person_height_at(feet.y) / person_height
		var fp := feet + Vector2(-24 * facing * k, 0)
		items.append({"y": feet.y - 1, "tex": follower, "at": fp, "flip": facing < 0, "scale": k, "roll": true})
	for g: Vector2 in ring_glow:
		for k in range(3):
			var phase := fmod(time * 1.4 + k / 3.0, 1.0)
			draw_arc(g + Vector2(0, camera_y), 10.0 + phase * 34.0, 0, TAU, 32, Color(1.0, 0.92, 0.6, (1.0 - phase) * 0.7), 2.0)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	for it: Dictionary in items:
		if it.has("player"):
			_draw_player()
		elif it.has("walker"):
			_draw_walker(walkers[int(it.walker)])
		else:
			var frame: String = it.tex
			if it.get("roll", false) and walk_dist > 0.0:
				frame = frame.replace("_1", "_%d" % (1 + int(walk_dist / 8.0) % 2))
			if not sprite(frame, it.at, it.flip, it.scale, NAN, int(it.get("plate", -1)), float(it.get("door", 0.0))) and it.get("roll", false):
				var p: Vector2 = it.at
				draw_rect(Rect2(p + Vector2(-11, -34), Vector2(22, 30)), Color("#3f6f8f"))
				draw_rect(Rect2(p + Vector2(-11, -34), Vector2(22, 30)), INK, false, 2.0)
				draw_line(p + Vector2(0, -34), p + Vector2(10 * -facing, -50), INK, 2.0)
				draw_circle(p + Vector2(-6, -3), 2.5, INK)
				draw_circle(p + Vector2(6, -3), 2.5, INK)


## Drawing reads the movement state; render order never advances simulation.
func _walker_source_transform() -> Transform2D:
	var tex := texture(bg)
	if not tex: return Transform2D.IDENTITY
	var k := maxf(view_rect.size.x/tex.get_width(),view_rect.size.y/tex.get_height())
	var size := tex.get_size()*k
	var extent := maxf(0,size.y-view_rect.size.y)*0.5
	# _draw_world already adds camera_y. Match cover's clamped camera exactly.
	var origin := view_rect.get_center()-size*0.5+Vector2(0,clampf(camera_y,-extent,extent)-camera_y)
	return Transform2D(Vector2(k,0),Vector2(0,k),origin)

func _walker_pos(w: Dictionary) -> Vector2:
	var at: Vector2 = crowd.at(walkers.find(w)).pos
	return _walker_source_transform()*at if bool(w.get("sourceAnchored",false)) else at

func _walker_height(w: Dictionary, pos: Vector2) -> float:
	if bool(w.get("sourceAnchored", false)) and not bool(w.get("sourceDepthScale", false)):
		return float(w.get("sourceHeight", 310)) * _walker_source_transform().x.length()
	return person_height_at(pos.y) * WorldScale.walker_multiplier(w)


func _draw_walker(w: Dictionary) -> void:
	var state: Dictionary = crowd.at(walkers.find(w))
	if w.has("sheet"):
		_draw_sheet_walker(w, state)
		var sheet_pos: Vector2 = _walker_pos(w)
		_draw_walker_extras(w, state, sheet_pos, _walker_height(w, sheet_pos))
		return
	var heading: Vector2 = state.heading
	var row := 8 if heading.x > 0 else 4
	if absf(heading.y) > absf(heading.x): row = 0 if heading.y > 0 else 12
	if bool(w.get("fishing",false)): row = 12
	if w.has("frameRow"): row = int(w.frameRow)
	var pos: Vector2 = _walker_pos(w)
	var height := _walker_height(w, pos)
	if w.has("npc"):
		_draw_npc_strip(w, state, pos, height)
		_draw_walker_extras(w, state, pos, height)
		return
	var path := "res://assets/characters/lm/chr_LM-GUEST-%s.png" % str(w.guest)
	if not sheet_cache.has(path): sheet_cache[path] = load(path) if ResourceLoader.exists(path) else null
	var sheet: Texture2D = sheet_cache[path]
	if not sheet: return
	var f := row + (int(float(state.distance) / 8.0) % 4 if state.walking else 0)
	var key := path + str(f)
	if not sheet_rects.has(key):
		sheet_rects[key] = Rect2(sheet.get_image().get_region(Rect2i(f * 64, 0, 64, 84)).get_used_rect())
	var used: Rect2 = sheet_rects[key]
	var parts := WorldScale.guest_parts(used,height,int(w.guest))
	_shadow(pos,parts[1].size.x*0.24)
	for part in range(2):
		var target: Rect2 = parts[part]
		target.position += pos
		var source: Rect2 = parts[part+2]
		source.position.x += f*64
		draw_texture_rect_region(sheet,target,source)
	_draw_walker_extras(w, state, pos, height)


## GPT 路人整图（5 帧横条：第 0 帧站立，1–4 帧向右走）。向左走时翻转；
## 缩放按 npc_meta.json 里该条的人高，脚点落在 foot 行，和老路人共用景深标定。
const NPC_DIR := "res://hongyuan/assets/round1/npc/"
var npc_meta: Dictionary = {}
var npc_tex: Dictionary = {}
func _npc_meta(id: String) -> Dictionary:
	if npc_meta.is_empty():
		var f := FileAccess.open(NPC_DIR + "npc_meta.json", FileAccess.READ)
		npc_meta = JSON.parse_string(f.get_as_text()) if f else {"_": {}}
	return npc_meta.get(id, {})

func _draw_npc_strip(w: Dictionary, state: Dictionary, pos: Vector2, height: float) -> void:
	var id := str(w.npc)
	var m := _npc_meta(id)
	var path := NPC_DIR + id + ".png"
	if m.is_empty() or not ResourceLoader.exists(path): return
	if not npc_tex.has(id):
		npc_tex[id] = load(path)
	var sheet: Texture2D = npc_tex[id]
	if not sheet: return
	var heading: Vector2 = state.heading
	var frame := 0
	if int(m.get("frames", 5)) == 3:
		# 聊天站姿：轮到自己说话时嘴一张一合，偶尔笑；不说话时闭嘴听
		if w.has("chat") and _chat_on(w): frame = 1 + int(world_elapsed / 0.32) % 2
	elif state.walking: frame = 1 + int(float(state.distance) / 8.0) % 4
	var k := height / float(m.h)
	var fw := float(m.w)
	var src := Rect2(frame * fw, 0, fw, float(m.get("cropBottom", sheet.get_height())))
	var flip := heading.x < 0
	if w.has("face") and not state.walking: flip = int(w.face) < 0
	var submerged := height * float(w.get("wade", 0.0))
	if submerged > 0.0:
		src.size.y = float(m.foot) - submerged / k
	else:
		_shadow(pos, fw * k * 0.16)
	var dest := Rect2(-fw * k * 0.5, -float(m.foot) * k, fw * k, src.size.y * k)
	draw_set_transform(pos + Vector2(0, camera_y), 0, Vector2(-1, 1) if flip else Vector2.ONE)
	draw_texture_rect_region(sheet, dest, src, Color(str(w.get("tint", "#ffffff"))))
	draw_set_transform(Vector2(0, camera_y))
	if submerged > 0.0:
		var surface := pos - Vector2(0, submerged)
		var span := height * 0.27
		draw_line(surface - Vector2(span, 0), surface + Vector2(span, 0), Color("#a7f6f0"), 1.2)
		draw_line(surface + Vector2(-span * 0.7, 3), surface + Vector2(span * 0.5, 3), Color(0.67, 0.96, 0.94, 0.52), 1.0)


func _draw_walker_extras(w: Dictionary, state: Dictionary, pos: Vector2, height: float) -> void:
	if bool(w.get("sourceAnchored",false)) and w.has("occludeBelowSource"):
		var plate := texture(bg)
		var source_h := float(w.get("sourceHeight",310))
		var source_w := source_h*0.58
		var source_pos: Vector2 = state.pos
		# Restore only the intersection of this NPC and the foreground plate.
		# It happens before nearer actors, so it cannot erase Toretto. The same
		# original desk/flowers pixels hide the legs and keep both bouquets intact.
		var mask_y := maxf(source_pos.y-source_h,float(w.occludeBelowSource))
		var cut := Rect2(source_pos.x-source_w*0.5,mask_y,source_w,maxf(0,source_pos.y-mask_y))
		if plate and cut.has_area():
			var xf := _walker_source_transform()
			draw_texture_rect_region(plate,Rect2(xf*cut.position,cut.size*xf.x.length()),cut)
	if bool(w.get("fishing",false)):
		var hand := pos + Vector2(-height*0.12,-height*0.43)
		var tip := hand + Vector2(-23,-height*0.68+sin(world_elapsed*0.8)*2)
		draw_line(hand,tip,Color("#543d29"),1.8)
		var float_at := tip+Vector2(-15,-24)
		draw_line(tip,float_at,Color(0.9,0.94,0.95,0.65),0.8)
		draw_circle(float_at,1.5,Color("#dc6652"))


## 路人闲聊：站着的时候头顶轮流冒一句。两人一对时用 chatOffset 错开，像在你一句我一句。
const CHAT_PERIOD := 4.6
const CHAT_SHOW := 2.16
func _chat_on(w: Dictionary) -> bool:
	return fposmod(world_elapsed + float(w.get("chatOffset", 0.0)), CHAT_PERIOD) <= CHAT_SHOW

const TALK_RANGE := 96.0
const REPLY_SECONDS := 4.2

func _nearest_chat() -> int:
	var nearest := -1
	var distance := TALK_RANGE
	for i in range(walkers.size()):
		var w: Dictionary = walkers[i]
		if not w.has("reply") or crowd.at(i).walking:
			continue
		var at := _walker_pos(w)
		var gap := feet.distance_to(at)
		if gap < distance and not _on_target(_npc_talk_button(at, _walker_height(w, at)).get_center()):
			nearest = i
			distance = gap
	return nearest


func _npc_talk_button(pos: Vector2, height: float) -> Rect2:
	return Rect2(Vector2(clampf(pos.x - 18.0, 5.0, CANVAS.x - 41.0), pos.y - height - 30.0), Vector2(36, 24))


func _talk_to_npc(pos: Vector2) -> bool:
	var i := _nearest_chat()
	if i < 0:
		return false
	var w: Dictionary = walkers[i]
	var at := _walker_pos(w)
	var height := _walker_height(w, at)
	var body := Rect2(at - Vector2(height * 0.22, height), Vector2(height * 0.44, height))
	if not (_npc_talk_button(at, height).grow(8.0).has_point(pos) or body.has_point(pos)):
		return false
	if w.has("nextChat"):
		var side := int(w.get("chatSide",0))
		var other := _ambient_lines(str(w.get("chatBank","")),1-side)
		var turn := int(w.nextChat)
		w.reply = [_text(str(w.chat[turn]))]
		if not other.is_empty() and side == 0:
			w.reply.append("阿鱼：" + str(other[turn % other.size()]))
		elif not other.is_empty():
			w.reply = [str(other[turn % other.size()]), "阿鱼：" + str(w.chat[turn])]
		w.nextChat = (int(w.nextChat)+1)%w.chat.size()
	var lines: Array = w.reply if w.reply is Array else [w.reply]
	if lines.is_empty(): return false
	if npc_reply == i and npc_reply_t > REPLY_SECONDS:
		npc_reply_t = REPLY_SECONDS
	else:
		npc_reply_t = REPLY_SECONDS * lines.size()
	npc_reply = i
	moving = false
	target_hot = ""
	play("blip")
	return true


func _draw_optional_chat() -> void:
	if not player_visible:
		return
	if npc_reply_t > 0.0 and npc_reply >= 0 and npc_reply < walkers.size():
		var speaker: Dictionary = walkers[npc_reply]
		var lines: Array = speaker.reply if speaker.reply is Array else [speaker.reply]
		var turn := clampi(lines.size() - ceili(npc_reply_t / REPLY_SECONDS), 0, lines.size() - 1)
		var at := _walker_pos(speaker) if turn == 0 else feet
		var height := _walker_height(speaker, at) if turn == 0 else person_height_at(feet.y)
		_draw_guest_bubble(str(lines[turn]), at, height, minf(npc_reply_t * 3.0, 1.0))
		return
	var i := _nearest_chat()
	for index in walkers.size():
		var speaker: Dictionary = walkers[index]
		var turns: Array = speaker.get("chat", [])
		if turns.is_empty() or not _chat_on(speaker) or crowd.at(index).walking: continue
		var at := _walker_pos(speaker)
		var height := _walker_height(speaker, at)
		var turn := floori(world_elapsed / CHAT_PERIOD) % turns.size()
		_draw_guest_bubble(_text(str(turns[turn])), at - Vector2(0,32 if index == i else 0), height, 1.0)
		break
	if i >= 0:
		var w: Dictionary = walkers[i]
		var at := _walker_pos(w)
		var badge := _npc_talk_button(at, _walker_height(w, at))
		_pill(badge, "···", 16, PAPER, INK, true)
		draw_colored_polygon(PackedVector2Array([badge.end-Vector2(17,1),badge.end-Vector2(10,1),badge.end-Vector2(15,-5)]),PAPER)




func _draw_guest_bubble(text: String, pos: Vector2, height: float, a: float) -> void:
	var fs := 11
	var tw := minf(FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0, 156.0)
	var wrapped := StoryCaption.wrap_text(text, tw - 12.0, fs)
	var box_height := 19.0 + wrapped.count("\n") * 13.0
	var box := Rect2(pos.x - tw * 0.5, pos.y - height - box_height - 10 + (1.0 - a) * 4, tw, box_height)
	box.position.x = clampf(box.position.x, 4, CANVAS.x - box.size.x - 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.99, 0.96, 0.93 * a)
	sb.set_corner_radius_all(9)
	sb.anti_aliasing = true
	sb.shadow_color = Color(0, 0, 0, 0.18 * a)
	sb.shadow_size = 2
	draw_style_box(sb, box)
	var tip := Vector2(clampf(pos.x, box.position.x + 10, box.end.x - 10), box.end.y)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-4, -1), tip + Vector2(4, -1), tip + Vector2(0, 5)]), Color(1, 0.99, 0.96, 0.93 * a))
	draw_multiline_string(FONT, box.position + Vector2(6, 13), wrapped, HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 12.0, fs, -1, Color(INK, a))


## GPT 路人图集：192×208 一格，横排 5 格（第 0 格站立、1–4 行走，朝右），脚点 (96,198)，
## 人从头顶到脚底约 185 像素（遛狗、骑车的狗和车不算身高）。往左走时水平翻转。
const SHEET_CELL := Vector2(192, 208)
const SHEET_FOOT := Vector2(96, 198)
const SHEET_BODY_H := 185.0
func _draw_sheet_walker(w: Dictionary, state: Dictionary) -> void:
	var sheet := texture(str(w.sheet))
	if not sheet: return
	var pos: Vector2 = _walker_pos(w)
	var height := _walker_height(w,pos)
	var k := height / SHEET_BODY_H
	var f := 1 + int(float(state.distance) / maxf(6.0, height * STRIDE_K)) % 4 if state.walking else 0
	var heading: Vector2 = state.heading
	var flip := heading.x < 0 if f > 0 else int(w.get("face",1)) < 0
	_shadow(pos, 60.0 * k * 0.5)
	draw_set_transform(pos + Vector2(0, camera_y), 0, Vector2(-k if flip else k, k))
	draw_texture_rect_region(sheet, Rect2(-SHEET_FOOT, SHEET_CELL), Rect2(Vector2(f * SHEET_CELL.x, 0), SHEET_CELL))
	draw_set_transform(Vector2(0, camera_y))


func _player_frame() -> String:
	if mode == "game" and game and game.has_method("body_frame"):
		return game.body_frame()
	var walking := mode == "go" and (moving or stick.length() > 0.08) and move_dir.length() > 0.01
	var shizuoka_art := bg in ["round1/rework1107/shizuoka_pier_v2.png", "round1/rework1107/turtle_boarding.png", "round1/scenes/cabin.png"]
	var idle_art := "w2/shizuoka/ayu_idle.png" if shizuoka_art else "ayu_idle.png"
	var walk_dir := "w2/shizuoka" if shizuoka_art else "w2/common"
	var name := idle_art
	if player_role == "toretto":
		name = "w2/common/toretto_neutral_r2.png"
		if walking:
			name = "w2/common/toretto_walk.png" if int(walk_dist / _stride()) % 2 == 0 else "w2/common/toretto_neutral_r2.png"
		elif pose != "":
			name = {"gifts": "w2/common/toretto_gifts_r2.png", "sit": "w2/common/toretto_sit.png", "back": "w2/common/toretto_back_r2.png"}.get(pose, pose)
	elif pose != "" and not walking:
		name = {"sit": ("w2/shizuoka/ayu_sit.png|w2/shizuoka/ayu_idle.png" if shizuoka_art else "w2/shizuoka/ayu_sit.png|ayu_idle.png"), "fishing": "w2/shizuoka/ayu_fish_hold.png|w2/common/ayu_fishing.png", "throw": "w2/hainan/ayu_throw_hold.png|w2/common/ayu_throw.png", "cheer": "w2/common/ayu_cheer.png", "back": ("w2/shizuoka/ayu_walk_back_1.png|w2/common/ayu_idle_back.png" if shizuoka_art else "w2/common/ayu_idle_back.png|ayu_idle.png")}.get(pose, pose)
		if pose == "surprised": name = "w2/common/ayu_surprised.png|ayu_idle.png"
	elif walking:
		var f := 1 + int(walk_dist / _stride()) % 4
		if absf(move_dir.y) > absf(move_dir.x) * 1.3:
			var dirn := "back" if move_dir.y < 0 else "front"
			name = "%s/ayu_walk_%s_%d.png|%s/ayu_walk_side_%d.png|%s" % [walk_dir, dirn, f, walk_dir, f, idle_art]
		else:
			name = "%s/ayu_walk_side_%d.png|%s" % [walk_dir, f, idle_art]
	if follower != "" and walking:
		name = "w2/hongkong/ayu_drag_side_%d.png|%s" % [1 + int(walk_dist / _stride()) % 4, name]
	return name


func _draw_player() -> void:
	if mode == "game" and game and game.has_method("draw_body"):
		game.draw_body(self)
		return
	var walking := mode == "go" and (moving or stick.length() > 0.08) and move_dir.length() > 0.01
	var bob := -1.0 if walking and int(walk_dist / _stride()) % 2 == 0 else 0.0
	sprite(_player_frame(), feet + Vector2(0, bob), facing < 0, 1.0, feet.y)


func _draw_go_ui() -> void:
	if hotspots.has(go_id):
		var h: Dictionary = hotspots[go_id]
		var at := _v(h.at)
		var near := _near_hotspot() != ""
		if near:
			var r := _icon_rect(go_id)
			r.position.y += sin(time * 5.0) * 2.0
			var icon := texture("w2/common/icon_%s.png" % str(h.get("icon", "pick")))
			if icon:
				draw_texture_rect(icon, Rect2(r.get_center() - Vector2(24, 24), Vector2(48, 48)), false)
			else:
				_pill(r, _text(str(h.get("label", "G-13"))) if h.has("label") else "！", 16, PAPER, INK, true)
		else:
			# 远处的目标也要一眼看得到：地面双光圈 + 头顶半透明图标，轻轻上下浮动
			var a := 0.6 + sin(time * 4.5) * 0.3
			draw_circle(at, 6, Color(1.0, 0.9, 0.6, a))
			draw_arc(at, 13 + sin(time * 4.5) * 3.0, 0, TAU, 28, Color(1.0, 0.9, 0.6, a), 2.0)
			draw_arc(at, 22 + sin(time * 4.5) * 3.0, 0, TAU, 32, Color(1.0, 0.9, 0.6, a * 0.5), 1.5)
			var far_icon := texture("w2/common/icon_%s.png" % str(h.get("icon", "pick")))
			if far_icon:
				var r2 := _icon_rect(go_id)
				r2.position.y += sin(time * 3.0) * 3.0
				draw_texture_rect(far_icon, Rect2(r2.get_center() - Vector2(18, 18), Vector2(36, 36)), false, Color(1, 1, 1, 0.75))
	_draw_optional_chat()



func _draw_walk_stick() -> void:
	var pressing := down and dragged and stick_pointer
	if not pressing and t > 3.0: return
	var origin: Vector2 = pointer_input.STICK_ORIGIN
	var tint := Color(1, 1, 1, 1.0 if pressing else 0.35 * clampf(3.0 - t, 0, 1))
	var base := texture("w2/common/joystick_base.png")
	var knob := texture("w2/common/joystick_knob.png")
	if base and knob:
		draw_texture_rect(base, Rect2(origin - Vector2(36, 36), Vector2(72, 72)), false, tint)
		draw_texture_rect(knob, Rect2(origin + stick * 25 - Vector2(16, 16), Vector2(32, 32)), false, tint)


func _draw_say() -> void:
	var intro: Dictionary = beats[bi]
	if t < float(intro.get("captionDelay", 0.0)): return
	if intro.get("narrate", "") == "A3-2i":
		_pill(Rect2(220, StoryCaption.safe_top + 8, 128, 24), "视角 · Toretto", 13, RED, PAPER)
	if intro.get("captionLow", false):
		StoryCaption.draw_low_narration(self, say_text, int(reveal))
		return
	var listening := _night_bridge()
	StoryCaption.draw_caption(self, say_text, say_who, int(reveal), not listening and reveal >= say_text.length() and mode == "say", _speaker_anchor(say_who))
	if listening:
		var label := "显示整句" if reveal < say_text.length() else ("听他唱" if intro.get("narrate", "") == "A3-S3" else "接着听")
		_pill(LISTEN_RECT, label, 16, Color(INK, 0.92), PAPER)


const LISTEN_RECT := Rect2(232, 420, 116, 44)

func _night_bridge() -> bool:
	var beat: Dictionary = beats[bi]
	return beat.get("say", beat.get("narrate", "")) in ["A3-S1", "A3-S2", "A3-S3"]


func _speaker_anchor(who: String) -> Vector2:
	if who == player_role and player_visible:
		return feet - Vector2(0, person_rect(_player_frame(), feet).size.y)
	if companion != "" and who == companion and player_visible:
		return comp_pos - Vector2(0, person_rect("w2/common/toretto_neutral_r2.png", comp_pos).size.y)
	if actors.has(who) and not actors[who].get("hidden", false):
		var a: Dictionary = actors[who]
		return _v(a.at) - Vector2(0, person_rect(str(a.tex), _v(a.at), float(a.get("scale", 1))).size.y)
	return Vector2(-1, -1)


func _draw_card() -> void:
	# 章节名叠在画面上，不再黑屏：上一屏的东西一直看得见
	var beat: Dictionary = beats[bi] if bi >= 0 and bi < beats.size() else {}
	var dur := float(beat.get("duration", 1.8))
	var a := clampf(t / 0.35, 0.0, 1.0) * clampf((dur - t) / 0.35, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, CANVAS), Color(INK, 0.28 * a))
	draw_rect(Rect2(0, 270, 360, 84), Color(INK, 0.72 * a))
	draw_rect(Rect2(0, 270, 360, 2), Color(GOLD, 0.8 * a))
	draw_rect(Rect2(0, 352, 360, 2), Color(GOLD, 0.8 * a))
	draw_multiline_string(FONT, Vector2(30, 318), StoryCaption.wrap_text(say_text,300,20), HORIZONTAL_ALIGNMENT_CENTER, 300, 20, -1, Color(WHEAT, a))


func _draw_material() -> void:
	draw_rect(view_rect, bg_fill)
	_draw_bg()
	draw_rect(view_rect, Color(INK, 0.22))
	var alpha := smoothstep(MATERIAL_FADE, MATERIAL_FADE + 0.65, t)
	if material_leaving:
		alpha *= 1.0 - smoothstep(0.0, MATERIAL_FADE, material_exit_t)
	var order := DeskArt.SLOTS.find(material_id)
	if order < 0: return
	var panel := Rect2(32, 85, 296, 432)
	_panel(panel, Color(0.16, 0.10, 0.09, 0.86 * alpha), Color(GOLD, alpha))
	var ink := Color(PAPER, alpha)
	var gold := Color(Color("#c29c63"), alpha)
	draw_string(FONT, Vector2(24, 121), "七缘大冒险 · 爱情篇", HORIZONTAL_ALIGNMENT_CENTER, 312, 16, gold)
	draw_string(FONT, Vector2(24, 158), "第%d/6关：已通过" % (order + 1), HORIZONTAL_ALIGNMENT_CENTER, 312, 21, ink)
	var mat := Rect2(62, 197, 236, 193)
	draw_rect(mat, Color(Color("#392a26"), alpha))
	draw_rect(mat, gold, false, 1.0)
	var art := texture("round1/desk_r4/writing.png")
	if art:
		draw_texture_rect_region(art, mat.grow(-5), MATERIAL_DETAILS[material_id], Color(1, 1, 1, alpha))
	draw_string(FONT, Vector2(24, 441), "奖励物：" + str(MATERIAL_NAMES[material_id]), HORIZONTAL_ALIGNMENT_CENTER, 312, 23, ink)
	draw_string(FONT, Vector2(24, 478), str(MATERIAL_LINES[material_id]), HORIZONTAL_ALIGNMENT_CENTER, 312, 15, gold)
	if t >= MATERIAL_READ_TIME and not material_leaving:
		var label := "收好信封" if material_id == "envelope" else "继续回忆"
		_pill(Rect2(100, 566, 160, 44), label, 17, Color(RED, alpha), Color(PAPER, alpha))



# ---------- 快速浏览：小游戏和走路 10 秒后出「下一步」，不能整章跳过 ----------
const SKIP_RECT := Rect2(268, 96, 80, 28)
const SKIP_AFTER := 10.0
const SKIP_LABELS := {"drive":"跳过驾驶", "pandas":"跳过喂食", "fishing":"跳过钓鱼", "ringtoss":"跳过套圈", "fireworks":"跳过烟花", "song":"跳过互动", "moments":"结束浏览", "offer":"跳过互动"}

func _skip_label() -> String:
	return "直接前往" if mode == "go" else str(SKIP_LABELS.get(beats[bi].get("game", ""), "跳过互动"))
const NO_SKIP := ["call", "desk_chat", "finale", "seat", "desk_intro", "group_chat", "onsen", "care", "balance", "registration", "photo"]  # 来电对白不能删；终章要玩家自己填名字入席


func _choice_rect(i: int) -> Rect2:
	if "res://hongyuan/world_entry.tscn" in choice_to and "res://hongyuan/village_entry.tscn" in choice_to:
		return Rect2(48, 532 + i * 52, 264, 44)
	return Rect2(80, 250 + i * 62, 200, 48)


func _skip_visible() -> bool:
	if t < SKIP_AFTER or bi < 0 or bi >= beats.size():
		return false
	if mode == "game" and beats[bi].get("game", "") == "moments" and game.viewing >= 0:
		return false
	# 开车时「下一步」晚一点出现（15 秒），免得换道时误点
	if mode == "game" and str(beats[bi].get("game", "")) == "drive" and t < 15.0:
		return false
	if mode == "go":
		return hotspots.has(go_id)
	return mode == "game" and game != null and not str(beats[bi].get("game", "")) in NO_SKIP


func _skip() -> void:
	sfx.stream = blip
	sfx.play()
	if mode == "go":
		_trigger(go_id)
		return
	if game.has_method("skip"):
		game.skip()
	pose = ""
	_next()


func _hint(text: String, top := 46.0) -> void:
	var w := minf(320.0, 30.0 + 16.0 * text.length())
	_pill(Rect2((CANVAS.x - w) * 0.5, top, w, 34), text, 16, Color(INK, 0.78), WHEAT)


# ---------- 工具（小游戏也用） ----------

func texture(name: String) -> Texture2D:
	for candidate in name.split("|"):
		if candidate == "":
			continue
		if not tex_cache.has(candidate):
			var path: String = ROOT + candidate
			if not ResourceLoader.exists(path) and not candidate.begins_with("w2/"):
				path = ROOT + "w2/" + candidate
			tex_cache[candidate] = load(path) if ResourceLoader.exists(path) else null
		if tex_cache[candidate]:
			return tex_cache[candidate]
	return null


func person_height_at(floor_y: float) -> float:
	return WorldScale.height_at(scale_profile, floor_y, person_height)


func person_rect(name: String, at: Vector2, scale_k := 1.0, depth_y := NAN) -> Rect2:
	var tex := texture(name)
	if not tex: return Rect2(at, Vector2.ZERO)
	if not used_rects.has(tex): used_rects[tex] = WorldScale.visible_rect(tex)
	var height := person_height_at(at.y if is_nan(depth_y) else depth_y) * scale_k
	var local := WorldScale.local_rect(tex.resource_path, tex.get_width(), used_rects[tex], height)
	return Rect2(at + local.position, local.size)


func sprite(name: String, at: Vector2, flip := false, scale_k := 1.0, depth_y := NAN, plate := -1, door_time := 0.0) -> bool:
	var tex := texture(name)
	if not tex:
		return false
	var person := "ayu_" in name or "toretto_" in name or "axiao_" in name
	if person:
		var rect := person_rect(name, at, scale_k, depth_y)
		var used: Rect2 = Rect2(used_rects[tex])
		if used.size.y > 0:
			_shadow(at, rect.size.x * 0.28)
			draw_set_transform(at + Vector2(0, camera_y), 0, Vector2(-1, 1) if flip else Vector2.ONE)
			if name == "w2/shizuoka/ayu_idle.png":
				_draw_pier_idle(tex, Rect2(rect.position - at,rect.size),used)
			else:
				draw_texture_rect_region(tex, Rect2(rect.position - at, rect.size), used)
			draw_set_transform(Vector2(0, camera_y))
			return true
	var source := Rect2(Vector2.ZERO, tex.get_size())
	var sz := tex.get_size() * S * scale_k
	var floor_offset := 5.0 * scale_k
	var vehicle_height := WorldScale.vehicle_height_m(tex.resource_path)
	if vehicle_height > 0.0:
		source = WorldScale.vehicle_source_rect(tex.resource_path)
		var floor_y := at.y if is_nan(depth_y) else depth_y
		var height := person_height_at(floor_y) * vehicle_height / WorldScale.PERSON_HEIGHT_M
		sz = source.size * (height / source.size.y)
		floor_offset = 0.0
	else:
		at = (at / S).round() * S
	draw_set_transform(Vector2(0, camera_y))
	_shadow(at, sz.x * 0.28)
	draw_set_transform(at + Vector2(0, camera_y), 0.0, Vector2(-1, 1) if flip else Vector2.ONE)
	var target := Rect2(Vector2(-sz.x * 0.5, -sz.y + floor_offset), sz)
	draw_texture_rect_region(tex, target, source)
	if plate >= 0:
		G42Art.draw_plate(self, target, plate)
	if door_time > 0.0 and world_elapsed < door_time:
		var open := smoothstep(0.1, 0.48, world_elapsed) * (1.0 - smoothstep(door_time - 0.44, door_time, world_elapsed))
		_draw_car_door(target, open)
	draw_set_transform(Vector2(0, camera_y))
	return true


func _draw_car_door(car: Rect2, open: float) -> void:
	if open <= 0.02: return
	var h := car.size.y
	var hinge := car.position + car.size * Vector2(0.89, 0.45)
	var outer := hinge + Vector2(car.size.x * 0.31 * open, -h * 0.13 * open)
	var inset := minf(2.0, (outer.x - hinge.x) * 0.45)
	var edge_top := outer + Vector2(-inset * 0.5, h * 0.16)
	draw_colored_polygon(PackedVector2Array([hinge, outer, outer + Vector2(-inset, h * 0.45), hinge + Vector2(0, h * 0.3)]), Color("#281e36"))
	draw_colored_polygon(PackedVector2Array([hinge + Vector2(0, h * 0.12), edge_top, outer + Vector2(-inset, h * 0.42), hinge + Vector2(0, h * 0.27)]), Color("#7342a1"))
	draw_line(hinge + Vector2(0, h * 0.12), edge_top, Color("#9c70b6"), 1.5)


func _draw_pier_idle(tex: Texture2D, dest: Rect2, used: Rect2) -> void:
	var outline := PackedVector2Array([Vector2(0,0),Vector2(128,0),Vector2(128,53),Vector2(83,54),Vector2(82,59),Vector2(86,63),Vector2(87,69),Vector2(85,74),Vector2(84,84),Vector2(86,94),Vector2(128,95),Vector2(128,208),Vector2(0,208),Vector2(0,95),Vector2(41,94),Vector2(43,84),Vector2(43,74),Vector2(41,69),Vector2(42,64),Vector2(46,59),Vector2(46,54),Vector2(0,53)])
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	for point in outline:
		vertices.append(dest.position + (point - used.position) * dest.size / used.size)
		uv.append(point / tex.get_size())
	draw_polygon(vertices,PackedColorArray([Color.WHITE]),uv,tex)

func _shadow(at: Vector2, w: float) -> void:
	if not cast_shadows: return
	var pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * i / 16.0
		pts.append(at + Vector2(cos(a) * w, sin(a) * w * 0.28))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.22))


func _panel(r: Rect2, fill: Color, edge: Color) -> void:
	draw_rect(r, fill)
	draw_rect(r.grow(-2), edge, false, 2.0)
	draw_rect(r, Color(INK, 0.9), false, 2.0)


func _pill(r: Rect2, text: String, font_size: int, fill: Color, fg: Color, outline := false) -> void:
	draw_rect(r, fill)
	draw_rect(r, Color(INK, 0.95) if outline or fill.a > 0.9 else Color(GOLD, 0.6), false, 2.0)
	var asc := FONT.get_ascent(font_size)
	var desc := FONT.get_descent(font_size)
	draw_string(FONT, Vector2(r.position.x, r.position.y + (r.size.y + asc - desc) * 0.5), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, font_size, fg)


func text_at(pos: Vector2, text: String, font_size: int, color: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_multiline_string(FONT, pos, StoryCaption.wrap_text(text,width,font_size), align, width, font_size, -1, color)


func pill(r: Rect2, text: String, font_size: int, fill: Color, fg: Color) -> void:
	_pill(r, text, font_size, fill, fg, true)


func _text(id: String) -> String:
	return keep_units(str(copy.get(id, id)).replace("<br>", "\n"))


static var _unit_re: RegEx
## 「24 年」「10 个月」：数字和后面的字之间去掉空格：Web 包会在任何空格（含不断行空格）处折行
static func keep_units(s: String) -> String:
	if _unit_re == null:
		_unit_re = RegEx.create_from_string("(\\d) (?=[\\x{4e00}-\\x{9fff}])")
	return _unit_re.sub(s, "$1", true)


func t_(id: String) -> String:
	return _text(id)


func play(kind: String) -> void:
	sfx.stream = pop if kind == "pop" else blip
	sfx.play()


static func _v(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _tone(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in range(n):
		var k := float(i) / n
		ph += TAU * lerpf(f0, f1, k) / rate
		var s := int(sin(ph) * 9000.0 * (1.0 - k))
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

# Only gameplay values enter the checkpoint. Nodes, resources, input holds and caches do not.
const GAME_SAVE_FIELDS := ["phase", "t", "power", "bob", "from", "wait_for", "fish_t", "missed",
	"thinned", "cloud_rounds", "cloud_arrivals",
	"li", "reveal", "hand", "aim", "thrown", "rings", "hit_flash", "bursts", "count", "need",
	"finale_t", "color_offset", "look", "hold", "name", "error", "lane", "car_x", "scroll",
	"speed", "bump", "traffic", "spawn_at", "bay_y", "park_t", "hint_t", "birthday_seen", "birthday_flash", "call_time", "speaker_on", "chat_scroll", "wi", "wechat_done",
	"caught", "fed", "hungry", "bamboo_held", "feed_flash", "last_fed", "ayu_x", "toretto_x", "sky_s", "field", "typed", "typing", "read_index", "cleared", "levels", "touches", "tended", "glow", "handed", "turn", "auto_t"]

func snapshot() -> Dictionary:
	var saved := {"beat": bi, "mode": mode, "feet": [feet.x, feet.y], "facing": facing, "comp_pos": [comp_pos.x, comp_pos.y],
			"target": [target.x, target.y], "moving": moving, "walk_dist": walk_dist,
		"pose": pose, "t": t, "reveal": reveal, "result": result.duplicate(true), "trail": [], "atmosphere_elapsed": atmosphere_elapsed, "world_elapsed": world_elapsed}
	for p: Vector2 in trail:
		saved.trail.append([p.x, p.y])
	if game:
		var values := {}
		for prop: Dictionary in game.get_property_list():
			var key := str(prop.name)
			if key in GAME_SAVE_FIELDS:
				values[key] = _pack_value(game.get(key))
		if "edit" in game and is_instance_valid(game.edit):
			values.name = game.edit.text
		if "rng" in game:
			values.rng_state = str(game.rng.state)
		saved.game = values
	return saved

func restore(saved: Dictionary) -> void:
	if int(saved.get("beat", -1)) != bi or str(saved.get("mode", "")) != mode:
		return
	feet = _v(saved.get("feet", [feet.x, feet.y]))
	facing = float(saved.get("facing", facing))
	comp_pos = _v(saved.get("comp_pos", [feet.x + 48.0, feet.y - 4.0]))
	target = _v(saved.get("target", [feet.x, feet.y]))
	moving = bool(saved.get("moving", false)) and mode == "go"
	walk_dist = float(saved.get("walk_dist", 0))
	pose = str(saved.get("pose", pose))
	t = float(saved.get("t", 0))
	atmosphere_elapsed = float(saved.get("atmosphere_elapsed", 0))
	world_elapsed = float(saved.get("world_elapsed", 0.0))
	crowd.restore_once(world_elapsed)
	reveal = float(saved.get("reveal", 0))
	result = saved.get("result", {}).duplicate(true)
	trail.clear()
	for p: Array in saved.get("trail", []):
		trail.append(_v(p))
	if game and saved.get("game", null) is Dictionary:
		var values: Dictionary = saved.game
		for prop: Dictionary in game.get_property_list():
			var key := str(prop.name)
			if key in GAME_SAVE_FIELDS and values.has(key):
				game.set(key, _unpack_value(values[key]))
		if "rng" in game and values.has("rng_state"):
			game.rng.state = int(values.rng_state)
		if "edit" in game and game.phase == "name":
			game._make_edit()
			game.edit.text = game.name
		if game.has_method("restore_checkpoint"):
			game.restore_checkpoint()
	queue_redraw()

static func _pack_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"vector2": [value.x, value.y]}
	if value is Array:
		return value.map(_pack_value)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _pack_value(value[key])
		return out
	return value

static func _unpack_value(value: Variant) -> Variant:
	if value is Array:
		return value.map(_unpack_value)
	if value is Dictionary:
		if value.has("vector2"):
			return _v(value.vector2)
		var out := {}
		for key: Variant in value:
			out[key] = _unpack_value(value[key])
		return out
	return value

func suspend_input() -> void:
	pointer_input.reset()
	_reset_input()
	if game:
		if "holding" in game:
			game.holding = false
		if "dragging" in game:
			game.dragging = false
		if "swiping" in game:
			game.swiping = false


func _goal_layout() -> Dictionary:
	var task := StoryCaption.wrap_text(str(goal_data.get("任务", "")), 216, 16)
	var reward := Rect2(42, maxf(186.0, 155.0 + (task.count("\n") + 1) * 22.0), 276, 68)
	var button_y := reward.end.y + 12.0
	var button := Rect2(90, button_y, 180, 43)
	return {"task": task, "reward": reward, "box": Rect2(24, 64, 312, button.end.y - 50.0), "button": button}


func _draw_goal_reward(row: Rect2, alpha: float) -> void:
	var reward_id := str(spec.get("goalRewardId", ""))
	if not MATERIAL_NAMES.has(reward_id):
		return
	draw_line(row.position, Vector2(row.end.x, row.position.y), Color(GOLD, alpha), 1)
	var baseline := row.get_center().y + 8.0
	draw_string(FONT, Vector2(row.position.x, baseline), "奖励物", HORIZONTAL_ALIGNMENT_LEFT, 54, 15, Color(RED, alpha))
	draw_string(FONT, Vector2(176, baseline), MATERIAL_NAMES[reward_id], HORIZONTAL_ALIGNMENT_LEFT, 134, 20, Color(INK, alpha))
	var art := texture("round1/desk_r3/object_%s.png" % reward_id)
	if art == null:
		return
	var slot := Rect2(98, row.position.y + 5, 68, 58)
	draw_rect(slot, Color("#ead9b9", alpha))
	draw_rect(slot, Color(GOLD, alpha), false, 2)
	var used: Rect2 = WorldScale.visible_rect(art)
	var fit := minf(58.0 / used.size.x, 48.0 / used.size.y)
	var size := used.size * fit
	draw_texture_rect_region(art, Rect2(slot.get_center() - size * 0.5, size), used, Color(1, 1, 1, alpha))
