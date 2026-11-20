extends RefCounted

const FRONT := "round1/vehicles/g42_front_r2.png"
const PLATE_SOURCE := "res://hongyuan/assets/round1/common/splash_1108.png"
static var plate_texture: Texture2D
const PLATE_AREAS := [Rect2(93, 489, 52, 17), Rect2(398, 489, 53, 17)]

## Use the opening illustration's original pixel lettering on the corresponding car.
static func draw_plate(ci: CanvasItem, front: Rect2, index: int) -> void:
	# The solid bumper strip is just below the two kidney grilles. Its centre
	# sits left of the sprite midpoint because the car is seen at an angle.
	var size := Vector2(front.size.x * 0.171, front.size.x * 0.052)
	var center := front.position + front.size * Vector2(0.446, 0.721)
	if not plate_texture:
		plate_texture = load(PLATE_SOURCE) as Texture2D
	if not plate_texture: return
	var plate := Rect2(center - size * 0.5, size)
	ci.draw_rect(plate.grow(front.size.x * 0.004), Color("#211f2c"))
	ci.draw_texture_rect_region(plate_texture, plate, PLATE_AREAS[index])


## The end illustration uses three-quarter views. Keep the same original
## plates and align them to the painted bumper faces.
static func draw_bund_plates(ci: Control, art_size: Vector2) -> void:
	if not plate_texture:
		plate_texture = load(PLATE_SOURCE) as Texture2D
	if not plate_texture:
		return
	var zoom := maxf(ci.size.x / art_size.x, ci.size.y / art_size.y)
	var origin := (ci.size - art_size * zoom) * 0.5
	var centers := [Vector2(449, 940), Vector2(747, 866)]
	var widths := [80.0, 63.0]
	for i in range(centers.size()):
		var dimensions := Vector2(widths[i], widths[i] * 0.29) * zoom
		var box := Rect2(-dimensions * 0.5, dimensions)
		ci.draw_set_transform(origin + centers[i] * zoom, -0.12)
		ci.draw_rect(box.grow(2.0 * zoom), Color("#282233"))
		ci.draw_texture_rect_region(plate_texture, box, PLATE_AREAS[i])
	ci.draw_set_transform(Vector2.ZERO)
