extends "res://scripts/modes/mode_base.gd"
## Counter-strafe: strafe with A/D, stop with the opposite key and shoot, for 60 seconds. Every shot
## is checked against CS2's rule that you're accurate at or below 34 % of the weapon's max speed.

const Sim = preload("res://scripts/movement_sim.gd")
const Dummy = preload("res://scripts/dummy.gd")
const Graph = preload("res://scripts/ui/strafe_graph.gd")
const SpeedMeter = preload("res://scripts/ui/speed_meter.gd")

const DUMMY_DIST := 12.0
const LANE_HALF_WIDTH := 5.0    # meters you can strafe to each side
const LOOKBACK := 0.6           # seconds before a shot in which we look for movement
const MOVING_FRACTION := 0.5    # a shot counts if you moved faster than this share of max speed

var weapon: Dictionary
var duration := 60.0
var sim: Sim
var dummy: Dummy
var graph: Graph
var meter: SpeedMeter
var shots: Array = []

var _held := {"w": false, "a": false, "s": false, "d": false}
var _last_shot := -10.0
var _done := false
var _run_start := -1.0
var _impacts: Array = []


func begin() -> void:
	weapon = Defs.WEAPONS[Settings.strafe_weapon]
	duration = Defs.RUN_SECONDS
	sim = Sim.new()
	sim.max_speed = weapon["speed"]
	var half := LANE_HALF_WIDTH / Defs.UNIT
	sim.bounds = Rect2(-half, -60.0, half * 2.0, 120.0)
	sim.reset(now())
	dummy = Dummy.new()
	dummy.team = randi() % 2
	dummy.position = Vector3(0.0, 0.0, -DUMMY_DIST)
	add_child(dummy)
	add_lane(LANE_HALF_WIDTH)
	meter = SpeedMeter.new()
	meter.sim = sim
	hud.add_widget(meter)
	graph = Graph.new()
	graph.sim = sim
	hud.add_widget(graph)
	hud.message("Strafea med A/D, tryck motsatt tangent för att stanna och skjut.", UI.DIM)
	_update_hud()


func go() -> void:
	_run_start = now()


func _process(_delta: float) -> void:
	if sim == null:
		return
	var t := now()
	sim.yaw = deg_to_rad(player.yaw)
	sim.advance(t)
	var state := sim.state_at(t)
	var p: Vector2 = state["pos"]
	player.position = Vector3(p.x * Defs.UNIT, 0.0, p.y * Defs.UNIT)
	dummy.face(player.eye_position())
	meter.speed = (state["vel"] as Vector2).length()
	graph.now_t = t
	meter.queue_redraw()
	graph.queue_redraw()
	if not _done and _run_start >= 0.0 and t - _run_start >= duration:
		_finish()
	_update_hud()


func key_event(key: String, pressed: bool, t: float) -> void:
	if sim == null or _held[key] == pressed:
		return
	_held[key] = pressed
	sim.set_key(t, key, pressed)


## Keys may have changed while the game was paused.
func on_resume() -> void:
	for code in Defs.MOVE_KEYS:
		key_event(Defs.MOVE_KEYS[code], Input.is_physical_key_pressed(code), now())


func shoot(origin: Vector3, dir: Vector3) -> void:
	var t := now()
	if _done or t - _last_shot < float(weapon["cycle"]):
		return
	_last_shot = t
	Sfx.play("shot")
	sim.advance(t)
	var vel: Vector2 = sim.state_at(t)["vel"]
	var info := _evaluate(t, vel)
	var shot_dir := _scatter(dir, vel.length())
	var hit := dummy.hit_test(origin, shot_dir)
	if hit["part"] == "":
		hit["dist"] = Defs.ray_box_exit(origin, shot_dir, Defs.ROOM_MIN, Defs.ROOM_MAX)
	else:
		Sfx.play("head" if hit["part"] == "head" else "hit")
		dummy.flash(hit["part"])
	info["part"] = hit["part"]
	_mark_impact(origin, shot_dir, hit)
	graph.show_shot(info)
	var text := Graph.describe(info)
	hud.flash(text["title"], text["color"])
	if info["counted"]:
		info["points"] = _points(info)
		shots.append(info)
		hud.message("")
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var shot_count := int(r.get("shots", 0))
	var early := int(r.get("early", 0))
	var early_text := str(early)
	if early > 0 and r.get("avg_early_ms") != null:
		early_text += " (snitt %s för tidigt)" % UI.ms(r.get("avg_early_ms"))
	var rows := [
		["Träffsäkra skott", "%d %% (%d av %d)" % [roundi(float(r.get("accuracy", 0.0)) * 100.0), int(r.get("accurate", 0)), shot_count]],
		["Skott efter stopp", UI.ms(r.get("avg_delay_ms"), true)],
		["Stopptid", UI.ms(r.get("avg_stop_ms"))],
		["För tidiga skott", early_text],
		["Skott i rörelse", str(int(r.get("moving", 0)))],
		["Counter-strafe", "%d %% av skotten" % roundi(float(r.get("counter_rate", 0.0)) * 100.0)],
		["Båda knapparna samtidigt", "%d gånger" % int(r.get("overlaps", 0))],
		["Huvudträffar", str(int(r.get("headshots", 0)))],
	]
	return {"headline": UI.num(r.get("score", 0)), "unit": "poäng", "rows": rows, "note": _tip(r)}


