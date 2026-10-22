extends RefCounted
## Decides how a tracking bot moves: strafes of different lengths, ADAD reversals, counter-strafed
## stops and slides, staying inside its lane, and with `crouch` on, crouches now and then. It only
## presses keys; the movement itself comes from movement_sim.gd, so speed, acceleration, stopping
## and crouching are the same as for a CS2 player.

var sim: RefCounted
var rng := RandomNumberGenerator.new()
## Whether the bot crouches: mostly when it stops, like a player stopping to shoot, and sometimes
## for a moment in the middle of ADAD.
var crouch := false
var plan_end := 0.0
## Times when the bot starts moving in a new direction.
var changes: Array = []
var _dir := 1


func start(t: float) -> void:
	plan_end = t


## Plans moves up to `lookahead` seconds past t, so key presses are queued before they happen.
func update(t: float, lookahead: float = 0.05) -> void:
	while plan_end <= t + lookahead:
		_plan_next()


func _plan_next() -> void:
	var s := plan_end
	var state: Dictionary = sim.state_at(s)
	var pos: Vector2 = state["pos"]
	var vel: Vector2 = state["vel"]
	var max_speed: float = sim.max_speed
	var bounds: Rect2 = sim.bounds
	var half := bounds.size.x / 2.0
	var x := pos.x - (bounds.position.x + half)

	# Mostly switch direction, and always head back towards the middle near the edges.
	var dir := -_dir if rng.randf() < 0.6 else _dir
	if x > half * 0.5:
		dir = -1
	elif x < -half * 0.5:
		dir = 1
	# Some short jiggles, but mostly strafes long enough to reach full speed (about 0.55 s).
	var hold := rng.randf_range(0.12, 0.3) if rng.randf() < 0.3 else rng.randf_range(0.45, 1.1)
	var room := half - x * dir
	hold = clampf(hold, 0.1, maxf(room / max_speed - 0.15, 0.1))

	var key := "d" if dir > 0 else "a"
	var opposite := "a" if dir > 0 else "d"
	if vel.length() < 30.0 or signf(vel.x) != dir:
		changes.append(s)
	_dir = dir
	sim.set_key(s, key, true)
	var end := s + hold
	sim.set_key(end, key, false)
	var r := rng.randf()
	if r < 0.35:
		# ADAD: straight into the next strafe, now and then with a quick crouch on the way.
		if crouch and rng.randf() < 0.15:
			var down := rng.randf_range(0.15, 0.35)
			sim.set_key(maxf(s, end - down * 0.5), "duck", true)
			sim.set_key(end + down * 0.5, "duck", false)
		plan_end = end
	elif r < 0.75:
		# Counter-strafe to a stop, then hold still for a moment; often crouched, like when stopping
		# to shoot.
		var tap := rng.randf_range(0.06, 0.085)
		sim.set_key(end, opposite, true)
		sim.set_key(end + tap, opposite, false)
		var still := rng.randf_range(0.05, 0.45)
		if crouch and rng.randf() < 0.4:
			still = rng.randf_range(0.35, 0.9)
			sim.set_key(end + tap * 0.5, "duck", true)
			sim.set_key(end + tap + still, "duck", false)
		plan_end = end + tap + still
	else:
		# Let go and slide to a stop.
		plan_end = end + rng.randf_range(0.25, 0.6)
