extends RefCounted
const Desk := preload("res://hongyuan/ui/desk_art.gd")
var r
var t := 0.0
var done := false
var copy_id := "A0-1"
func start(runner, beat: Dictionary) -> void:
	r = runner
	copy_id = str(beat.get("copyId", "A0-1"))
func process(dt: float) -> bool:
	t += dt
	return done
func input(kind: String, _pos: Vector2) -> void:
	if kind == "tap" and t > 0.5:
		done = true
		r.play("blip")
func draw(ci) -> void:
	Desk.draw(ci, r.materials, r.view_rect, "", t)
	if copy_id == "A0-2":
		ci.pill(Rect2(18,174,324,282),"",16,ci.PAPER,ci.INK)
		ci.text_at(Vector2(26,211),"写完这封邀请函，需要六件东西",19,ci.INK,308)
		ci.text_at(Vector2(26,239),"每走过一段回忆，就带回一件。",15,ci.RED,308)
		for index in Desk.SLOTS.size():
			var item: String = Desk.SLOTS[index]
			var pos := Vector2(77 + index % 3 * 103, 279 + floori(index / 3.0) * 90)
			var icon := Desk.texture("round1/desk_r3/object_%s.png" % item)
			if icon: ci.draw_texture_rect(icon, Rect2(pos - Vector2(32,32),Vector2(64,64)), false)
			ci.text_at(pos + Vector2(-44,51),ci.MATERIAL_NAMES[item],16,ci.INK,88)
	else:
		ci.StoryCaption.draw_caption(ci, ci.t_(copy_id), "ayu", -1, false, Desk.head(r.view_rect))
	ci.pill(Rect2(104, 566, 152, 44), "轻点继续", 17, ci.RED, ci.PAPER)
