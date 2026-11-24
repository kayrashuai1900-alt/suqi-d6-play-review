extends RefCounted
## 深夜动态保留点赞互动，旅行动态直接浏览已发布的内容。
const StoryCaption := preload("res://hongyuan/ui/story_caption.gd")
var r
var phase := "read"          # read → liked → done
var t := 0.0
var liked_t := 0.0
var scroll := 0.0
var dragging := false
var last_y := 0.0
var menu := false
var menu_t := 0.0
var lines: PackedStringArray = []
var toast := ""
var viewing := -1           # 正在看大图的那张（-1 表示没在看）
var view_t := 0.0
var swiping := false
var swipe_start := Vector2.ZERO
var post: Dictionary = {}
var photos: Array = []
var post_likes: Array = []
var post_comments: Array = []
var post_date := ""
var post_location := ""
var post_author := "阿鱼。"
var author_avatar := "ayu_avatar.png"
var body_size := FS
var like_atlas: Texture2D
var like_tiles: Array[Rect2] = []
var authored_reactions := false

const FS := 15
const LH := 24.0
const NAV_H := 52.0
const TEXT_X := 62.0
const TEXT_W := 284.0
const BLUE := Color("#576b95")
const GRAY := Color("#b2b2b2")
const INK := Color("#191919")
const PANEL := Color("#f7f7f7")
const PAPER := Color("#fffcf6")
const PHOTO := 92.0
const POST_PHOTO := 84.0
const PHOTO_GAP := 4.0
const DATE_LINE := 22.0
const POST_COLUMNS := 3
const MAX_PHOTOS := 9
const FOOTER_Y := 570.0
const CONTINUE := Rect2(84, 582, 192, 44)
const VIEW_CLOSE := Rect2(6, 6, 44, 44)
const LIKE_COLUMNS := 8
const ATLAS_ICON := 29.0
const ATLAS_STEP := 32.0
const COMMENT_FONT := 13
const COMMENT_X := TEXT_X + 41.0
const COMMENT_WIDTH := 346.0 - COMMENT_X - 8.0
const COMMENT_LINE := 19.0
## 四张生活照：GPT 出的正式图（w2/call/moments_N.png）到位就用它，没到位先用游戏里现成场景的局部
const PHOTOS := [
	["w2/call/moments_1.png", "w2/call/ayu_toretto_holdhands.png", Rect2(0, 820, 841, 841)],
	["w2/call/moments_2.png", "round1/people/call_split.png", Rect2(110, 40, 740, 740)],
	["w2/call/moments_3.png", "round1/people/call_split.png", Rect2(80, 900, 760, 760)],
	["w2/call/moments_4.png", "round1/people/daily_walk.png", Rect2(0, 860, 841, 841)],
]
## 点赞栏里先有的朋友（游戏角色和泛化的朋友），点赞后 Toretto 排到最前
const FRIENDS := [
	["axiao_avatar.png", "", Color.WHITE],
	["", "猫", Color("#e9c9a8")],
	["", "海", Color("#8fb8d8")],
	["", "星", Color("#3c4f86")],
	["", "花", Color("#f2b8c6")],
	["", "糖", Color("#c8e0b4")],
	["", "鹿", Color("#c9a27e")],
	["", "云", Color("#d8dde6")],
	["", "橘", Color("#f4b26b")],
]

# 版面（内容坐标，未减滚动）
var y_body := 0.0
var y_photos := 0.0
var y_meta := 0.0
var y_panel := 0.0
var bottom := 0.0

func start(runner, beat: Dictionary) -> void:
	r = runner
	var body := str(r.copy.get(str(beat.get("text", "")), ""))
	r.hint = ""
	post = beat.get("post", {})
	photos = post.get("photos", PHOTOS).slice(0, MAX_PHOTOS)
	if post.is_empty():
		toast = "上下滑动，读完她那晚写下的话"
	else:
		phase = "posted"
		if post.has("assetPattern"):
			body = "\n".join(post.body)
			body_size = 14
			_load_authored_post()
		else:
			post_date = str(r.copy.get(post.get("date", ""), ""))
			post_location = r.t_(str(post.get("location", "")))
			for who: String in post.get("likes", []):
				post_likes.append([who + "_avatar.png", "", Color.WHITE])
			for comment: Dictionary in post.get("comments", []):
				post_comments.append([StoryCaption.NAMES.get(comment.who, comment.who), r.t_(comment.say)])
	lines = StoryCaption.wrap_text(body.replace("<br>", "\n"), TEXT_W, body_size).split("\n")
	_layout()