static func _tip(r: Dictionary) -> String:
	var shot_count := maxi(int(r.get("shots", 1)), 1)
	if int(r.get("overlaps", 0)) * 4 >= shot_count:
		return "Du håller ofta båda knapparna samtidigt. Då tar de ut varandra och bara friktionen bromsar. Släpp först, tryck sedan motsatt tangent."
	if float(r.get("counter_rate", 1.0)) < 0.6:
		return "Du släpper ofta bara knappen i stället för att kontra. Ett tryck på motsatt tangent stoppar dig ungefär tre gånger snabbare."
	if int(r.get("early", 0)) * 4 >= shot_count:
		return "Många skott går iväg innan du hunnit stanna. Ett counter-strafe tar runt 70 ms innan du är träffsäker, vänta in det."
	var delay: Variant = r.get("avg_delay_ms")
	if delay != null and float(delay) > 120.0:
		return "Du stannar bra men skjuter sent. Försök klicka direkt när du står still."
	return "Snyggt! Prova ett annat vapen eller fler skott."


## Classifies a shot: was it accurate, early, fired while moving, and how was the stop done?
func _evaluate(t: float, vel: Vector2) -> Dictionary:
	var thr := sim.threshold()
	var speed := vel.length()
	var info := {
		"t": t, "speed": speed, "accurate": speed <= thr, "counted": false,
		"counter": false, "overlap": 0.0, "gap": 0.0, "keys": ["d", "a"],
	}
	var peak := Vector2.ZERO
	for s: Vector3 in sim.samples:
		if s.x >= t - LOOKBACK and s.x <= t and Vector2(s.y, s.z).length() > peak.length():
			peak = Vector2(s.y, s.z)
	if peak.length() < sim.max_speed * MOVING_FRACTION:
		info["verdict"] = "standing"
		return info
	for hit_time: float in sim.wall_hits:
		if hit_time >= t - LOOKBACK and hit_time <= t:
			info["verdict"] = "wall"
			return info
	info["counted"] = true
	var keys := _keys_for(peak)
	info["keys"] = keys
	var move_key: String = keys[0]
	var counter_key: String = keys[1]
	var released := sim.last_change(move_key, false, t)
	var still_held := sim.held_at(move_key, t)
	var stop_start := -1.0
	if not still_held and released >= 0.0:
		var counter_press := -1.0
		if sim.held_at(counter_key, released):
			counter_press = sim.last_change(counter_key, true, released)
		else:
			counter_press = sim.first_press(counter_key, released, t)
		if counter_press >= 0.0:
			info["counter"] = true
			info["overlap"] = maxf(released - counter_press, 0.0)
			info["gap"] = maxf(counter_press - released, 0.0)
			stop_start = minf(released, counter_press)
		else:
			stop_start = released
	if info["accurate"]:
		var became := sim.became_accurate(t, thr, speed)
		info["verdict"] = "accurate"
		if became >= 0.0:
			info["t_acc"] = became
			info["delay"] = t - became
			if stop_start >= 0.0 and became >= stop_start:
				info["stop"] = became - stop_start
	elif still_held:
		info["verdict"] = "moving"
	else:
		var ahead := sim.until_accurate(t)
		if ahead["seconds"] > 0.0 and ahead["falling"]:
			info["verdict"] = "early"
			info["early"] = ahead["seconds"]
			info["t_acc"] = t + ahead["seconds"]
		elif vel.dot(peak) < 0.0:
			info["verdict"] = "overcounter"
		else:
			info["verdict"] = "moving"
	return info


