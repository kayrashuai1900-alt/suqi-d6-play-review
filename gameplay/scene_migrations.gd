extends RefCounted
## Match the complete archived script signature before interpreting a beat index.
## Unknown signatures are deliberately left to Player's safe scene restart.
static func _archived(baseline: Dictionary, full_id: String, signature: String) -> Array:
	var original: Array = baseline.get(full_id, [])
	if signature == "": return original # legacy pre-signature baseline only
	if not original.is_empty() and signature == str(JSON.stringify(original).hash()): return original
	for version: Dictionary in baseline.get("_versions", {}).get(full_id, []):
		var beats: Array = version.get("beats", [])
		if signature == str(JSON.stringify(beats).hash()): return beats
	return []

static func _key(beat: Dictionary) -> String:
	for name in ["game", "go", "material", "card", "button"]:
		if beat.has(name): return name+":"+str(beat[name])
	for name in ["say", "narrate"]:
		if beat.has(name): return "copy:"+str(beat[name])
	return ""

static func _find_key(beats: Array, key: String, occurrence := 0) -> int:
	for i in range(beats.size()):
		if _key(beats[i]) == key:
			if occurrence == 0: return i
			occurrence -= 1
	return -1

static func _same_beat(old: Array, index: int, current: Array) -> int:
	var key := _key(old[index])
	if key != "":
		var occurrence := 0
		for i in range(index):
			if _key(old[i]) == key: occurrence += 1
		var matched := _find_key(current,key,occurrence)
		if matched < 0 and key == "game:balance":
			return _find_key(current,"copy:A3-S1")
		if matched < 0 and key in ["copy:A3-2a", "copy:A3-2b", "copy:A3-2f"]:
			matched = _find_key(current, "copy:A3-CALL-AYU-REFLECT")
		if matched < 0 and key.begins_with("copy:"):
			for i in range(current.size()):
				if key.trim_prefix("copy:") in current[i].get("memory", []): return i
			# A setup beat can resolve through one of these retired captions.
			if key in ["copy:A4-3a", "copy:A4-3b"]:
				return _find_key(current, "game:registration")
		return matched
	# Setup-only beats are not resumable interactions. Follow the next semantic
	# beat so repeated hide/show/background dictionaries cannot map backwards.
	for i in range(index+1,old.size()):
		if _key(old[i]) != "": return _same_beat(old,i,current)
	return -1

static func _new_entry(old: Array,index: int,current: Array,new_index: int) -> int:
	# An old awarded token remains awarded, but newly required play is not skipped.
	var care := _find_key(current,"game:care")
	if care >= 0 and _find_key(old,"game:care") < 0 and new_index > care:
		# Include the new instruction card and its scene setup before care.
		return maxi(0,care-2)
	var registry := _find_key(current,"game:registration")
	if registry >= 0 and _find_key(old,"game:registration") < 0:
		if _key(old[index]) in ["copy:A4-3a","copy:A4-3b","material:stamp"]:
			return registry
	# The old HK photo is the first photo, never one of the added Disney/campus
	# photos. Saves after it replay the newly added travel sequence before reward.
	var first_photo := _find_key(current,"game:photo")
	var second_photo := _find_key(current,"game:photo",1)
	if second_photo >= 0 and _find_key(old,"game:photo",1) < 0 and new_index > first_photo:
		return first_photo+1
	# Already underway later games keep their position; a save at an old walkway
	# starts at its newly required approach, rather than teleporting through it.
	if _key(old[index]) == "go:seat" and _find_key(old,"go:gangway_foot") < 0:
		var approach := _find_key(current,"go:gangway_foot")
		if approach >= 0: return approach
	if _key(old[index]) == "go:exit" and _find_key(old,"go:security") < 0:
		var security := _find_key(current,"go:security")
		if security >= 0: return security
	return new_index

# Visual cues, NPC artwork and pause lengths may change without moving a
# checkpoint. Compare every other field, including routes and interaction IDs.
static func _timeline_beat(beat: Dictionary) -> Dictionary:
	var result := beat.duplicate(true)
	for field in ["hint", "caption", "chapterCaption", "captionLow"]:
		result.erase(field)
	if result.has("wait"):
		result.wait = true
	if result.has("goal"):
		result.goal = true
	for walker: Dictionary in result.get("walkers", []):
		walker.erase("npc")
	return result

static func _same_timeline(previous: Array, current: Array) -> bool:
	if previous.size() != current.size(): return false
	for i in range(previous.size()):
		if previous[i] != current[i] and _timeline_beat(previous[i]) != _timeline_beat(current[i]):
			return false
	return true

# Spoken exchanges now use stable copy IDs, not the old eight-line offsets.
# In particular, a checkpoint inside the former wechat recollection must resume
# that same sentence, rather than accidentally becoming the birthday reveal.
static func _migrate_call(snapshot: Dictionary, previous: Dictionary, current: Dictionary) -> void:
	var game: Dictionary = snapshot.game
	var phase := str(game.get("phase", "ring"))
	if phase in ["hangup", "done"]:
		game.li = current.lines.size()
		return
	var id := ""
	if phase == "wechat":
		var remembered: Array = previous.get("wechat", [])
		var index := int(game.get("wi", 0))
		if index >= 0 and index < remembered.size(): id = str(remembered[index].get("say", ""))
	else:
		var index := int(game.get("li", 0))
		if index >= 0 and index < previous.lines.size(): id = str(previous.lines[index].get("say", ""))
	id = str({"A3-2a":"A3-W1", "A3-2b":"A3-W5", "A3-2f":"A3-2g"}.get(id, id))
	var mapped := 0
	var birthday := 0
	for i in range(current.lines.size()):
		if str(current.lines[i].get("say", "")) == id: mapped = i
		if str(current.lines[i].get("say", "")) == "A3-2d": birthday = i
	game.li = mapped
	game.phase = phase if phase in ["ring", "birthday"] else ("reply" if mapped > birthday else "talk")
	game.wechat_done = true
	game.holding = false
	game.t = 0.0
	game.reveal = 0.0

