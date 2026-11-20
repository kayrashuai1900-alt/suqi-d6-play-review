extends RefCounted
## Ambient walkers: pause at each end, keep a continuous foot position, and
## give the player room. Coordinates are feet in the scene's world plane.
var states: Array[Dictionary] = []
var walkers: Array = []
func setup(config: Array) -> void:
	walkers = []
	for authored: Dictionary in config:
		walkers.append(_route_for_sprite(authored))
	states.clear()
	for w: Dictionary in walkers:
		var a := _point(w.a)
		var b := _point(w.b)
		var phase := fposmod(float(w.get("phase", 0)), 1.0)
		var returning := phase >= 0.5
		var fraction := (1.0 - phase) * 2.0 if returning else phase * 2.0
		states.append({"pos":a.lerp(b,fraction),"returning":returning,"pause":float(w.get("startDelay",0.0)),"distance":0.0,"heading":(a-b if returning else b-a).normalized(),"walking":false})
func advance(dt: float, player: Vector2, player_visible: bool) -> void:
	for i in range(states.size()):
		var state: Dictionary = states[i]
		var w: Dictionary = walkers[i]
		state.walking = false
		if state.get("stopped", false) or float(w.get("speed", 30.0)) == 0.0:
			continue
		if state.pause > 0:
			state.pause = maxf(0, state.pause - dt)
			continue
		var target := _point(w.a if state.returning else w.b)
		var from: Vector2 = state.pos
		if from.distance_to(target) < 0.3:
			if w.get("once", false):
				state.stopped = true
				continue
			state.returning = not state.returning
			state.pause = float(w.get("pause", 1.2))
			continue
		var next := from.move_toward(target, float(w.get("speed", 30)) * dt)
		var personal_space := float(w.get("radius", 12))
		if player_visible and bool(w.get("avoidPlayer", true)) and next.distance_to(player) < personal_space and next.distance_to(player) < from.distance_to(player):
			continue
		# Scene authors give nearby walkers distinct lanes. This final guard
		# prevents rear-end overlap without teleporting a pedestrian sideways.
		var blocked := false
		for j in range(states.size()):
			if i == j: continue
			var other: Dictionary = states[j]
			if next.distance_to(other.pos) < personal_space and next.distance_to(other.pos) < from.distance_to(other.pos) and state.heading.dot(other.heading) > 0.5:
				blocked = true
				break
		if blocked: continue
		state.pos = next
		state.walking = true
		state.heading = (target - from).normalized()
		state.distance += from.distance_to(next)
func restore_once(elapsed: float) -> void:
	for i in range(walkers.size()):
		var w: Dictionary = walkers[i]
		if not w.get("once", false): continue
		var from := _point(w.a)
		var target := _point(w.b)
		var delay := float(w.get("startDelay", 0.0))
		var moving_elapsed := maxf(0.0, elapsed - delay)
		var position := from.move_toward(target, moving_elapsed * float(w.get("speed", 30.0)))
		states[i].pos = position
		states[i].pause = maxf(0.0, delay - elapsed)
		states[i].distance = from.distance_to(position)
		states[i].heading = (target - from).normalized()
		states[i].walking = false
		states[i].stopped = position.is_equal_approx(target)

# Strip art faces left or right only. Keep these routes across the floor.
# Four-direction guest sheets retain their authored routes into scene depth.
static func _route_for_sprite(authored: Dictionary) -> Dictionary:
	if not authored.has("npc") and not authored.has("sheet"):
		return authored
	var a := _point(authored.a)
	var b := _point(authored.b)
	var span := b - a
	if absf(span.y) <= absf(span.x) * 0.35:
		return authored
	var route := authored.duplicate()
	if absf(span.x) < 12.0:
		route.b = route.a
		route.speed = 0.0
		return route
	var mid_y := (a.y + b.y) * 0.5
	var half_depth := signf(span.y) * absf(span.x) * 0.16
	route.a = [a.x, mid_y - half_depth]
	route.b = [b.x, mid_y + half_depth]
	return route

func at(index: int) -> Dictionary:
	return states[index]
static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))
