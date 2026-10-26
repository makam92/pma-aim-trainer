extends "res://scripts/modes/mode_base.gd"
## Strafe Aim: hit targets while you strafe with A/D and CS2's movement. A shot only counts when
## you're moving faster than half your max speed, so standing still and the turns in an ADAD don't
## count. Bullets go exactly where you aim (no movement inaccuracy here): it's your aim on the move
## that's trained. Three targets at a time, for 60 seconds.

const Sim = preload("res://scripts/movement_sim.gd")
const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")
const SpeedMeter = preload("res://scripts/ui/speed_meter.gd")

const LANE_HALF_WIDTH := 5.0       # meters you can strafe to each side
const LANE_DEPTH := 80.0           # units you can move forwards or back, when strafing at an angle
const MOVING_FRACTION := 0.5       # a shot counts at or above this share of your max speed
const ACTIVE := 3                  # targets up at a time
const FIELD_YAW := 22.0            # targets show up to this far to each side of straight ahead,
const PITCH := Vector2(-4.0, 7.0)  # this far below and above eye level,
const MIN_GAP := 5.0               # and at least this many degrees from each other

var duration := 60.0
var max_speed := 215.0
var hits := 0
var misses := 0
var still_shots := 0
var times: Array = []              # seconds between consecutive hits
var speeds: Array = []             # your speed at each hit, as a share of max speed
var sim: Sim
var meter: SpeedMeter

var _targets: Array = []
var _held := {"w": false, "a": false, "s": false, "d": false}
var _run_start := -1.0
var _last_hit := 0.0
var _done := false


func begin() -> void:
	duration = Defs.RUN_SECONDS
	max_speed = Defs.TRACK_SPEEDS[Settings.saim_speed]["speed"]
	sim = Sim.new()
	sim.max_speed = max_speed
	var half := LANE_HALF_WIDTH / Defs.UNIT
	sim.bounds = Rect2(-half, -LANE_DEPTH, half * 2.0, LANE_DEPTH * 2.0)
	sim.reset(now())
	add_lane(LANE_HALF_WIDTH)
	meter = SpeedMeter.new()
	meter.sim = sim
	meter.min_speed = max_speed * MOVING_FRACTION
	hud.add_widget(meter)
	for i in ACTIVE:
		_spawn()
	hud.message("Strafea med A/D och skjut målen medan du rör dig.", UI.DIM)
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
	meter.speed = (state["vel"] as Vector2).length()
	meter.queue_redraw()
	if not _done and _run_start >= 0.0 and t - _run_start >= duration:
		_finish()
	_update_hud()


func key_event(key: String, pressed: bool, t: float) -> void:
	if sim == null or _held[key] == pressed:
		return
	_held[key] = pressed
	sim.set_key(t, key, pressed)
	if pressed:
		hud.message("")


## Keys may have changed while the game was paused.
func on_resume() -> void:
	for code in Defs.MOVE_KEYS:
		key_event(Defs.MOVE_KEYS[code], Input.is_physical_key_pressed(code), now())


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if _done:
		return
	var t := now()
	sim.advance(t)
	var speed := (sim.state_at(t)["vel"] as Vector2).length()
	var hit_index := -1
	var nearest := INF
	for i in _targets.size():
		var d: float = _targets[i].hit_distance(origin, dir)
		if d >= 0.0 and d < nearest:
			nearest = d
			hit_index = i
	shot_hit = hit_index >= 0
	if speed < max_speed * MOVING_FRACTION:
		hud.flash("STÅR STILL" if speed < 1.0 else "FÖR LÅNGSAMT", UI.BAD)
		if _run_start >= 0.0:
			still_shots += 1
			Sfx.play("miss")
		_update_hud()
		return
	if hit_index < 0:
		misses += 1
		Sfx.play("miss")
		_update_hud()
		return
	if hits > 0:
		times.append(t - _last_hit)
	_last_hit = t
	hits += 1
	speeds.append(speed / max_speed)
	Sfx.play("hit")
	_targets[hit_index].pop()
	_targets.remove_at(hit_index)
	_spawn()
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var accuracy := float(r.get("accuracy", 0.0))
	var still := int(r.get("still_shots", 0))
	var speed: Variant = r.get("avg_speed")
	var rows := [
		["Träffsäkerhet i rörelse", "%d %%" % roundi(accuracy * 100.0)],
		["Snittid mellan träffar", UI.ms(r.get("avg_ms"))],
		["Fart vid träff", "%d %% av maxfarten" % roundi(float(speed) * 100.0) if speed != null else "–"],
		["Skott när du stod still", str(still)],
		["Missar", str(int(r.get("misses", 0)))],
	]
	var note := ""
	if still * 4 >= maxi(int(r.get("hits", 0)) + int(r.get("misses", 0)), 4):
		note = "Många skott kom när du nästan stod still, oftast i vändningarna. Skjut mitt i strafen när farten är uppe."
	elif accuracy < 0.7:
		note = "Många missar. Låt siktet följa med målet medan du glider förbi och klicka när det ligger still i siktet."
	elif accuracy >= 0.9:
		note = "Säkert! Prova högre fart eller mindre mål längre bort."
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


## A new target in front of where you are now, away from the other targets and above the floor.
func _spawn() -> void:
	var eye: Vector3 = player.eye_position()
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.saim_range])
	var low := maxf(PITCH.x, Defs.lowest_pitch(dist, eye.y) + 0.5)
	var yaw := 0.0
	var pitch := 0.0
	for attempt in 20:
		yaw = randf_range(-FIELD_YAW, FIELD_YAW)
		pitch = randf_range(low, PITCH.y)
		var dir := Defs.dir_from_angles(yaw, pitch)
		if _targets.all(func(other: Node3D) -> bool: return rad_to_deg(dir.angle_to(other.position - eye)) >= MIN_GAP):
			break
	var target := Target.new()
	if Settings.saim_target == 0:
		target.setup_head(randi() % 2)
	else:
		target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	target.position = eye + Defs.dir_from_angles(yaw, pitch) * dist
	target.rotation.y = deg_to_rad(yaw)
	add_child(target)
	_targets.append(target)


func _finish() -> void:
	_done = true
	for target: Node3D in _targets:
		target.queue_free()
	_targets.clear()
	Sfx.play("done")
	_update_hud()
	var avg: Variant = average(times)
	finished.emit({
		"variant": Defs.variant("strafeaim", Settings),
		"score": hits,
		"hits": hits,
		"misses": misses,
		"still_shots": still_shots,
		"accuracy": float(hits) / maxi(hits + misses, 1),
		"avg_ms": avg * 1000.0 if avg != null else null,
		"avg_speed": average(speeds),
	})


func _update_hud() -> void:
	var left := duration
	if _done:
		left = 0.0
	elif _run_start >= 0.0:
		left = maxf(_run_start + duration - now(), 0.0)
	var shots := hits + misses
	var accuracy := 100 if shots == 0 else roundi(100.0 * hits / shots)
	var title := "STRAFE AIM · %s %d u/s" % [Defs.TRACK_SPEEDS[Settings.saim_speed]["name"], max_speed]
	var stats := "%s s kvar · %d %% · %d stillastående" % [UI.dec(left, 1), accuracy, still_shots]
	hud.set_texts(title, "%d träffar" % hits, stats)
	hud.set_progress(1.0 - left / duration)
