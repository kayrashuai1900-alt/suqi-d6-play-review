extends SceneTree

const Runner := preload("res://hongyuan/scene_runner.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func tap(runner, point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		runner._gui_input(event)

func tick(runner, seconds: float) -> void:
	for frame in ceili(seconds / 0.05): runner._process(0.05)

func run() -> void:
	var runner := Runner.new()
	runner.setup({"beats":[{"game":"care"},{"narrate":"A3-S1"},{"say":"A3-S2"},{"narrate":"A3-S3"},{"game":"pandas"}]}, {}, {})
	root.add_child(runner)
	runner.set_process(false)
	runner.begin()
	var care = runner.game
	check(care.visible_at(0) and not care.visible_at(2),"new worries appear in waves")
	var saved := runner.snapshot()
	saved.game.erase("cloud_rounds");saved.game.erase("cloud_arrivals")
	saved.game.cleared = [5,3]
	runner.restore(saved)
	check(care.group_count()==2,"older worry IDs keep progress")
	tick(runner,9.0)
	for index in [0,1,2,4]:
		check(care.visible_at(index),"remaining cloud is reachable")
		care.input("down",care.HEART_CENTER)
		care.input("up",care.center(index))
		if index in care.DOUBLE:
			var partial := runner.snapshot()
			runner.restore(partial)
			check(index in care.thinned and care.visible_at(index),"second cloud layer survives resume")
			care.input("down",care.HEART_CENTER);care.input("up",care.center(index))
	check(runner.bi==0 and care.phase=="care","six cleared worries do not end care")
	for wave in 1:
		tick(runner,3.5)
		for index in [0,1,5]:
			check(care.visible_at(index),"a new cloud returns after its cooldown")
			while care.visible_at(index):
				care.input("down",care.HEART_CENTER);care.input("up",care.center(index))
	var checkpoint := runner.snapshot()
	runner.begin(0); runner.restore(checkpoint); care = runner.game
	check(care.group_count()==9 and not care.visible_at(0) and care.visible_at(3) and care.phase=="care","nine worries resume without completing")
	while care.visible_at(3):
		care.input("down",care.HEART_CENTER);care.input("up",care.center(3))
	check(care.group_count()==10 and care.phase=="settle","tenth worry automatically ends care")
	tick(runner,1.7)
	check(runner.bi==1,"care goes straight to the conversation")
	for repeat in 16:
		tick(runner,0.3);tap(runner,Vector2(162,145))
	check(runner.bi==1,"previous gestures cannot advance the night conversation")
	for index in [1,2,3]:
		tick(runner,2.0);tap(runner,runner.LISTEN_RECT.get_center())
		check(runner.bi==index+1,"one listening action per line")
	check(runner._skip_label() == "跳过喂食", "panda shortcut says what it skips")
	runner.free()
	var archive: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://hongyuan/scene_migrations.json"))
	var versions: Array = archive._versions["call/night_call"]
	var previous: Array = versions.filter(func(version):return version.get("revision","")=="d6-before-story-pass")[0].beats
	var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://hongyuan/chapters/call.json"))
	var shot: Dictionary = chapter.steps[0].duplicate(true)
	shot.fullId = "call/night_call"
	shot.chapterId = "call"
	for index in previous.size():
		if previous[index].get("game")!="balance": continue
		var state := {"sceneSig":str(JSON.stringify(previous).hash()),"sceneBeat":index,"sceneSnapshot":{"beat":index,"mode":"game","game":{"tended":[0,1]}}}
		var migrated := preload("res://hongyuan/scene_migrations.gd").migrate(state,shot)
		check(migrated and shot.scene.beats[state.sceneBeat].get("narrate")=="A3-S1","retired pressure checkpoint continues at the night call")
	quit(failures)