func _load_authored_post() -> void:
	authored_reactions = true
	post_date = str(post.date)
	post_location = str(post.location)
	post_author = str(post.author)
	author_avatar = _post_asset(post.authorAvatar)
	like_atlas = r.texture(_post_asset(post.likes.file))
	for item: Dictionary in post.likes.items:
		like_tiles.append(Rect2(float(item.x), float(item.y), float(item.w), float(item.h)))
	for comment: Dictionary in post.comments:
		var wrapped := StoryCaption.wrap_text(comment.text, COMMENT_WIDTH, COMMENT_FONT)
		post_comments.append({
			"name": comment.name, "time": comment.time, "avatar": _post_asset(comment.avatar),
			"lines": wrapped.split("\n"),
		})

func _post_asset(file: String) -> String:
	return str(post.assetPattern) % file.get_basename()

func _layout() -> void:
	y_body = NAV_H + 44.0
	y_photos = y_body + lines.size() * LH + 10.0
	var rows := ceili(float(_photo_count()) / _photo_columns())
	var grid_height := rows * _photo_size() + maxi(0, rows - 1) * PHOTO_GAP
	y_meta = y_photos + grid_height + 22.0
	y_panel = y_meta + 18.0 + (DATE_LINE if not post_date.is_empty() else 0.0)
	bottom = y_panel + _panel_h() + (6.0 if not post.is_empty() else 40.0)

func _like_people() -> Array:
	if not post.is_empty():
		return post_likes
	if phase == "read":
		return FRIENDS
	return [["toretto_avatar.png", "", Color.WHITE]] + FRIENDS

func _like_rows() -> int:
	var count := like_tiles.size() if authored_reactions else _like_people().size()
	return ceili(float(count) / LIKE_COLUMNS)

func _comments() -> Array:
	if not post.is_empty():
		return post_comments
	var c := [["阿鱼。", "谢谢大家～点赞即祝福哈哈哈哈"], ["阿晓", "所以电脑最后修好了吗"]]
	if phase != "read":
		c.append(["Toretto", "下次换台电脑，再唱给你听。"])
	return c

func _panel_h() -> float:
	if authored_reactions:
		var height := 12.0 + _like_rows() * ATLAS_STEP + 6.0
		for comment: Dictionary in post_comments:
			height += _comment_h(comment)
		return height
	return 12.0 + _like_rows() * 34.0 + 8.0 + _comments().size() * 24.0 + 8.0

func _comment_h(comment: Dictionary) -> float:
	return 34.0 + comment.lines.size() * COMMENT_LINE

func _max_scroll() -> float:
	return maxf(0.0, bottom - (FOOTER_Y if not post.is_empty() else 640.0))

func _dots_rect() -> Rect2:
	return Rect2(312, y_meta - 15 - scroll, 34, 22)

func _like_btn() -> Rect2:
	var d := _dots_rect()
	return Rect2(d.position.x - 152, d.position.y - 8, 74, 38)

func process(dt: float) -> bool:
	if phase == "done":
		return true
	t += dt
	view_t += dt
	if not post.is_empty():
		return false
	if menu:
		menu_t += dt
	if phase == "read" and scroll >= _max_scroll() - 30 and toast.begins_with("上下"):
		toast = "读完了，点右下角的「··」给她点个赞"
	if phase == "liked":
		liked_t += dt
		# 点赞后把新长出来的点赞栏和评论滑进来
		scroll = move_toward(scroll, _max_scroll(), 240.0 * dt)
		if liked_t > 2.6:
			phase = "done"
			return true
	return false

