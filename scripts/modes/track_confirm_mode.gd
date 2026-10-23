extends "res://scripts/modes/mode_base.gd"
## Tracking Confirmation: kill strafing CS2 bots one after another for 60 seconds. Every bot moves
## with real CS2 movement (ADAD, counter-strafes, max speed) at a new spot and distance. Only a kill
## brings the next bot; misses, and body hits when aiming for heads, count against your accuracy.
## With lives (3, or 1 on Hard) every shot that doesn't kill costs one, and losing the last one starts
## you over from zero, like in Target Confirmation. The clock starts on the start target.

const Sim = preload("res://scripts/movement_sim.gd")
const Brain = preload("res://scripts/bot_brain.gd")
const Dummy = preload("res://scripts/dummy.gd")
const Target = preload("res://scripts/target.gd")

enum Phase { READY, RUN, FAILED, DONE }

const FIELD_YAW := 25.0      # bots appear up to this far to each side
const LANE_UNITS := 160.0    # and strafe up to this far either way,
const LANE_DEG := 18.0       # but never more than this, seen from you
const FAIL_PAUSE := 0.9      # with lives, seconds before you can start over

var duration := 60.0
var max_speed := 250.0
var zone := "head"
var lives := 0               # shots that don't kill you get per attempt; 0 for no limit
var lives_left := 0
var phase := Phase.READY
var kills := 0
var misses := 0
var body_hits := 0
var attempts := 0
var run_start := 0.0

var _phase_time := 0.0
var _mixed := false          # every bot gets a CS2 speed at random
var _start: Target = null
var _dummy: Dummy = null
var _sim: Sim = null
var _brain: Brain = null
var _origin := Vector3.ZERO
var _distance := 0.0
var _pb := -1


func begin() -> void:
	duration = Defs.RUN_SECONDS
	_mixed = Settings.tconf_speed >= Defs.TRACK_SPEEDS.size()
	if not _mixed:
		max_speed = Defs.TRACK_SPEEDS[Settings.tconf_speed]["speed"]
	zone = Defs.TRACK_ZONES[Settings.tconf_zone]["id"]
	lives = Defs.TCONF_LEVELS[Settings.tconf_lives]["lives"]
	var best: Variant = Stats.best("tconfirm", Defs.variant("tconfirm", Settings))
	if best != null:
		_pb = int(best.get("score", 0))
	_new_attempt()


## A fresh start from zero, waiting for the start target.
func _new_attempt() -> void:
	attempts += 1
	kills = 0
	misses = 0
	body_hits = 0
	lives_left = lives
	phase = Phase.READY
	_start = Target.new()
	_start.setup(Defs.radius_for(0.9), UI.START)
	_start.position = player.eye_position() + Vector3(0.0, 0.0, -Defs.TARGET_DIST)
	add_child(_start)
	var rule := ""
	if lives == 1:
		rule = "  ·  en miss och du börjar om"
	elif lives > 1:
		rule = "  ·  %d missar och du börjar om" % lives
	hud.message("Skjut startmålet när du är redo" + rule, UI.DIM)
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
	match phase:
		Phase.RUN:
			if t - run_start >= duration:
				_complete()
			else:
				_update_hud()
		Phase.FAILED:
			if t - _phase_time >= FAIL_PAUSE:
				_new_attempt()


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
			elif lives > 0:
				_lose_life(part)
				return
			elif part == "body":
				body_hits += 1
				Sfx.play("hit")
				_dummy.flash("body")
			else:
				misses += 1
				Sfx.play("miss")
			_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	if int(r.get("lives", 0)) > 0:
		return _lives_summary(r)
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


## A run with lives: how many attempts it took, and with more than one life how many were left.
static func _lives_summary(r: Dictionary) -> Dictionary:
	var lives_at_start := int(r.get("lives", 1))
	var attempts_used := int(r.get("attempts", 1))
	var rows := [["Snitt per kill", UI.ms(r.get("per_kill_ms"))], ["Försök", str(attempts_used)]]
	if lives_at_start > 1:
		rows.append(["Liv kvar", "%d av %d" % [int(r.get("lives_left", 0)), lives_at_start]])
	var note := ""
	if attempts_used == 1:
		note = "Klart på första försöket! " + ("Prova Hard, där en miss räcker." if lives_at_start > 1 \
			else "Prova högre fart eller längre avstånd.")
	elif attempts_used >= 8:
		note = "Det krävdes %d försök. Känns det för svårt kan du prova lägre fart eller avståndet Nära." % attempts_used
	var unit := "kills på 60 s utan miss" if lives_at_start == 1 else "kills på 60 s"
	return {"headline": str(int(r.get("score", 0))), "unit": unit, "rows": rows, "note": note}


## A new bot at a random direction and distance, strafing in its own lane (at a random CS2 speed
## when they're mixed).
func _spawn_bot() -> void:
	_clear_bot()
	if _mixed:
		var pick: Dictionary = Defs.TRACK_SPEEDS.pick_random()
		max_speed = pick["speed"]
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


## With lives: a shot that didn't kill costs one, and losing the last one ends the attempt.
func _lose_life(part: String) -> void:
	var reason := "KROPPSTRÄFF" if part == "body" else "MISS"
	lives_left -= 1
	if lives_left <= 0:
		_fail(reason)
		return
	if part == "body":
		body_hits += 1
		_dummy.flash("body")
	else:
		misses += 1
	Sfx.play("miss")
	hud.tint(UI.BAD, 0.12)
	hud.flash("%s · %d liv kvar" % [reason, lives_left], UI.BAD)
	_update_hud()


## Out of lives: this attempt is over, and a new one starts from zero.
func _fail(reason: String) -> void:
	phase = Phase.FAILED
	_phase_time = now()
	_clear_bot()
	Sfx.play("fail")
	hud.tint(UI.BAD)
	hud.message("%s – börja om  (%d kills)" % [reason, kills], UI.BAD)
	_update_hud()


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
		"lives": lives,
		"lives_left": lives_left,
		"attempts": attempts,
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
		if _mixed:
			info += "  ·  %d u/s" % max_speed
	var shots := kills + misses + body_hits
	var accuracy := 100 if shots == 0 else roundi(100.0 * kills / shots)
	var pb := "PB %d" % _pb if _pb >= 0 else "inget PB än"
	var title := "TRACKING CONFIRMATION · " + (Defs.MIXED_SPEED if _mixed \
		else "%s %d u/s" % [Defs.TRACK_SPEEDS[Settings.tconf_speed]["name"], max_speed])
	var stats := "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, pb]
	if lives > 0:
		title += " · " + str(Defs.TCONF_LEVELS[Settings.tconf_lives]["name"]).to_upper()
		var left_text := "%d liv · " % lives_left if lives > 1 else ""
		stats = "%s s kvar · %sförsök %d · %s" % [UI.dec(left, 1), left_text, attempts, pb]
	hud.set_texts(title, info, stats)
	hud.set_progress(1.0 - left / duration)
