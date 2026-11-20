extends Node
## A single host for the estate and village, sharing the invitation identity.
const Checkpoint := preload("res://hongyuan/checkpoint.gd")
const Packs := preload("res://hongyuan/content_packs.gd")
const ContentOverlay := preload("res://hongyuan/ui/content_overlay.gd")
const PrefetchNotice := preload("res://hongyuan/ui/prefetch_notice.gd")
const FONT := preload("res://hongyuan/fonts/dialogue_font.tres")
var destination := ""
var content: Node
var game: Node
var profile: Dictionary = {}
var state: Dictionary = {}
var loading: Control
var prefetch_notice := PrefetchNotice.new()
var navigation: HBoxContainer
var busy := false
var save_elapsed := 0.0
var requested_destination := ""

func _ready() -> void:
    state = Checkpoint.read()
    var guest: Dictionary = state.get("guest", {})
    profile = state.get("worldProfile", {}).duplicate(true)
    if profile.is_empty():
        profile = {
            "id": "hongyuan_" + str(state.get("runId", "guest")),
            "nick": str(guest.get("name", "来做客的你")),
            "avatar": clampi(int(str(guest.get("look", "01"))) - 1, 0, 7)
        }
    profile["nick"] = str(guest.get("name", profile.get("nick", "来做客的你")))
    profile["avatar"] = clampi(int(str(guest.get("look", int(profile.get("avatar", 0)) + 1))) - 1, 0, 7)
    get_tree().root.set_meta("player_profile", profile.duplicate(true))
    var layer := CanvasLayer.new()
    layer.layer = 100
    add_child(layer)
    # Full-screen village photo pages (layer 45) keep the picture unobstructed.
    var notice_layer := CanvasLayer.new()
    notice_layer.layer = 40
    add_child(notice_layer)
    notice_layer.add_child(prefetch_notice)
    loading = ContentOverlay.new()
    layer.add_child(loading)
    loading.desk_button.text = "留在这里"
    loading.retry.connect(func(): travel(requested_destination))
    loading.return_to_desk.connect(_cancel_travel)
    # 放在顶栏（山庄金币条/村子来信卡）下面、宴会厅提示面板上面。
    navigation = HBoxContainer.new()
    navigation.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    navigation.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    navigation.offset_left = -300
    navigation.offset_right = -8
    navigation.offset_top = 96
    navigation.alignment = BoxContainer.ALIGNMENT_END
    navigation.add_theme_constant_override("separation", 6)
    layer.add_child(navigation)
    await travel(str(state.get("worldRoute", "wedding")))

func _cancel_travel() -> void:
    if is_instance_valid(content):
        loading.hide()
        navigation.show()
    else:
        get_tree().change_scene_to_file.call_deferred("res://hongyuan/boot.tscn")

func _process(dt: float) -> void:
    if busy:
        return
    save_elapsed += dt
    if save_elapsed >= 5.0:
        save_elapsed = 0.0
        save_world()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_PAUSED and not busy:
        save_world()

func save_world() -> void:
    if not is_instance_valid(game) or destination == "":
        return
    if destination == "village":
        game.village_ui.checkpoint()
        game.save_journal()
    else:
        var at: Dictionary = game.location()
        if not at.is_empty():
            state["weddingLocation"] = at
    state["worldProfile"] = profile.duplicate(true)
    state["worldRoute"] = destination
    state["revision"] = int(state.get("revision", 0)) + 1
    if not Checkpoint.write(state):
        state["revision"] = int(state["revision"]) - 1
        push_warning("World progress could not be saved.")

func travel(where: String) -> void:
    if busy:
        return
    busy = true
    requested_destination = where
    save_world()
    navigation.hide()
    var title := "正在前往村子…" if where == "village" else "正在前往罗曼山庄…"
    loading.desk_button.text = "留在这里" if is_instance_valid(content) else "返回开屏"
    if not await loading.prepare(title, Packs.route_groups(where)):
        busy = false
        return
    loading.waiting(title)
    loading.progress_bar.hide()
    loading.detail.text = "正在准备画面…"
    if is_instance_valid(content):
        content.queue_free()
        await get_tree().process_frame
    destination = "village" if where == "village" else "wedding"
    var window := get_window()
    window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    window.content_scale_size = Vector2i(540, 960)
    if destination == "village":
        game = load("res://ayu_home/v4/home.tscn").instantiate()
        game.town_profile = profile.duplicate(true)
        content = game
        add_child(content)
        while not game.bootstrapped:
            await get_tree().process_frame
        # 从爱情篇进村会跳过村子欢迎页，音乐要在这里启动（点按钮进村，已算一次手势）
        load("res://ayu_home/v4/core/playtest_music.gd").ensure(get_tree()).unlock_from_gesture()
    else:
        game = load("res://hongyuan/wedding.gd").new()
        game.guest_profile = profile.duplicate(true)
        game.resume_location = state.get("weddingLocation", {}).duplicate(true)
        content = game
        add_child(content)
        await game.venue_ready
    for child in navigation.get_children():
        child.queue_free()
    add_button("去婚礼现场" if destination == "village" else "去村子入住",
        func(): travel("wedding" if destination == "village" else "village"))
    if destination == "wedding":
        add_button("直接入席", func(): game.enter_banquet())
    place_navigation()
    navigation.show()
    loading.hide()
    busy = false
    save_world()
    print("WORLD_READY route=", destination, " nick=", profile.nick, " avatar=", profile.avatar)
    prefetch_notice.clear_batches()
    if destination == "village" and Packs.service().has_group("village-home"):
        prefetch_notice.offer("village-later", ["village-home", "village-street", "village-panels", "village-rooms", "village-activities"])
    elif destination == "wedding" and Packs.service().has_group("village-entry"):
        prefetch_notice.offer("village-entry", Packs.route_groups("village"))

# 微信右上角的胶囊按钮会盖住「去婚礼现场」，按刘海安全区往下让出胶囊的高度
func place_navigation() -> void:
    var top := 82.0
    var safe := DisplayServer.get_display_safe_area()
    var win := DisplayServer.window_get_size()
    if win.y > 0 and safe.position.y > 0:
        top = maxf(top, safe.position.y * get_viewport().get_visible_rect().size.y / win.y + 62.0)
    navigation.offset_top = top
    prefetch_notice.position = Vector2(8, top + 42)

func add_button(label: String, action: Callable) -> void:
    var button := Button.new()
    button.text = label
    button.custom_minimum_size = Vector2(0, 38)
    button.add_theme_font_override("font", FONT)
    button.add_theme_font_size_override("font_size", 18)
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#473329", 0.92)
    style.border_color = Color("#be974d")
    style.set_border_width_all(2)
    style.content_margin_left = 10
    style.content_margin_right = 10
    style.content_margin_top = 4
    style.content_margin_bottom = 4
    button.add_theme_stylebox_override("normal", style)
    var hover := style.duplicate()
    hover.bg_color = Color("#694a35")
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", hover)
    button.pressed.connect(action)
    navigation.add_child(button)
