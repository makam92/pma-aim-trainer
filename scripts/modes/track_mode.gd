extends "res://scripts/modes/mode_base.gd"
## Tracking: keep the crosshair on a bot that strafes with real CS2 movement (the same acceleration,
## friction and max speed as a player), including ADAD reversals and counter-strafed stops.

const Sim = preload("res://scripts/movement_sim.gd")
const Brain = preload("res://scripts/bot_brain.gd")
const Dummy = preload("res://scripts/dummy.gd")
const SpeedMeter = preload("res://scripts/ui/speed_meter.gd")

const LANE_DEG := 25.0          # how far to each side the bot may go, seen from you
const REACTION_WINDOW := 0.3    # seconds after the bot changes direction that count as "reaction"

var max_speed := 250.0
var dist := 15.0
var duration := 30.0
var zone := "head"
var sim: Sim
var brain: Brain
var dummy: Dummy
var meter: SpeedMeter
var run_start := 0.0
var running := false
var done := false

var total := 0.0
var on_head := 0.0
var on_body := 0.0
var react_total := 0.0
var react_on := 0.0
var error_sum := 0.0
var streak := 0.0
var best_streak := 0.0
var _last_t := 0.0
var _change_index := 0


func begin() -> void:
	max_speed = Defs.TRACK_SPEEDS[Settings.track_speed]["speed"]
	dist = float(Defs.TRACK_DISTS[Settings.track_dist]) * Defs.UNIT
	duration = Defs.RUN_SECONDS
	zone = Defs.TRACK_ZONES[Settings.track_zone]["id"]
	sim = Sim.new()
	sim.max_speed = max_speed
	var half := dist * tan(deg_to_rad(LANE_DEG)) / Defs.UNIT
	sim.bounds = Rect2(-half, -1.0, half * 2.0, 2.0)
	var t := now()
	sim.reset(t)
	brain = Brain.new()
	brain.sim = sim
	dummy = Dummy.new()
	dummy.team = randi() % 2
	# Knife speed and walking use the knife animations; rifle speeds hold a rifle.
	dummy.weapon_kind = "rifle" if max_speed <= 225.0 and max_speed >= 200.0 else "knife"
	dummy.gait = "walk" if max_speed <= 140.0 else "run"
	dummy.position = Vector3(0.0, 0.0, -dist)
	add_child(dummy)
	brain.crouch = Settings.bot_crouch and dummy.can_crouch()
	meter = SpeedMeter.new()
	meter.sim = sim
	meter.title = "Gubbens fart"
	meter.neutral = true
	hud.add_widget(meter)
	run_start = INF    # the bot stands still until the run starts
	_last_t = t
	_update_hud()


func go() -> void:
	run_start = now()


func _process(_delta: float) -> void:
	if sim == null:
		return
	var t := now()
	var dt := t - _last_t
	_last_t = t
	if not running and not done and t >= run_start:
		running = true
		brain.start(run_start)
	if running:
		brain.update(t)
	sim.advance(t)
	var state := sim.state_at(t)
	var p: Vector2 = state["pos"]
	var vel: Vector2 = state["vel"]
	dummy.position = Vector3(p.x * Defs.UNIT, 0.0, -dist)
	dummy.face(player.eye_position())
	dummy.set_motion(vel.x, state["duck"])
	meter.speed = vel.length()
	meter.queue_redraw()
	if running:
		_measure(t, dt)
		if t - run_start >= duration:
			_finish()
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var zone_name := "huvudet" if r.get("zone", "head") == "head" else "kroppen"
	var rows := [
		["På huvudet", _pct(r.get("head_pct"))],
		["På kroppen", _pct(r.get("body_pct"))],
		["Direkt efter riktningsbyte", _pct(r.get("react_pct"))],
		["Resten av tiden", _pct(r.get("steady_pct"))],
		["Snittavstånd till huvudet", UI.dec(r.get("avg_error_deg", 0.0), 2) + "°"],
		["Längst i rad på " + zone_name, UI.dec(r.get("best_streak", 0.0), 2) + " s"],
		["Riktningsbyten", str(int(r.get("changes", 0)))],
	]
	var note := ""
	var react: Variant = r.get("react_pct")
	var steady: Variant = r.get("steady_pct")
	var score := float(r.get("score", 0)) / 10000.0
	if react != null and steady != null and float(react) < float(steady) * 0.6:
		note = "Du tappar gubben när han byter riktning. Följ med när han bromsar i stället för att fortsätta åt samma håll."
	elif score >= 0.6:
		note = "Starkt! Prova högre fart, längre avstånd eller att sikta på huvudet."
	elif score < 0.2:
		note = "Tufft läge. Börja med kortare avstånd eller lägre fart och öka sedan."
	return {"headline": UI.dec(score * 100.0, 1) + " %", "unit": "på " + zone_name, "rows": rows, "note": note}


static func _pct(value: Variant) -> String:
	return "–" if value == null else UI.dec(float(value) * 100.0, 1) + " %"


func _measure(t: float, dt: float) -> void:
	if dt <= 0.0 or dt > 0.1:
		return
	var origin: Vector3 = player.eye_position()
	var aim: Vector3 = player.aim_dir()
	var part: String = dummy.hit_test(origin, aim)["part"]
	var in_zone := part == "head" if zone == "head" else part != ""
	total += dt
	if part != "":
		on_body += dt
	if part == "head":
		on_head += dt
	streak = streak + dt if in_zone else 0.0
	best_streak = maxf(best_streak, streak)
	error_sum += rad_to_deg(aim.angle_to((dummy.head_centre() - origin).normalized())) * dt
	var changes: Array = brain.changes
	while _change_index + 1 < changes.size() and changes[_change_index + 1] <= t:
		_change_index += 1
	if not changes.is_empty() and changes[_change_index] <= t and t - changes[_change_index] <= REACTION_WINDOW:
		react_total += dt
		if in_zone:
			react_on += dt
	dummy.glow(part)


func _finish() -> void:
	running = false
	done = true
	dummy.glow("")
	Sfx.play("done")
	var zone_on := on_head if zone == "head" else on_body
	var seconds := maxf(total, 0.001)
	var steady_total := total - react_total
	var end_time := run_start + duration
	finished.emit({
		"variant": Defs.variant("track", Settings),
		"score": roundi(zone_on / seconds * 10000.0),
		"zone": zone,
		"head_pct": on_head / seconds,
		"body_pct": on_body / seconds,
		"react_pct": react_on / react_total if react_total > 0.0 else null,
		"steady_pct": (zone_on - react_on) / steady_total if steady_total > 0.0 else null,
		"avg_error_deg": error_sum / seconds,
		"best_streak": best_streak,
		"changes": brain.changes.filter(func(c: float) -> bool: return c <= end_time).size(),
		"bot_speed": max_speed,
	})


func _update_hud() -> void:
	var left := duration if not running and not done else maxf(run_start + duration - now(), 0.0)
	var seconds := maxf(total, 0.001)
	var bot_name: String = Defs.TRACK_SPEEDS[Settings.track_speed]["name"]
	var title := "TRACKING · %s %d u/s" % [bot_name, max_speed]
	var stats := "Huvud %d %% · Kropp %d %%" % [roundi(on_head / seconds * 100.0), roundi(on_body / seconds * 100.0)]
	hud.set_texts(title, UI.dec(left, 1) + " s", stats)
	hud.set_progress(1.0 - left / duration)