# The runner restores phase/scroll after start() has laid out the unread post.
func restore_checkpoint() -> void:
	_layout()
	scroll = clampf(scroll, 0.0, _max_scroll())
	if phase != "read":
		toast = ""

func _photo_rect(k: int) -> Rect2:
	var columns := _photo_columns()
	var side := _photo_size()
	var step := side + PHOTO_GAP
	return Rect2(TEXT_X + (k % columns) * step, y_photos - scroll + floori(float(k) / columns) * step, side, side)

func _photo_columns() -> int:
	return 2 if post.is_empty() else POST_COLUMNS

func _photo_size() -> float:
	if post.is_empty(): return PHOTO
	return 178.0 if photos.size() == 1 else POST_PHOTO

func input(kind: String, pos: Vector2) -> void:
	if viewing >= 0:
		_view_input(kind, pos)
		return
	if phase not in ["read", "posted"]:
		return
	var content_end := FOOTER_Y if phase == "posted" else 640.0
	match kind:
		"down":
			dragging = pos.y > NAV_H and pos.y < content_end
			last_y = pos.y
		"move":
			if dragging:
				scroll = clampf(scroll - (pos.y - last_y), 0, _max_scroll())
				last_y = pos.y
		"up":
			dragging = false
		"tap":
			if phase == "posted" and CONTINUE.has_point(pos):
				phase = "done"
				r.play("pop")
				return
			if pos.y <= NAV_H or pos.y >= content_end:
				return
			if menu and _like_btn().grow(6).has_point(pos):
				_like()
				return
			for k in range(_photo_count()):
				if not menu and _photo_rect(k).has_point(pos):
					viewing = k
					view_t = 0.0
					r.play("pop")
					return
			if phase == "posted":
				return
			if _dots_rect().grow(10).has_point(pos):
				menu = not menu
				menu_t = 0.0
				r.play("pop")
			else:
				menu = false

func _view_input(kind: String, pos: Vector2) -> void:
	match kind:
		"down":
			swiping = true
			swipe_start = pos
		"up":
			var delta := pos - swipe_start
			if swiping and absf(delta.x) >= 36.0 and absf(delta.x) > absf(delta.y):
				_change_photo(1 if delta.x < 0 else -1)
			swiping = false
		"tap":
			if VIEW_CLOSE.has_point(pos) or (pos.x >= 64 and pos.x <= 296):
				viewing = -1
			elif pos.y >= NAV_H:
				_change_photo(-1 if pos.x < 64 else 1)

func _change_photo(delta: int) -> void:
	var index := clampi(viewing + delta, 0, _photo_count() - 1)
	if index != viewing:
		viewing = index
		view_t = 0.12
		r.play("pop")

func _like() -> void:
	menu = false
	phase = "liked"
	liked_t = 0.0
	toast = ""
	r.play("pop")
	_layout()

## 测试和走查脚本用：直接滑到底并点赞
func auto_like() -> void:
	scroll = _max_scroll()
	_like()

