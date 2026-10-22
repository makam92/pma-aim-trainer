extends "res://scripts/modes/mode_base.gd"
## Micro Adjustments: a head shows up just off your crosshair, wherever you are aiming, like when
## your crosshair placement is almost right. Correct the last bit and shoot; the next one shows up
## near the new spot. Hit as many as you can in 60 seconds from the first hit. Also measures how
## straight each correction went: overshooting and coming back counts against it.

const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")

const DELAY := Vector2(0.15, 0.4)   # random wait before the next target, so it can't be timed
const VERTICAL := 0.45              # offsets are mostly sideways, like crosshair placement errors
const DRIFT_LIMIT := 18.0           # beyond this yaw from the middle, targets lead back towards it
const MAX_YAW := 30.0
const TOP_PITCH := 12.0
const MIN_STRAIGHT := 0.3           # corrections shorter than this (degrees) aren't measured

var duration := 60.0
var hits := 0
var misses := 0
var times: Array = []          # seconds from a target appearing to hitting it
var directness: Array = []     # per hit: the straight line to the target / how far the crosshair went

var _target: Target = null
var _shown_at := 0.0
var _next_at := 0.0
var _run_start := -1.0
var _done := false
var _start_aim := Vector3.ZERO
var _last_aim := Vector3.ZERO
var _travel := 0.0             # degrees the crosshair has moved since the target appeared
var _distance := 0.0


func begin() -> void:
	duration = Defs.RUN_SECONDS
	_next_at = now() + 0.5
	hud.message("Skjut första målet för att starta klockan", UI.DIM)
	_update_hud()


func _process(_delta: float) -> void:
	if _done:
		return
	var t := now()
	if _run_start >= 0.0 and t - _run_start >= duration:
		_finish()
		return
	if _target == null:
		if t >= _next_at:
			_spawn()
	else:
		var aim: Vector3 = player.aim_dir()
		_travel += rad_to_deg(_last_aim.angle_to(aim))
		_last_aim = aim
	_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if _done or _target == null:
		return
	if _target.hit_distance(origin, dir) < 0.0:
		misses += 1
		Sfx.play("miss")
		hud.flash("Miss", UI.BAD)
		_update_hud()
		return
	var t := now()
	if _run_start < 0.0:
		_run_start = t
		hud.message("")
	else:
		times.append(t - _shown_at)
	_travel += rad_to_deg(_last_aim.angle_to(dir))
	var straight := rad_to_deg(_start_aim.angle_to(dir))
	if straight >= MIN_STRAIGHT:
		directness.append(clampf(straight / maxf(_travel, straight), 0.0, 1.0))
	hits += 1
	shot_hit = true
	Sfx.play("hit")
	_target.pop()
	_target = null
	_next_at = t + randf_range(DELAY.x, DELAY.y)
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var accuracy := float(r.get("accuracy", 0.0))
	var straight: Variant = r.get("directness")
	var rows := [
		["Träffsäkerhet", "%d %%" % roundi(accuracy * 100.0)],
		["Snittid per mål", UI.ms(r.get("avg_ms"))],
		["Rakhet", "%d %%" % roundi(float(straight) * 100.0) if straight != null else "–"],
		["Missar", str(int(r.get("misses", 0)))],
	]
	var note := ""
	if straight != null and float(straight) < 0.75:
		note = "Rakhet visar hur rakt siktet gick till målet. Du korrigerar ofta förbi och får gå tillbaka; gör rörelsen lugnare och sluta på huvudet."
	elif accuracy < 0.85:
		note = "Många missar. Klicka först när siktet ligger på huvudet, det går fortare i längden."
	elif straight != null and float(straight) >= 0.9 and accuracy >= 0.95:
		note = "Raka och säkra justeringar. Prova längre avstånd så att huvudena blir mindre."
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


## A new target a small step from where you're aiming, mostly sideways, kept inside the room and
## above the floor, and leading back towards the middle if you've wandered off.
func _spawn() -> void:
	var aim := Vector2(wrapf(player.yaw, -180.0, 180.0), player.pitch)
	var offset: Dictionary = Defs.MICRO_OFFSETS[Settings.micro_offset]
	var angle := randf() * TAU
	var step := Vector2(cos(angle), sin(angle) * VERTICAL).normalized() * randf_range(offset["min"], offset["max"])
	if absf(aim.x + step.x) > DRIFT_LIMIT:
		step.x = -signf(aim.x) * absf(step.x)
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.micro_range])
	var eye: Vector3 = player.eye_position()
	var low := Defs.lowest_pitch(dist, eye.y) + 0.5
	var pitch := aim.y + step.y
	if pitch < low or pitch > TOP_PITCH:
		pitch = aim.y - step.y
	pitch = clampf(pitch, low, TOP_PITCH)
	var yaw := clampf(aim.x + step.x, -MAX_YAW, MAX_YAW)
	_target = Target.new()
	if Settings.micro_target == 0:
		_target.setup_head(randi() % 2)
	else:
		_target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	_target.position = eye + Defs.dir_from_angles(yaw, pitch) * dist
	_target.rotation.y = deg_to_rad(yaw)
	add_child(_target)
	_distance = dist
	_shown_at = now()
	_start_aim = player.aim_dir()
	_last_aim = _start_aim
	_travel = 0.0


func _finish() -> void:
	_done = true
	if _target:
		_target.queue_free()
		_target = null
	Sfx.play("done")
	_update_hud()
	var avg: Variant = average(times)
	finished.emit({
		"variant": Defs.variant("micro", Settings),
		"score": hits,
		"hits": hits,
		"misses": misses,
		"accuracy": float(hits) / maxi(hits + misses, 1),
		"avg_ms": avg * 1000.0 if avg != null else null,
		"directness": average(directness),
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
	var info := "%d träffar" % hits
	if _target != null:
		info += "  ·  %d u" % roundi(_distance / Defs.UNIT)
	var stats := "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, UI.ms(avg * 1000.0 if avg != null else null)]
	hud.set_texts("MICRO ADJUSTMENTS", info, stats)
	hud.set_progress(1.0 - left / duration)
