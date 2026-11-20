extends Control
## Hold the outgoing frame while a scene mounts, then dissolve into the new one.
## On renderers without a frame readback, briefly tint the artwork in place.
const SHADE := Color(0.26, 0.16, 0.14, 0.24)
var frame: Texture2D
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func capture(ci: CanvasItem) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var image := ci.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

static func paint(ci: CanvasItem, rect: Rect2, amount: float, outgoing: Texture2D = null) -> void:
	if amount <= 0.0:
		return
	if outgoing:
		ci.draw_texture_rect(outgoing, rect, false, Color(1, 1, 1, amount))
	else:
		ci.draw_rect(rect, Color(SHADE, SHADE.a * amount))

func _draw() -> void:
	paint(self, Rect2(Vector2.ZERO, size), progress, frame)

func hold_frame() -> void:
	frame = capture(self)
	progress = 1.0

func cover(seconds := 0.22) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	hold_frame()
	# Leave the picture visible while the following Control enters the tree.
	await get_tree().create_timer(minf(seconds, 0.08), false).timeout

func reveal(seconds := 0.28) -> void:
	var tween := create_tween()
	tween.tween_property(self, "progress", 0.0, seconds).from(1.0).set_trans(Tween.TRANS_SINE)
	await tween.finished
	frame = null