func draw(ci) -> void:
	if viewing >= 0:
		_draw_viewer(ci)
		return
	var published := not post.is_empty()
	var s := scroll
	var content_end := FOOTER_Y if published else 640.0
	ci.draw_rect(ci.view_rect, PAPER if published else Color.WHITE)
	# 头像、名字
	var top := NAV_H + 14 - s
	_avatar(ci, author_avatar, "", Color.WHITE, Rect2(12, top, 42, 42))
	ci.text_at(Vector2(TEXT_X, top + 17), post_author, 16, BLUE, 200, HORIZONTAL_ALIGNMENT_LEFT)
	# 正文
	for i in range(lines.size()):
		var y := y_body + i * LH - s + 4
		if y < NAV_H or y > content_end + 20.0:
			continue
		ci.text_at(Vector2(TEXT_X, y), lines[i], body_size, INK, TEXT_W, HORIZONTAL_ALIGNMENT_LEFT)
	for k in range(_photo_count()):
		var rect := _photo_rect(k)
		if rect.end.y < NAV_H or rect.position.y > content_end:
			continue
		_draw_photo(ci, k, rect, true)
	# 时间行和「··」
	var my := y_meta - s
	if not post_date.is_empty():
		ci.text_at(Vector2(TEXT_X, my), post_date, 14, Color("#736c66"), TEXT_W, HORIZONTAL_ALIGNMENT_LEFT)
		my += DATE_LINE
	var metadata := post_location if published else "深夜 · 异地的最后一段日子"
	ci.text_at(Vector2(TEXT_X, my), metadata, 14 if published else 12, BLUE if published else GRAY, 240, HORIZONTAL_ALIGNMENT_LEFT)
	var d := _dots_rect()
	if phase == "read" and not menu and scroll >= _max_scroll() - 30:
		var a := 0.35 + 0.35 * sin(t * 5.0)
		ci.draw_style_box(_box(Color(0, 0, 0, 0), 6, Color(BLUE, a), 2), d.grow(4))
	if not published:
		ci.draw_style_box(_box(PANEL, 4), d)
		ci.draw_circle(d.get_center() + Vector2(-5, 0), 2.4, BLUE)
		ci.draw_circle(d.get_center() + Vector2(5, 0), 2.4, BLUE)
	# 点赞和评论栏
	_draw_panel(ci, y_panel - s)
	# 弹出的「赞 | 评论」
	if menu:
		var k := clampf(menu_t / 0.12, 0, 1)
		var box := Rect2(d.position.x - 156 + 156 * (1 - k), d.position.y - 8, 150 * k, 38)
		ci.draw_style_box(_box(Color("#4c4c4c"), 6), box)
		if k >= 1:
			ci.text_at(Vector2(box.position.x, box.position.y + 25), "♡ 赞", 14, Color.WHITE, 76)
			ci.draw_line(Vector2(box.position.x + 76, box.position.y + 10), Vector2(box.position.x + 76, box.end.y - 10), Color(1, 1, 1, 0.25), 1)
			ci.text_at(Vector2(box.position.x + 76, box.position.y + 25), "评论", 14, Color.WHITE, 74)
	# 顶栏（盖在滚动内容上面）
	ci.draw_rect(Rect2(ci.view_rect.position, Vector2(ci.view_rect.size.x, NAV_H - ci.view_rect.position.y)), Color("#f2eadb") if published else Color("#ededed"))
	ci.draw_line(Vector2(0, NAV_H), Vector2(360, NAV_H), Color("#dfd4c1") if published else Color("#dcdcdc"), 1)
	ci.text_at(Vector2(0, 34), "朋友圈" if published else "详情", 17, INK, 360)
	if published:
		ci.draw_rect(Rect2(Vector2(0, FOOTER_Y), Vector2(360, ci.view_rect.end.y - FOOTER_Y)), PAPER)
		ci.draw_line(Vector2(14, FOOTER_Y), Vector2(346, FOOTER_Y), Color("#e8dece"), 1)
		ci.pill(CONTINUE, "继续回忆", 16, ci.RED, ci.PAPER)
	# 滚动条
	if _max_scroll() > 0:
		var view := content_end - NAV_H
		var bar_h := view * view / (view + _max_scroll())
		ci.draw_style_box(_box(Color(0, 0, 0, 0.18), 2), Rect2(354, NAV_H + (view - bar_h) * scroll / _max_scroll(), 3, bar_h))
	# 底部提示
	if toast != "" and viewing < 0:
		var w := minf(320.0, 30.0 + 14.0 * toast.length())
		var tr := Rect2((360 - w) * 0.5, 588, w, 32)
		ci.draw_style_box(_box(Color(0, 0, 0, 0.62), 16), tr)
		ci.text_at(Vector2(tr.position.x, tr.position.y + 21), toast, 14, Color.WHITE, w)

