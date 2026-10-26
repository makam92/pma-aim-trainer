extends "res://scripts/modes/mode_base.gd"
## Micro Adjustments: a flick to a head further away, then three heads just off your crosshair to
## correct onto, like follow-up shots or an enemy right next to the first one; then a new flick, and
## so on. Every head shows up the moment the last one is hit. Hit as many as you can in 60 seconds.
## Measures how straight each small correction went (going past and coming back counts against it)
## and whether your flicks stop short or go past.

const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")

const MICROS := 3                   # small corrections after every flick
const FLICK := Vector2(12.0, 35.0)  # degrees from your crosshair to a flick's head,
const FIELD_YAW := 40.0             # which stays this far to each side of straight ahead
const FLICK_PITCH := 7.0
const VERTICAL := 0.45              # corrections are mostly sideways, like crosshair placement errors
const DRIFT_LIMIT := 18.0           # beyond this yaw from the middle, corrections lead back towards it
const MAX_YAW := 50.0
const TOP_PITCH := 12.0
const MIN_STRAIGHT := 0.3           # corrections shorter than this (degrees) aren't measured
const SAMPLE_INTERVAL := 0.004
const MAX_SAMPLES := 1000           # about 4 seconds of aim movement

var duration := 60.0
var hits := 0
var misses := 0
var flick_times: Array = []         # seconds from a flick's head showing up to hitting it
var micro_times: Array = []         # the same for the corrections
var directness: Array = []          # per correction: the straight line to the head / how far the crosshair went
var ratios: Array = []              # per flick: how far its fast part went, 1.0 spot on

var _target: Target = null
var _target_angles := Vector2.ZERO
var _step := 0                      # 0: a flick, 1..MICROS: the corrections after it
var _shown_at := 0.0
var _run_start := -1.0
var _done := false
var _start_aim := Vector3.ZERO
var _last_aim := Vector3.ZERO
var _travel := 0.0                  # degrees the crosshair has moved since the head showed up
var _start_angles := Vector2.ZERO
var _samples: Array = []            # Vector3(time, yaw, pitch) since the head showed up
var _distance := 0.0


func begin() -> void:
	duration = Defs.RUN_SECONDS
	_spawn()
	_update_hud()


## The first flick is timed and measured from wherever you aim when the run starts.
func go() -> void:
	_run_start = now()
	_shown_at = _run_start
	_start_aim = player.aim_dir()
	_last_aim = _start_aim
	_travel = 0.0
	_start_angles = _aim_angles()
	_samples = [Vector3(_run_start, _start_angles.x, _start_angles.y)]


func _process(_delta: float) -> void:
	if _done:
		return
	var t := now()
	if _run_start >= 0.0 and t - _run_start >= duration:
		_finish()
		return
	var aim: Vector3 = player.aim_dir()
	_travel += rad_to_deg(_last_aim.angle_to(aim))
	_last_aim = aim
	var last: Vector3 = _samples[-1]
	if t - last.x >= SAMPLE_INTERVAL:
		var angles := _aim_angles()
		_samples.append(Vector3(t, angles.x, angles.y))
		if _samples.size() > MAX_SAMPLES:
			_samples.pop_front()
	_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if _done or _target == null:
		return
	if _target.hit_distance(origin, dir) < 0.0:
		if _run_start >= 0.0:
			misses += 1
		Sfx.play("miss")
		hud.flash("Miss", UI.BAD)
		_update_hud()
		return
	var t := now()
	if _step == 0:
		flick_times.append(t - _shown_at)
	else:
		micro_times.append(t - _shown_at)
	if _step == 0:
		var angles := _aim_angles()
		_samples.append(Vector3(t, angles.x, angles.y))
		var ratio: Variant = flick_ratio(_samples, _start_angles, _target_angles)
		if ratio != null:
			ratios.append(ratio)
	else:
		_travel += rad_to_deg(_last_aim.angle_to(dir))
		var straight := rad_to_deg(_start_aim.angle_to(dir))
		if straight >= MIN_STRAIGHT:
			directness.append(clampf(straight / maxf(_travel, straight), 0.0, 1.0))
	hits += 1
	shot_hit = true
	Sfx.play("hit")
	flash_time(t - _shown_at)
	_target.pop()
	_target = null
	_step = (_step + 1) % (MICROS + 1)
	_spawn()
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var accuracy := float(r.get("accuracy", 0.0))
	var straight: Variant = r.get("directness")
	var bias: Variant = r.get("flick_bias")
	var rows := [
		["Träffsäkerhet", "%d %%" % roundi(accuracy * 100.0)],
		["Snittid flick", UI.ms(r.get("flick_ms"))],
		["Snittid micro", UI.ms(r.get("micro_ms"))],
		["Rakhet", "%d %%" % roundi(float(straight) * 100.0) if straight != null else "–"],
		["Flicklängd", flick_length_text(bias) if bias != null else "–"],
		["Missar", str(int(r.get("misses", 0)))],
	]
	var note := ""
	if straight != null and float(straight) < 0.75:
		note = "Rakhet visar hur rakt siktet gick till målet. Du korrigerar ofta förbi och får gå tillbaka; gör rörelsen lugnare och sluta på huvudet."
	elif bias != null and flick_length_note(bias) != "":
		note = flick_length_note(bias)
	elif accuracy < 0.85:
		note = "Många missar. Klicka först när siktet ligger på huvudet, det går fortare i längden."
	elif straight != null and float(straight) >= 0.9 and accuracy >= 0.95:
		note = "Raka och säkra justeringar. Prova längre avstånd så att huvudena blir mindre."
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


