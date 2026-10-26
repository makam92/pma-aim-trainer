extends "res://scripts/modes/mode_base.gd"
## Target Confirmation: hit as many targets as you can in 60 seconds without missing once. One miss
## and you start over. Targets are real head size at random distances, so near ones look big and
## far ones small, like in a real match. The first attempt starts with the run; after a miss the
## clock starts again when you shoot the start target.

const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")

enum Phase { READY, RUN, FAILED, DONE }

const JUMP := Vector2(7.0, 30.0)          # degrees between consecutive targets
const FIELD_YAW := 38.0
const FIELD_PITCH := Vector2(-9.0, 13.0)
const FAIL_PAUSE := 0.9

var duration := 60.0
var limit := 0.0
var phase := Phase.READY
var hits := 0
var attempts := 0
var best_attempt := 0       # most hits in an attempt that ended with a miss
var run_start := 0.0
var target_start := 0.0

var _phase_time := 0.0
var _target: Target = null
var _angles := Vector2.ZERO
var _distance := 0.0
var _pb := -1


func begin() -> void:
	duration = Defs.RUN_SECONDS
	limit = Defs.CONFIRM_LIMITS[Settings.confirm_limit]
	var best: Variant = Stats.best("confirm", Defs.variant("confirm", Settings))
	if best != null:
		_pb = int(best.get("score", 0))
	attempts = 1
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.confirm_range])
	_spawn(_next_angles(Vector2.ZERO, dist), dist, false)
	_update_hud()


func go() -> void:
	phase = Phase.RUN
	run_start = now()
	target_start = run_start


func _process(_delta: float) -> void:
	match phase:
		Phase.RUN:
			var t := now()
			if t - run_start >= duration:
				_complete()
			elif limit > 0.0 and t - target_start > limit:
				_fail("FÖR LÅNGSAMT")
			else:
				_update_hud()
		Phase.FAILED:
			if now() - _phase_time >= FAIL_PAUSE:
				_new_attempt()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if _target == null or (phase != Phase.READY and phase != Phase.RUN):
		return
	if _target.hit_distance(origin, dir) >= 0.0:
		shot_hit = true
		_on_hit()
	elif phase == Phase.RUN:
		_fail("MISS")


static func summary(r: Dictionary) -> Dictionary:
	var attempts_used := int(r.get("attempts", 1))
	var rows := [
		["Snitt per mål", UI.ms(r.get("per_target_ms"))],
		["Försök", str(attempts_used)],
	]
	var note := ""
	if attempts_used == 1:
		note = "Felfritt på första försöket! Prova ett längre avstånd eller en tidsgräns."
	elif attempts_used >= 8:
		note = "Det krävdes %d försök. Känns det för svårt kan du prova avståndet Nära." % attempts_used
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


## After a miss: a fresh start from zero, waiting for the start target.
func _new_attempt() -> void:
	attempts += 1
	hits = 0
	phase = Phase.READY
	_spawn(Vector2.ZERO, Defs.TARGET_DIST, true)
	hud.message("Skjut startmålet när du är redo", UI.DIM)
	_update_hud()


func _on_hit() -> void:
	var t := now()
	_target.pop()
	_target = null
	if phase == Phase.READY:
		phase = Phase.RUN
		run_start = t
		hud.message("")
		Sfx.play("start")
	else:
		hits += 1
		Sfx.play("hit", 1.0 + 0.6 * minf(hits / 40.0, 1.0))
	target_start = t
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.confirm_range])
	_spawn(_next_angles(_angles, dist), dist, false)
	_update_hud()


func _fail(reason: String) -> void:
	phase = Phase.FAILED
	_phase_time = now()
	best_attempt = maxi(best_attempt, hits)
	if _target:
		_target.queue_free()
		_target = null
	Sfx.play("fail")
	hud.tint(UI.BAD)
	hud.message("%s – börja om  (%d träffar)" % [reason, hits], UI.BAD)
	_update_hud()


func _complete() -> void:
	phase = Phase.DONE
	if _target:
		_target.queue_free()
		_target = null
	Sfx.play("done")
	_update_hud()
	finished.emit({
		"variant": Defs.variant("confirm", Settings),
		"score": hits,
		"per_target_ms": duration / hits * 1000.0 if hits > 0 else null,
		"attempts": attempts,
	})


func _spawn(angles: Vector2, dist: float, is_start: bool) -> void:
	_angles = angles
	_distance = dist
	_target = Target.new()
	if is_start:
		_target.setup(Defs.radius_for(0.9), UI.START)
	elif Settings.confirm_target == 0:
		_target.setup_head(randi() % 2)
	else:
		_target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	_target.position = player.eye_position() + Defs.dir_from_angles(angles.x, angles.y) * dist
	_target.rotation.y = deg_to_rad(angles.x)
	add_child(_target)


## The next target's direction: a jump from the last one, inside the field, and never so low that
## a far target would end up under the floor.
func _next_angles(from: Vector2, dist: float) -> Vector2:
	var eye: Vector3 = player.eye_position()
	var low := maxf(FIELD_PITCH.x, Defs.lowest_pitch(dist, eye.y))
	for i in 24:
		var a := randf() * TAU
		var p := from + Vector2(cos(a), sin(a) * 0.6) * randf_range(JUMP.x, JUMP.y)
		if absf(p.x) <= FIELD_YAW and p.y >= low and p.y <= FIELD_PITCH.y and p.distance_to(from) >= JUMP.x:
			return p
	return Vector2(randf_range(-FIELD_YAW, FIELD_YAW), randf_range(low, FIELD_PITCH.y))


func _update_hud() -> void:
	var left := duration
	if phase == Phase.RUN:
		left = maxf(run_start + duration - now(), 0.0)
	elif phase == Phase.DONE:
		left = 0.0
	var info := "%d träffar" % hits
	if phase == Phase.RUN and _target != null:
		info += "  ·  %d u" % roundi(_distance / Defs.UNIT)
	var pb := "PB %d" % _pb if _pb >= 0 else "inget PB än"
	var stats := "%s s kvar · försök %d · %s" % [UI.dec(left, 1), attempts, pb]
	hud.set_texts("TARGET CONFIRMATION", info, stats)
	hud.set_progress(1.0 - left / duration)
