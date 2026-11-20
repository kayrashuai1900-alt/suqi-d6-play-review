extends Button
## Each screen observes its own batches; the loader owns their lifetime.
const Packs := preload("res://hongyuan/content_packs.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")

var loader: Node
var batches: Dictionary = {}
var retrying := false

func _ready() -> void:
	text = "接下来的回忆还没下载好 · 轻点重试"
	add_theme_font_override("font", FONT)
	add_theme_font_size_override("font_size", 14)
	custom_minimum_size.y = 48
	if custom_minimum_size.x <= 0: custom_minimum_size.x = 312
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#482e24", 0.96)
	panel.border_color = Color("#dda96e")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(5)
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	add_theme_stylebox_override("normal", panel)
	var active := panel.duplicate() as StyleBoxFlat
	active.bg_color = Color("#68432d")
	add_theme_stylebox_override("hover", active)
	add_theme_stylebox_override("pressed", active)
	loader = Packs.service()
	loader.progress.connect(_on_progress)
	loader.blocking_changed.connect(_on_blocking_changed)
	pressed.connect(_retry)
	hide()

func _exit_tree() -> void:
	if is_instance_valid(loader) and loader.progress.is_connected(_on_progress):
		loader.progress.disconnect(_on_progress)
	if is_instance_valid(loader) and loader.blocking_changed.is_connected(_on_blocking_changed):
		loader.blocking_changed.disconnect(_on_blocking_changed)

func offer(key: String, groups: Array[String]) -> void:
	if batches.has(key) or loader.is_ready(groups):
		return
	batches[key] = {"groups": groups, "ticket": Packs.prefetch(groups)}
	_refresh()

func clear_batches() -> void:
	batches.clear()
	retrying = false
	hide()

func _on_progress(detail: Dictionary) -> void:
	if retrying or detail.state == "ready" or detail.state == "error":
		_refresh()

func _on_blocking_changed(_active: bool) -> void:
	_refresh()

func _refresh() -> void:
	var failures := PackedStringArray()
	var labels := PackedStringArray()
	var remaining := false
	var received := 0
	var total := 0
	for key: String in batches.keys():
		var batch: Dictionary = batches[key]
		var ticket: Dictionary = batch.ticket
		if loader.is_ready(batch.groups):
			batches.erase(key)
			continue
		received += maxi(0, int(ticket.received))
		total += int(ticket.total)
		if not ticket.done:
			remaining = true
			continue
		if ticket.error.is_empty():
			batches.erase(key)
		else:
			var failed_group := str(ticket.get("failure", {}).get("group", ""))
			var label := Packs.group_title(failed_group) if not failed_group.is_empty() else Packs.groups_title(batch.groups)
			if not labels.has(label): labels.append(label)
			failures.append(label + "：" + str(ticket.error))
	tooltip_text = "\n".join(failures)
	if retrying and remaining:
		text = "正在补齐接下来的回忆 · %d%%\n当前回忆可以继续" % (floori(float(received)*100.0/total) if total > 0 else 0)
		disabled = true
		visible = not loader.is_blocking()
		return
	retrying = false
	disabled = false
	var title := "、".join(labels)
	if title.length() > 16: title = labels[0] + "等后续内容"
	text = title + "预下载未完成\n轻点重试 · 当前回忆可以继续"
	visible = not failures.is_empty() and not loader.is_blocking()

func _retry() -> void:
	retrying = true
	for batch: Dictionary in batches.values():
		var ticket: Dictionary = batch.ticket
		if ticket.done and not ticket.error.is_empty() and not loader.is_ready(batch.groups):
			batch.ticket = Packs.prefetch(batch.groups, true)
	_refresh()