## The key that caused the movement and its opposite, judged from the direction of travel.
func _keys_for(v: Vector2) -> Array:
	var forward := Vector2(-sin(sim.yaw), -cos(sim.yaw))
	var right := Vector2(cos(sim.yaw), -sin(sim.yaw))
	if absf(v.dot(right)) >= absf(v.dot(forward)):
		return ["d", "a"] if v.dot(right) > 0.0 else ["a", "d"]
	return ["w", "s"] if v.dot(forward) > 0.0 else ["s", "w"]


func _points(info: Dictionary) -> int:
	if not info["accurate"]:
		return 0
	var delay_ms: float = float(info.get("delay", 0.0)) * 1000.0
	var points := clampf(100.0 - maxf(delay_ms - 30.0, 0.0) / 2.0, 20.0, 100.0)
	if info.get("part", "") == "head":
		points += 20.0
	return int(points)


## Spreads the shot like CS: no movement inaccuracy at or below the threshold, then more the faster
## you go. The curve above the threshold is an approximation.
func _scatter(dir: Vector3, speed: float) -> Vector3:
	var thr := sim.threshold()
	var inaccuracy := Defs.STAND_INACC
	if speed > thr:
		var x := clampf(remap(speed, thr, sim.max_speed * 0.95, 0.0, 1.0), 0.0, 1.0)
		inaccuracy += float(weapon["move_inacc"]) * sqrt(x)
	var basis: Basis = player.camera.global_transform.basis
	var angle := randf() * TAU
	var r := randf() * inaccuracy
	return (dir + basis.x * cos(angle) * r + basis.y * sin(angle) * r).normalized()


func _mark_impact(origin: Vector3, dir: Vector3, hit: Dictionary) -> void:
	var dist: float = hit["dist"]
	var mesh := SphereMesh.new()
	mesh.radius = clampf(dist * 0.003, 0.025, 0.1)
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match hit["part"]:
		"head":
			mat.albedo_color = UI.GOOD
		"body":
			mat.albedo_color = UI.ACCENT
		_:
			mat.albedo_color = Color(0.12, 0.12, 0.14) if Settings.room_theme == 0 else Color(0.85, 0.87, 0.92)
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	mark.material_override = mat
	mark.position = origin + dir * dist
	add_child(mark)
	_impacts.append(mark)
	if _impacts.size() > 12:
		_impacts.pop_front().queue_free()


func _finish() -> void:
	_done = true
	var accurate := shots.filter(func(s: Dictionary) -> bool: return s["accurate"])
	var early := shots.filter(func(s: Dictionary) -> bool: return s["verdict"] == "early")
	var stops := shots.filter(func(s: Dictionary) -> bool: return s.has("stop"))
	var delays := accurate.filter(func(s: Dictionary) -> bool: return s.has("delay"))
	var score := 0
	for s: Dictionary in shots:
		score += int(s["points"])
	Sfx.play("done")
	finished.emit({
		"variant": Defs.variant("strafe", Settings),
		"score": score,
		"shots": shots.size(),
		"accurate": accurate.size(),
		"accuracy": float(accurate.size()) / maxi(shots.size(), 1),
		"avg_delay_ms": to_ms(average(delays, "delay")),
		"early": early.size(),
		"avg_early_ms": to_ms(average(early, "early")),
		"moving": shots.filter(func(s: Dictionary) -> bool: return s["verdict"] == "moving" or s["verdict"] == "overcounter").size(),
		"avg_stop_ms": to_ms(average(stops, "stop")),
		"counter_rate": float(shots.filter(func(s: Dictionary) -> bool: return s["counter"]).size()) / maxi(shots.size(), 1),
		"overlaps": shots.filter(func(s: Dictionary) -> bool: return s["overlap"] > 0.015).size(),
		"headshots": shots.filter(func(s: Dictionary) -> bool: return s.get("part", "") == "head").size(),
	})


func _update_hud() -> void:
	var accurate := shots.filter(func(s: Dictionary) -> bool: return s["accurate"]).size()
	var pct := 0 if shots.is_empty() else roundi(100.0 * accurate / shots.size())
	var score := 0
	for s: Dictionary in shots:
		score += int(s["points"])
	var left := duration
	if _done:
		left = 0.0
	elif _run_start >= 0.0:
		left = maxf(_run_start + duration - now(), 0.0)
	var title := "COUNTER-STRAFE · %s" % weapon["name"]
	var stats := "%s s kvar · träffsäkra %d %% · %s p" % [UI.dec(left, 1), pct, UI.num(score)]
	hud.set_texts(title, "Skott %d" % shots.size(), stats)
	hud.set_progress(1.0 - left / duration)
