extends "res://hongyuan/tests/full_flow_review.gd"

var landmarks := ["shizuoka/pier_12_go_settled", "hainan/wanning_11_say_settled", "hongkong/hk_04_game_list_settled", "hongkong/hk_07_say_settled", "hongkong/hk_19_say_readable", "hongkong/hk_33_game_ready_settled", "call/night_call_29_game_care_0", "call/night_call_29_game_care_3"]

func capture(tag: String) -> void:
	if tag in landmarks: await super.capture(tag)

func game_action(runner, activity, kind: String) -> void:
	if kind=="care" and activity.group_count()==0 and activity.t<5.4:
		return
	super.game_action(runner,activity,kind)

func run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	view = SubViewport.new()
	view.size = Vector2i(390,844)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	p = Harness.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(p)
	await process_frame
	for step in p.playlist:
		if step.type == "terminal": break
		var deadline := Time.get_ticks_msec()+20000
		while p.shot.get("fullId","") != step.fullId or p.fading or p.loading_content:
			await process_frame
			if Time.get_ticks_msec() > deadline:
				problem("Expected "+step.fullId+" after "+str(p.shot.get("fullId")))
				quit(1)
				return
		print("STORY ",step.fullId)
		await run_scene(step.fullId)
		if failures > 0: break
	if not report.any(func(row):return row.kind=="exits"): problem("Invitation destinations not reached")
	print("CONTINUOUS failures=",failures," codas=",p.interludes_shown.keys())
	p.free()
	quit(failures)
