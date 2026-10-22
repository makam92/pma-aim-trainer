extends "res://scripts/modes/mode_base.gd"
## Tracking Confirmation: kill strafing CS2 bots one after another for 60 seconds. Every bot moves
## with real CS2 movement (ADAD, counter-strafes, max speed) at a new spot and distance. Only a kill
## brings the next bot; misses, and body hits when aiming for heads, count against your accuracy.
## The clock starts on the start target.

const Sim = preload("res://scripts/movement_sim.gd")
const Brain = preload("res://scripts/bot_brain.gd")
const Dummy = preload("res://scripts/dummy.gd")
const Target = preload("res://scripts/target.gd")

enum Phase { READY, RUN, DONE }

const FIELD_YAW := 25.0      # bots appear up to this far to each side
const LANE_UNITS := 160.0    # and strafe up to this far either way,
const LANE_DEG := 18.0       # but never more than this, seen from you

var duration := 60.0
var max_speed := 250.0
var zone := "head"
var phase := Phase.READY
var kills := 0
var misses := 0
var body_hits := 0
var run_start := 0.0

var _start: Target = null
var _dummy: Dummy = null
var _sim: Sim = null
var _brain: Brain = null
var _origin := Vector3.ZERO
var _distance := 0.0
var _pb := -1


func begin() -> void:
	duration = Defs.RUN_SECONDS
	max_speed = Defs.TRACK_SPEEDS[Settings.tconf_speed]["speed"]
	zone = Defs.TRACK_ZONES[Settings.tconf_zone]["id"]
	var best: Variant = Stats.best("tconfirm", Defs.variant("tconfirm", Settings))
	if best != null:
		_pb = int(best.get("score", 0))
	_start = Target.new()
	_start.setup(Defs.radius_for(0.9), UI.START)
	_start.position = player.eye_position() + Vector3(0.0, 0.0, -Defs.TARGET_DIST)
	add_child(_start)
	hud.message("Skjut startmålet när du är redo", UI.DIM)
	_update_hud()


func _process(_delta: float) -> void:
	var t := now()
	if _sim:
		_brain.update(t)
		_sim.advance(t)
		var state := _sim.state_at(t)
		var p: Vector2 = state["pos"]
		var vel: Vector2 = state["vel"]
		_dummy.position = _origin + Vector3(p.x * Defs.UNIT, 0.0, 0.0)
		_dummy.face(player.eye_position())
		_dummy.set_motion(vel.x, state["duck"])
	if phase == Phase.RUN:
		if t - run_start >= duration:
			_complete()
		else:
			_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	match phase:
		Phase.READY:
			if _start and _start.hit_distance(origin, dir) >= 0.0:
				shot_hit = true
				_start.pop()
				_start = null
				phase = Phase.RUN
				run_start = now()
				hud.message("")
				Sfx.play("start")
				_spawn_bot()
		Phase.RUN:
			var part: String = _dummy.hit_test(origin, dir)["part"]
			shot_hit = part != ""
			if part == "head" or (part == "body" and zone == "body"):
				kills += 1
				Sfx.play("head" if part == "head" else "hit", 1.0 + 0.5 * minf(kills / 30.0, 1.0))
				_spawn_bot()
			elif part == "body":
				body_hits += 1
				Sfx.play("hit")
				_dummy.flash("body")
			else:
				misses += 1
				Sfx.play("miss")
			_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var accuracy := float(r.get("accuracy", 0.0))
	var head_only: bool = r.get("zone", "head") == "head"
	var rows := [
		["Snitt per kill", UI.ms(r.get("per_kill_ms"))],
		["Träffsäkerhet", "%d %%" % roundi(accuracy * 100.0)],
		["Missar", str(int(r.get("misses", 0)))],
	]
	if head_only:
		rows.append(["Kroppsträffar", str(int(r.get("body_hits", 0)))])
	var note := ""
	if int(r.get("score", 0)) > 0:
		if accuracy < 0.6:
			note = "Många skott som inte dödade. Vänta tills siktet ligger på huvudet innan du skjuter, det går fortare i längden."
		elif accuracy >= 0.9:
			note = "Nästan varje skott dödade. Prova högre fart eller längre avstånd." if head_only \
				else "Nästan varje skott dödade. Prova att bara räkna huvudträffar."
	return {"headline": str(int(r.get("score", 0))), "unit": "kills på 60 s", "rows": rows, "note": note}


## A new bot at a random direction and distance, strafing in its own lane.
func _spawn_bot() -> void:
	_clear_bot()
	_distance = Defs.random_distance(Defs.TARGET_RANGES[Settings.tconf_range])
	var flat := Defs.dir_from_angles(randf_range(-FIELD_YAW, FIELD_YAW), 0.0)
	_origin = Vector3(flat.x, 0.0, flat.z) * _distance
	_sim = Sim.new()
	_sim.max_speed = max_speed
	var half := minf(LANE_UNITS, _distance * tan(deg_to_rad(LANE_DEG)) / Defs.UNIT)
	_sim.bounds = Rect2(-half, -1.0, half * 2.0, 2.0)
	var t := now()
	_sim.reset(t)
	_brain = Brain.new()
	_brain.sim = _sim
	_brain.start(t)
	_dummy = Dummy.new()
	_dummy.team = randi() % 2
	_dummy.weapon_kind = "rifle" if max_speed <= 225.0 and max_speed >= 200.0 else "knife"
	_dummy.gait = "walk" if max_speed <= 140.0 else "run"
	_dummy.position = _origin
	add_child(_dummy)
	_brain.crouch = Settings.bot_crouch and _dummy.can_crouch()


func _clear_bot() -> void:
	if _dummy:
		_dummy.queue_free()
	_dummy = null
	_sim = null
	_brain = null


func _complete() -> void:
	phase = Phase.DONE
	_clear_bot()
	Sfx.play("done")
	_update_hud()
	var shots := kills + misses + body_hits
	finished.emit({
		"variant": Defs.variant("tconfirm", Settings),
		"score": kills,
		"zone": zone,
		"shots": shots,
		"misses": misses,
		"body_hits": body_hits,
		"accuracy": float(kills) / maxi(shots, 1),
		"per_kill_ms": duration / kills * 1000.0 if kills > 0 else null,
	})


func _update_hud() -> void:
	var left := duration
	if phase == Phase.RUN:
		left = maxf(run_start + duration - now(), 0.0)
	elif phase == Phase.DONE:
		left = 0.0
	var info := "%d kills" % kills
	if phase == Phase.RUN and _dummy != null:
		info += "  ·  %d u" % roundi(_distance / Defs.UNIT)
	var shots := kills + misses + body_hits
	var accuracy := 100 if shots == 0 else roundi(100.0 * kills / shots)
	var pb := "PB %d" % _pb if _pb >= 0 else "inget PB än"
	var bot_name: String = Defs.TRACK_SPEEDS[Settings.tconf_speed]["name"]
	var title := "TRACKING CONFIRMATION · %s %d u/s" % [bot_name, max_speed]
	hud.set_texts(title, info, "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, pb])
	hud.set_progress(1.0 - left / duration)