func _draw_photo(ci, k: int, rect: Rect2, thumbnail := false) -> void:
	var entry = photos[k]
	var tex: Texture2D = ci.texture(entry[0] if post.is_empty() else entry.asset)
	var source := Rect2()
	if not tex and post.is_empty():
		tex = ci.texture(entry[1])
		source = entry[2]
	if not tex:
		ci.draw_rect(rect, Color("#e8e2da"))
		return
	if not source.has_area():
		source.size = tex.get_size()
	if thumbnail:
		var side := minf(source.size.x, source.size.y)
		var square := Vector2.ONE * side
		var crop_y := 0.5 if post.is_empty() else clampf(float(entry.get("thumbnailY", 0.5)), 0.0, 1.0)
		source = Rect2(source.position + (source.size - square) * Vector2(0.5, crop_y), square)
	else:
		var fit := minf(rect.size.x / source.size.x, rect.size.y / source.size.y)
		var fitted := source.size * fit
		rect = Rect2(rect.get_center() - fitted / 2.0, fitted)
	ci.draw_texture_rect_region(tex, rect, source)

func _draw_viewer(ci) -> void:
	ci.draw_rect(ci.view_rect, Color("#151314"))
	var zoom := lerpf(0.92, 1.0, smoothstep(0.0, 0.16, view_t))
	var area := Vector2(360, 526) * zoom
	_draw_photo(ci, viewing, Rect2(Vector2(180, 316) - area / 2.0, area))
	var count := _photo_count()
	ci.text_at(Vector2(0, 33), "%d / %d" % [viewing + 1, count], 15, Color.WHITE, 360)
	var close := VIEW_CLOSE.get_center()
	ci.draw_line(close - Vector2(6, 6), close + Vector2(6, 6), Color.WHITE, 2, true)
	ci.draw_line(close + Vector2(-6, 6), close + Vector2(6, -6), Color.WHITE, 2, true)
	if not post.is_empty() and photos[viewing].has("caption"):
		ci.text_at(Vector2(12, 606), ci.t_(photos[viewing].caption), 15, Color.WHITE, 336)
	if viewing > 0:
		_draw_viewer_arrow(ci, Vector2(22, 316), -1)
	if viewing < count - 1:
		_draw_viewer_arrow(ci, Vector2(338, 316), 1)

func _draw_viewer_arrow(ci, at: Vector2, direction: int) -> void:
	ci.draw_circle(at, 14.0, Color(0, 0, 0, 0.5))
	ci.draw_polyline(PackedVector2Array([at + Vector2(-3 * direction, -6), at + Vector2(3 * direction, 0), at + Vector2(-3 * direction, 6)]), Color.WHITE, 2.0, true)

func _photo_count() -> int:
	return photos.size()

func _draw_panel(ci, y: float) -> void:
	if authored_reactions:
		_draw_authored_panel(ci, y)
		return
	var people := _like_people()
	var comments := _comments()
	if people.is_empty() and comments.is_empty(): return
	var rect := Rect2(TEXT_X, y, 346 - TEXT_X, _panel_h())
	ci.draw_colored_polygon(PackedVector2Array([Vector2(TEXT_X + 14, y - 6), Vector2(TEXT_X + 8, y), Vector2(TEXT_X + 20, y)]), PANEL)
	ci.draw_style_box(_box(PANEL, 4), rect)
	# 爱心 + 头像
	if not people.is_empty(): _heart(ci, Vector2(TEXT_X + 14, y + 26), 7.0, BLUE)
	for i in range(people.size()):
		var at := Vector2(TEXT_X + 30 + (i % 8) * 31, y + 12 + int(i / 8) * 34)
		var size := 28.0
		if phase == "liked" and i == 0:
			var k := clampf(liked_t / 0.35, 0, 1)
			size = 28.0 * (1.0 + 0.35 * sin(k * PI)) * k
		var p: Array = people[i]
		_avatar(ci, str(p[0]), str(p[1]), p[2], Rect2(at + Vector2(14 - size * 0.5, 14 - size * 0.5), Vector2(size, size)))
	# 评论
	var cy := y + 12 + _like_rows() * 34.0 + 4
	ci.draw_line(Vector2(TEXT_X + 6, cy), Vector2(rect.end.x - 6, cy), Color("#e6e6e6"), 1)
	for c: Array in comments:
		cy += 24
		var name := str(c[0]) + "："
		var nw := 0.0
		for ch in name:
			nw += 7.5 if ch.unicode_at(0) < 128 else 13.0
		ci.text_at(Vector2(TEXT_X + 10, cy - 6), name, 13, BLUE, nw + 4, HORIZONTAL_ALIGNMENT_LEFT)
		ci.text_at(Vector2(TEXT_X + 10 + nw, cy - 6), str(c[1]), 13, INK, rect.size.x - nw - 14, HORIZONTAL_ALIGNMENT_LEFT)