## The next head, inside the room and above the floor: for a flick further away and on screen, else
## a small step from where you aim.
func _spawn() -> void:
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.micro_range])
	var eye: Vector3 = player.eye_position()
	var low := Defs.lowest_pitch(dist, eye.y) + 0.5
	var aim := _aim_angles()
	var angles := _flick_angles(aim, low) if _step == 0 else _micro_angles(aim, low)
	_target = Target.new()
	if Settings.micro_target == 0:
		_target.setup_head(randi() % 2)
	else:
		_target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	_target.position = eye + Defs.dir_from_angles(angles.x, angles.y) * dist
	_target.rotation.y = deg_to_rad(angles.x)
	add_child(_target)
	_target_angles = angles
	_distance = dist
	_shown_at = now()
	_start_aim = player.aim_dir()
	_last_aim = _start_aim
	_travel = 0.0
	_start_angles = aim
	_samples = [Vector3(_shown_at, aim.x, aim.y)]


## A flick's head: on screen from where you aim, FLICK away from it, and near the middle.
func _flick_angles(aim: Vector2, low: float) -> Vector2:
	# What fits on screen to each side of where you aim (at 16:9 about 53°, at 5:4 about 43°).
	var screen := Vector2(main.game_view.size)
	var reach := rad_to_deg(atan(tan(deg_to_rad(Defs.CS_VFOV / 2.0)) * screen.x / screen.y)) - 5.0
	var lo := maxf(-FIELD_YAW, aim.x - reach)
	var hi := minf(FIELD_YAW, aim.x + reach)
	var bottom := maxf(-FLICK_PITCH, low)
	var angles := aim
	for attempt in 40:
		angles = Vector2(randf_range(lo, maxf(lo, hi)), randf_range(bottom, maxf(bottom, FLICK_PITCH)))
		var away := angles.distance_to(aim)
		if away >= FLICK.x and away <= FLICK.y:
			break
	return angles


## A correction's head: the setting's distance from where you aim, mostly sideways, and leading back
## towards the middle if you've wandered off.
func _micro_angles(aim: Vector2, low: float) -> Vector2:
	var offset: Dictionary = Defs.MICRO_OFFSETS[Settings.micro_offset]
	var a := randf() * TAU
	var step := Vector2(cos(a), sin(a) * VERTICAL).normalized() * randf_range(offset["min"], offset["max"])
	if absf(aim.x + step.x) > DRIFT_LIMIT:
		step.x = -signf(aim.x) * absf(step.x)
	var pitch := aim.y + step.y
	if pitch < low or pitch > TOP_PITCH:
		pitch = aim.y - step.y
	return Vector2(clampf(aim.x + step.x, -MAX_YAW, MAX_YAW), clampf(pitch, low, TOP_PITCH))


## Your aim as (yaw, pitch) in degrees, with the yaw kept between -180 and 180 like the heads' angles.
func _aim_angles() -> Vector2:
	return Vector2(wrapf(player.yaw, -180.0, 180.0), player.pitch)


func _finish() -> void:
	_done = true
	if _target:
		_target.queue_free()
		_target = null
	Sfx.play("done")
	_update_hud()
	var bias: Variant = average(ratios)
	finished.emit({
		"variant": Defs.variant("micro", Settings),
		"score": hits,
		"hits": hits,
		"misses": misses,
		"accuracy": float(hits) / maxi(hits + misses, 1),
		"flick_ms": to_ms(average(flick_times)),
		"micro_ms": to_ms(average(micro_times)),
		"directness": average(directness),
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
	var avg: Variant = average(flick_times + micro_times)
	var info := "%d träffar  ·  %s" % [hits, "FLICK" if _step == 0 else "MICRO %d/%d" % [_step, MICROS]]
	if _target != null:
		info += "  ·  %d u" % roundi(_distance / Defs.UNIT)
	var stats := "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, UI.ms(avg * 1000.0 if avg != null else null)]
	hud.set_texts("MICRO ADJUSTMENTS", info, stats)
	hud.set_progress(1.0 - left / duration)
