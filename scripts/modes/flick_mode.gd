extends "res://scripts/modes/mode_base.gd"
## Flicks: two heads are always up at random angles and distances in front of you. Flick to one and
## shoot, and a new one shows up right away somewhere else: never right at your crosshair, and always
## close enough to the other head that both are on screen together. Hit as many as you can in 60
## seconds. Also shows whether your flicks tend to stop short or go past.

const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")

const ACTIVE := 2                  # heads up at a time
const MIN_FLICK := 12.0            # degrees a new head is at least from your crosshair,
const MIN_GAP := 10.0              # and from the other head
const FIELD_YAW := 45.0            # heads stay this far to each side of straight ahead
const PITCH_RANGE := 7.0
const SAMPLE_INTERVAL := 0.004
const MAX_SAMPLES := 1000          # about 4 seconds of aim movement

var duration := 60.0
var hits := 0
var misses := 0
var times: Array = []              # seconds between consecutive hits
var ratios: Array = []

var _targets: Array = []           # {"node": Target, "angles": Vector2 (yaw, pitch), "distance": meters}
var _run_start := -1.0
var _last_hit := 0.0
var _done := false
var _start_angles := Vector2.ZERO  # your aim at the last hit, where the next flick starts
var _samples: Array = []           # Vector3(time, yaw, pitch) since the last hit


func begin() -> void:
	duration = Defs.RUN_SECONDS
	for i in ACTIVE:
		_spawn()
	_start_angles = _aim_angles()
	_samples = [Vector3(now(), _start_angles.x, _start_angles.y)]
	_update_hud()


## The first flick starts from wherever you aim when the run starts.
func go() -> void:
	_run_start = now()
	_last_hit = _run_start
	_start_angles = _aim_angles()
	_samples = [Vector3(_run_start, _start_angles.x, _start_angles.y)]


func _process(_delta: float) -> void:
	if _done:
		return
	var t := now()
	if _run_start >= 0.0 and t - _run_start >= duration:
		_finish()
		return
	var last: Vector3 = _samples[-1]
	if t - last.x >= SAMPLE_INTERVAL:
		var aim := _aim_angles()
		_samples.append(Vector3(t, aim.x, aim.y))
		if _samples.size() > MAX_SAMPLES:
			_samples.pop_front()
	_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if _done:
		return
	var hit := -1
	var nearest := INF
	for i in _targets.size():
		var d: float = _targets[i]["node"].hit_distance(origin, dir)
		if d >= 0.0 and d < nearest:
			nearest = d
			hit = i
	if hit < 0:
		if _run_start >= 0.0:
			misses += 1
		Sfx.play("miss")
		hud.flash("Miss", UI.BAD)
		_update_hud()
		return
	var t := now()
	times.append(t - _last_hit)
	flash_time(t - _last_hit)
	_last_hit = t
	hits += 1
	shot_hit = true
	Sfx.play("hit")
	var target: Dictionary = _targets[hit]
	var aim := _aim_angles()
	_samples.append(Vector3(t, aim.x, aim.y))
	var ratio: Variant = flick_ratio(_samples, _start_angles, target["angles"])
	if ratio != null:
		ratios.append(ratio)
	target["node"].pop()
	_targets.remove_at(hit)
	_start_angles = aim
	_samples = [Vector3(t, aim.x, aim.y)]
	_spawn()
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var rows := [
		["Träffsäkerhet", "%d %%" % roundi(float(r.get("accuracy", 0.0)) * 100.0)],
		["Snittid mellan träffar", UI.ms(r.get("avg_ms"))],
		["Missar", str(int(r.get("misses", 0)))],
	]
	var note := ""
	var bias: Variant = r.get("flick_bias")
	if bias != null:
		rows.append(["Flicklängd", flick_length_text(bias)])
		note = flick_length_note(bias)
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


## A new head in front of you: on screen from where you aim, close enough to the other head that both
## fit on screen at once, at least MIN_FLICK from your crosshair and MIN_GAP from the other head, and
## above the floor.
func _spawn() -> void:
	# What fits on screen to each side of where you aim (at 16:9 about 53°, at 5:4 about 43°).
	var screen := Vector2(main.game_view.size)
	var reach := rad_to_deg(atan(tan(deg_to_rad(Defs.CS_VFOV / 2.0)) * screen.x / screen.y)) - 5.0
	var aim := _aim_angles()
	var lo := maxf(-FIELD_YAW, aim.x - reach)
	var hi := minf(FIELD_YAW, aim.x + reach)
	for other: Dictionary in _targets:
		lo = maxf(lo, other["angles"].x - reach)
		hi = minf(hi, other["angles"].x + reach)
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.flick_range])
	var eye: Vector3 = player.eye_position()
	# Far heads can't go as low, or they'd end up under the floor.
	var low := maxf(-PITCH_RANGE, Defs.lowest_pitch(dist, eye.y))
	var angles := Vector2.ZERO
	for attempt in 40:
		angles = Vector2(randf_range(lo, maxf(lo, hi)), randf_range(low, PITCH_RANGE))
		var clear := angles.distance_to(aim) >= MIN_FLICK
		for other: Dictionary in _targets:
			clear = clear and angles.distance_to(other["angles"]) >= MIN_GAP
		if clear:
			break
	var target := Target.new()
	if Settings.flick_target == 0:
		target.setup_head(randi() % 2)
	else:
		target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	target.position = eye + Defs.dir_from_angles(angles.x, angles.y) * dist
	target.rotation.y = deg_to_rad(angles.x)
	add_child(target)
	_targets.append({"node": target, "angles": angles, "distance": dist})


## Your aim as (yaw, pitch) in degrees, with the yaw kept between -180 and 180 like the heads' angles.
func _aim_angles() -> Vector2:
	return Vector2(wrapf(player.yaw, -180.0, 180.0), player.pitch)


func _finish() -> void:
	_done = true
	for target: Dictionary in _targets:
		target["node"].queue_free()
	_targets.clear()
	Sfx.play("done")
	_update_hud()
	var bias: Variant = average(ratios)
	var avg: Variant = average(times)
	finished.emit({
		"variant": Defs.variant("flick", Settings),
		"score": hits,
		"hits": hits,
		"misses": misses,
		"accuracy": float(hits) / maxi(hits + misses, 1),
		"avg_ms": avg * 1000.0 if avg != null else null,
		"flick_bias": bias - 1.0 if bias != null else null,
	})


func _update_hud() -> void:
	var left := duration
	if _done:
		left = 0.0
	elif _run_start >= 0.0:
		left = maxf(_run_start + duration - now(), 0.0)
	var shots := hits + misses
	var accuracy := 100 if shots == 0 else roundi(100.0 * hits / shots)
	var avg: Variant = average(times)
	var stats := "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, UI.ms(avg * 1000.0 if avg != null else null)]
	hud.set_texts("FLICKS", "%d träffar" % hits, stats)
	hud.set_progress(1.0 - left / duration)