static func migrate(state: Dictionary, shot: Dictionary) -> bool:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://hongyuan/scene_migrations.json"))
	var signature := str(state.get("sceneSig", ""))
	var current: Array = shot.scene.get("beats", [])
	# Text and backdrop edits preserve the previous exact beat and game snapshot.
	var copy_updates: Dictionary = baseline.get("_copy_only", {}).get(shot.fullId, {})
	if copy_updates.has(signature) and copy_updates[signature] == str(JSON.stringify(current).hash()):
		return true
	var old := _archived(baseline, str(shot.fullId), signature)
	var index := int(state.get("sceneBeat", 0))
	if old.is_empty() or index < 0 or index >= old.size(): return false
	if _same_timeline(old, current): return true
	var snapshot: Dictionary = state.get("sceneSnapshot", {}).duplicate(true)
	var beat: Dictionary = old[index]
	var new_index := _same_beat(old,index,current)
	# The retired call button only opened Moments. Resume the post itself, not the whole scene.
	if new_index < 0 and str(shot.fullId) == "call/night_call" and _key(beat) == "button:A3-S14":
		new_index = _find_key(current, "game:moments")
	if new_index >= 0: new_index = _new_entry(old,index,current,new_index)
	if str(shot.chapterId) == "finale":
		var guest: Dictionary = state.get("guest", snapshot.get("result", {}))
		var game: Dictionary = snapshot.get("game", {})
		var name := str(game.get("name", guest.get("name", "")))
		var keeps_letter_flow: bool = old.size() == 6 and old[3].has("choice") and beat.get("game", "") == "finale"
		if keeps_letter_flow and new_index >= 0 and not game.is_empty():
			# This release only removes what follows the letter. Keep its current phase.
			snapshot.game = game
		elif name.length() >= 2:
			new_index = _find_key(current,"game:finale")
			var old_phase := str(game.get("phase", ""))
			var phase := old_phase if old_phase in ["name", "seal"] else "write"
			if old_phase in ["stamped", "done"] or not guest.is_empty(): phase = "ready_send"
			var look := int(game.get("look", int(str(guest.get("look", "01"))) - 1))
			game = {"phase": phase, "name": name, "look": look, "typed": 0.0, "hold": 0.0, "t": 0.0}
			snapshot = {"mode": "game", "game": game, "result": guest}
	elif new_index >= 0:
		var target: Dictionary = current[new_index]
		if _key(beat) == "" or _key(beat) != _key(target):
			# Keep identity/result, but never reuse another activity's mode/game state.
			snapshot = {"result": snapshot.get("result", {}).duplicate(true)}
		elif _key(beat) == "game:registration" and beat.has("memory") and target.has("memories") and snapshot.has("game"):
			var registry: Dictionary = snapshot.game
			match str(registry.get("phase", "")):
				"handover":
					registry.merge({"phase":"memory", "li":0, "t":0.0}, true)
				"photo", "flash":
					registry.merge({"phase":"photo", "li":3, "t":0.0}, true)
				"memory":
					registry.merge({"phase":"memory", "li":3, "t":0.0}, true)
		elif beat.get("game", "") == "call" and target.get("game", "") == "call" and snapshot.has("game"):
			_migrate_call(snapshot, beat, target)
		elif beat.has("game") and beat.has("lines") and target.has("lines") and snapshot.has("game"):
			var line_index := int(snapshot.game.get("li",0))
			if line_index >= 0 and line_index < beat.lines.size():
				var copy_id := str(beat.lines[line_index].get("say",""))
				var mapped_line := -1
				for i in range(target.lines.size()):
					if str(target.lines[i].get("say","")) == copy_id: mapped_line=i;break
				if mapped_line >= 0: snapshot.game.li=mapped_line
				else: snapshot={"result":snapshot.get("result",{}).duplicate(true)}
	if new_index < 0: return false
	if str(shot.fullId) == "hainan/wanning" and snapshot.get("pose") == "back":
		var shore := _find_key(current, "go:shore")
		var fireworks := _find_key(current, "game:fireworks")
		if shore >= 0 and new_index > shore and new_index <= fireworks:
			# Reapply the directed arrival, including for a save already mid-dialogue.
			for setup: Dictionary in current.slice(0, shore):
				for hotspot: Dictionary in setup.get("hotspots", []):
					if hotspot.get("id") == "shore" and hotspot.has("companionSnap"):
						snapshot.feet = hotspot.snap
						snapshot.target = hotspot.snap
						snapshot.comp_pos = hotspot.companionSnap
						snapshot.facing = hotspot.face
						snapshot.trail = []
	state.sceneBeat = new_index
	snapshot.beat = new_index
	state.sceneSnapshot = snapshot
	return true
