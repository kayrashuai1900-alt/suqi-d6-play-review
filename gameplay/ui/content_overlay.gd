extends Control
signal retry
signal return_to_desk
const Packs := preload("res://hongyuan/content_packs.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")
var heading: Label
var detail: Label
var progress_bar: ProgressBar
var retry_button: Button
var desk_button: Button
var request_id := -1
var chapter_name := ""
var requested_groups: Array[String] = []
var last_percent := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 90 # A loading/retry message must remain above a scene's black wipe.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visibility_changed.connect(_sync_blocking)
	_sync_blocking()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color("#2b211d")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.custom_minimum_size.x = minf(390.0, maxf(0.0, size.x - 48.0))
	resized.connect(func(): box.custom_minimum_size.x = minf(390.0, maxf(0.0, size.x - 48.0)))
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	heading = _label(box, 27)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail = _label(box, 18)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 16)
	progress_bar.show_percentage = false
	box.add_child(progress_bar)
	retry_button = _button(box, "重试", func(): retry.emit())
	desk_button = _button(box, "回到书桌", func(): return_to_desk.emit())
	retry_button.hide()
	desk_button.hide()

func _sync_blocking() -> void:
	Packs.service().set_blocking(get_instance_id(), is_visible_in_tree())

func _exit_tree() -> void:
	if is_instance_valid(Packs.runtime):
		Packs.runtime.set_blocking(get_instance_id(), false)

func _label(box: Control, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#fff1d5"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return label

func _button(box: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 66
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	box.add_child(button)
	return button

func prepare(chapter_title: String, groups: Array[String]) -> bool:
	var loader := Packs.service()
	requested_groups = groups.duplicate()
	chapter_name = chapter_title
	if loader.is_ready(groups):
		return true
	if not loader.progress.is_connected(update_progress):
		loader.progress.connect(update_progress)
	var ticket: Dictionary = loader.request_groups(groups)
	request_id = int(ticket.id)
	waiting(chapter_title)
	update_progress({"request_id":request_id,"received":ticket.received,"total":ticket.total,"state":"download","group":""})
	var ok: bool = await loader.wait_request(ticket)
	if not ok:
		failed(str(ticket.error), ticket.get("failure", {}))
	return ok

func waiting(chapter_title: String) -> void:
	chapter_name = chapter_title
	heading.text = "正在准备 · " + chapter_title
	last_percent = 0
	detail.text = "正在查找已保存的画面…"
	progress_bar.value = 0
	progress_bar.show()
	retry_button.hide()
	desk_button.hide()
	show()

func update_progress(value: Dictionary) -> void:
	if int(value.get("request_id", -2)) != request_id:
		return
	var received := int(value.get("received", 0))
	var total := int(value.get("total", 0))
	if total <= 0:
		detail.text = "正在准备画面…"
		return
	var percent := clampf(float(received) * 100.0 / total, 0.0, 100.0)
	progress_bar.value = percent
	last_percent = floori(percent)
	var group := str(value.get("group", ""))
	var label := Packs.group_title(group) if not group.is_empty() else chapter_name
	var amount := "%.1f / %.1f MB" % [float(received)/1000000.0, float(total)/1000000.0]
	detail.text = "画面已下载，正在打开…" if percent >= 100.0 else ("正在下载%s\n%s（%d%%）" % [label, amount, last_percent])

func failed(reason: String, failure: Dictionary = {}) -> void:
	var group := str(failure.get("group", ""))
	var label := Packs.group_title(group) if not group.is_empty() else Packs.groups_title(requested_groups)
	if label.is_empty(): label = chapter_name
	heading.text = label + "还没准备好"
	detail.text = reason + "\n已完成 %d%%，可继续下载。\n已完成的画面不用重下。" % last_percent
	progress_bar.show()
	retry_button.text = "继续加载"
	retry_button.show()
	desk_button.show()
	retry_button.grab_focus()
