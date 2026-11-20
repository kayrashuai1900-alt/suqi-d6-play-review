extends Control
## A short handoff in the love story before the selected destination takes over.
const DeskArt := preload("res://hongyuan/ui/desk_art.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")
const WeddingArt := "round1/common/welcome_entrance_r2.png"
const VillageArt := "w2/common/chapter_end_prologue.png"

var venue := false
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()
var view_rect := Rect2(0, 0, 360, 640)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	draw_rect(view_rect, Color("#392920"))
	DeskArt.cover(self, DeskArt.texture(WeddingArt if venue else VillageArt), view_rect)
	draw_rect(Rect2(62, 513, 236, 46), Color(0.19, 0.11, 0.08, 0.81))
	var title := "抵达罗曼山庄" if venue else "先去裳泓村"
	draw_string(FONT, Vector2(20, 543), title, HORIZONTAL_ALIGNMENT_CENTER, 320, 20, Color("#ffe7c0"))