func _draw_authored_panel(ci, y: float) -> void:
	var rect := Rect2(TEXT_X, y, 346 - TEXT_X, _panel_h())
	if rect.end.y <= NAV_H or y >= FOOTER_Y:
		return
	ci.draw_style_box(_box(Color("#eeeeed"), 4), rect)
	var grid_top := y + 10.0
	if grid_top + ATLAS_ICON > NAV_H and grid_top < FOOTER_Y:
		_heart(ci, Vector2(TEXT_X + 12, grid_top + 12), 7.0, BLUE)
	if like_atlas:
		var first := clampi(floori((NAV_H - grid_top) / ATLAS_STEP), 0, _like_rows())
		var end := clampi(ceili((FOOTER_Y - grid_top) / ATLAS_STEP), 0, _like_rows())
		for row in range(first, end):
			for i in range(row * LIKE_COLUMNS, mini((row + 1) * LIKE_COLUMNS, like_tiles.size())):
				var at := Vector2(TEXT_X + 26 + (i % LIKE_COLUMNS) * ATLAS_STEP, grid_top + row * ATLAS_STEP)
				ci.draw_texture_rect_region(like_atlas, Rect2(at, Vector2.ONE * ATLAS_ICON), like_tiles[i])
	var comment_top := y + 12.0 + _like_rows() * ATLAS_STEP + 6.0
	for comment: Dictionary in post_comments:
		var height := _comment_h(comment)
		if comment_top >= FOOTER_Y:
			break
		if comment_top + height > NAV_H:
			_draw_authored_comment(ci, comment, comment_top)
		comment_top += height

func _draw_authored_comment(ci, comment: Dictionary, y: float) -> void:
	ci.draw_line(Vector2(TEXT_X + 7, y), Vector2(339, y), Color("#dbd5ce"), 1)
	_avatar(ci, comment.avatar, "", Color.WHITE, Rect2(TEXT_X + 8, y + 8, 26, 26))
	ci.text_at(Vector2(COMMENT_X, y + 20), comment.name, COMMENT_FONT, BLUE, COMMENT_WIDTH - 48, HORIZONTAL_ALIGNMENT_LEFT)
	ci.text_at(Vector2(291, y + 20), comment.time, 10, Color("#736c66"), 47, HORIZONTAL_ALIGNMENT_RIGHT)
	for index in range(comment.lines.size()):
		ci.text_at(Vector2(COMMENT_X, y + 39 + index * COMMENT_LINE), comment.lines[index], COMMENT_FONT, INK,
			COMMENT_WIDTH, HORIZONTAL_ALIGNMENT_LEFT)

func _avatar(ci, tex_name: String, letter: String, fill: Color, rect: Rect2) -> void:
	if rect.size.x <= 1:
		return
	var tex: Texture2D = ci.texture(tex_name) if tex_name != "" else null
	if tex:
		ci.draw_rect(rect, Color("#f0ebe4"))
		ci.draw_texture_rect(tex, rect, false)
	else:
		ci.draw_style_box(_box(fill, 3), rect)
		ci.text_at(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.7), letter, int(rect.size.y * 0.5), Color(1, 1, 1, 0.92), rect.size.x)

static func _heart(ci, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(25):
		var a := TAU * i / 24.0
		var x := 16.0 * pow(sin(a), 3)
		var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
		pts.append(c + Vector2(x, y) * s / 16.0)
	ci.draw_polyline(pts, col, 1.6, true)

static func _box(fill: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(radius)
	b.anti_aliasing = true
	if bw > 0:
		b.border_color = border
		b.set_border_width_all(bw)
	return b
