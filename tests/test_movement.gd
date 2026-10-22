extends SceneTree
## Headless check of the movement model:
##   godot --headless --path . --script res://tests/test_movement.gd

const Sim = preload("res://scripts/movement_sim.gd")
const Brain = preload("res://scripts/bot_brain.gd")
const Defs = preload("res://scripts/defs.gd")


func _init() -> void:
	var failures := 0
	for weapon: Dictionary in Defs.WEAPONS:
		var max_speed: float = weapon["speed"]
		var top := _top_speed(max_speed)
		var counter := _stop_ms(max_speed, "counter")
		var release := _stop_ms(max_speed, "release")
		var both := _stop_ms(max_speed, "both")
		print("%-13s max %3d u/s (nått %5.1f)  träffsäker <= %5.1f  counter %3d ms  släpp %3d ms  A+D %3d ms" % [
			weapon["name"], max_speed, top, max_speed * Sim.ACCURATE_FRACTION, counter, release, both])
		if absf(top - max_speed) > 0.5:
			failures += 1
		if counter < 40 or counter > 110:
			failures += 1
		if release < counter * 2:
			failures += 1
		if absi(both - release) > 2:
			failures += 1

	# A shot evaluated between ticks must see the speed at that exact instant.
	var sim = Sim.new()
	sim.reset(0.0)
	sim.set_key(0.0, "d", true)
	sim.advance(1.0)
	sim.set_key(1.003, "d", false)
	sim.set_key(1.003, "a", true)
	var mid: float = (sim.state_at(1.01)["vel"] as Vector2).length()
	var tick_end: float = (sim.state_at(1.0 + Sim.TICK)["vel"] as Vector2).length()
	print("sub-tick: fart vid 1.010 s = %.1f, vid tickens slut = %.1f" % [mid, tick_end])
	if not (mid < 215.0 and mid > tick_end):
		failures += 1

	failures += _check_crouch()
	failures += _check_bot()

	print("OK" if failures == 0 else "FEL: %d" % failures)
	quit(failures)


## Crouch-walking with a knife tops out at 34 % (85 u/s), the crouch takes 0.125 s, and crouching
## while running slows you down by friction instead of stopping you dead.
func _check_crouch() -> int:
	var sim = Sim.new()
	sim.max_speed = 250.0
	sim.reset(0.0)
	sim.set_key(0.0, "duck", true)
	sim.set_key(0.0, "d", true)
	sim.advance(1.0)
	var crouch_top: float = (sim.vel as Vector2).length()
	var down_at := -1.0
	var probe = Sim.new()
	probe.reset(0.0)
	probe.set_key(0.0, "duck", true)
	for i in 40:
		var t := i * 0.005
		if probe.state_at(t)["duck"] >= 1.0:
			down_at = t
			break
	var run = Sim.new()
	run.max_speed = 250.0
	run.reset(0.0)
	run.set_key(0.0, "d", true)
	run.advance(1.0)
	run.set_key(1.0, "duck", true)
	var after_100ms: float = (run.state_at(1.1)["vel"] as Vector2).length()
	var after_500ms: float = (run.state_at(1.5)["vel"] as Vector2).length()
	print("crouch: toppfart %.1f u/s, nere efter %.3f s, springer 250 och croucher: %.0f u/s efter 0,1 s, %.0f efter 0,5 s" % [
		crouch_top, down_at, after_100ms, after_500ms])
	var failures := 0
	if absf(crouch_top - 85.0) > 0.5:
		failures += 1
	if absf(down_at - 0.125) > 0.006:
		failures += 1
	# Friction alone takes 250 down to about 145 in 0.1 s; an instant stop would be 85 or less.
	if not (after_100ms > 120.0 and absf(after_500ms - 85.0) < 1.0):
		failures += 1
	return failures


## A tracking bot planned for 60 s must reach the CS2 max speed and stay inside its lane.
func _check_bot() -> int:
	var bot = Sim.new()
	bot.max_speed = 250.0
	var half := 15.0 * tan(deg_to_rad(25.0)) / Defs.UNIT
	bot.bounds = Rect2(-half, -1.0, half * 2.0, 2.0)
	bot.reset(0.0)
	var brain = Brain.new()
	brain.sim = bot
	brain.rng.seed = 42
	brain.crouch = true
	brain.start(0.0)
	var top := 0.0
	var widest := 0.0
	var full_speed := 0.0
	var crouched := 0.0
	var crouch_top := 0.0
	var crouches := 0
	var was_down := false
	var step := 1.0 / 240.0
	var t := 0.0
	while t < 60.0:
		t += step
		brain.update(t)
		bot.advance(t)
		var state: Dictionary = bot.state_at(t)
		var speed := (state["vel"] as Vector2).length()
		top = maxf(top, speed)
		widest = maxf(widest, absf((state["pos"] as Vector2).x))
		if speed >= 249.0:
			full_speed += step
		var down: bool = state["duck"] >= 1.0
		if down:
			crouched += step
			# Allow a short slide: speed only falls to 85 u/s by friction after the crouch is down.
			if bot.held_at("duck", t - 0.3):
				crouch_top = maxf(crouch_top, speed)
		if down and not was_down:
			crouches += 1
		was_down = down
	print("bot: toppfart %.1f u/s, full fart %.0f %% av tiden, längst ut %.0f av %.0f u, %d riktningsbyten, %d väggstopp" % [
		top, full_speed / 60.0 * 100.0, widest, half, brain.changes.size(), bot.wall_hits.size()])
	print("bot: %d crouchar, crouchad %.0f %% av tiden, toppfart efter 0,3 s nere %.1f u/s" % [
		crouches, crouched / 60.0 * 100.0, crouch_top])
	var failures := 0
	if top > 250.01 or top < 249.0:
		failures += 1
	if widest > half + 0.01:
		failures += 1
	if brain.changes.size() < 40:
		failures += 1
	if crouches < 10 or crouched / 60.0 > 0.4 or crouch_top > 85.5:
		failures += 1
	return failures


func _top_speed(max_speed: float) -> float:
	var sim = Sim.new()
	sim.max_speed = max_speed
	sim.reset(0.0)
	sim.set_key(0.0, "d", true)
	sim.advance(1.0)
	return (sim.vel as Vector2).length()


## Runs right at full speed, stops at t = 1 s and returns the milliseconds until accurate.
func _stop_ms(max_speed: float, how: String) -> int:
	var sim = Sim.new()
	sim.max_speed = max_speed
	sim.reset(0.0)
	sim.set_key(0.0, "d", true)
	sim.advance(1.0)
	match how:
		"counter":
			sim.set_key(1.0, "d", false)
			sim.set_key(1.0, "a", true)
		"release":
			sim.set_key(1.0, "d", false)
		"both":
			sim.set_key(1.0, "a", true)
	var r: Dictionary = sim.until_accurate(1.0, 1.0)
	return roundi(float(r["seconds"]) * 1000.0)
