extends RefCounted
## CS2 ground movement: Source-style friction and acceleration in 64 Hz ticks. Key changes carry
## exact timestamps and split a tick into shorter steps, like CS2's sub-tick input. Holding "duck"
## crouches: the max speed falls to 34 % as the crouch goes down.

const TICK := 1.0 / 64.0
const ACCELERATE := 5.5            # sv_accelerate
const FRICTION := 5.2              # sv_friction
const STOP_SPEED := 80.0           # sv_stopspeed
const ACCURATE_FRACTION := 0.34    # at or below 34 % of max speed there is no movement inaccuracy
const DUCK_MODIFIER := 0.34        # crouched max speed as a fraction of standing (85 u/s with a knife)
const DUCK_SPEED := 8.0            # crouch amount per second: all the way down or up in 0.125 s
const KEEP_SECONDS := 4.0          # history kept for graphs and shot analysis

var max_speed := 215.0
var time := 0.0                    ## seconds; pos, vel and duck are valid at this time
var pos := Vector2.ZERO            ## units on the ground plane (x, z)
var vel := Vector2.ZERO            ## units per second
var duck := 0.0                    ## 0 standing, 1 fully crouched
var yaw := 0.0                     ## radians; W/A/S/D move relative to this view yaw
var keys := {"w": false, "a": false, "s": false, "d": false, "duck": false}
var bounds := Rect2(-1000.0, -1000.0, 2000.0, 2000.0)

## Velocity after every simulated step, as Vector3(time, vel.x, vel.y).
var samples: Array = []
## Every key change as [time, key, pressed], oldest first.
var key_log: Array = []
## Times when running into the edge of the bounds stopped you.
var wall_hits: Array = []

var _pending: Array = []
var _record := true


func threshold() -> float:
	return max_speed * ACCURATE_FRACTION


## The top speed right now: lower the further down the crouch is.
func speed_cap() -> float:
	return max_speed * lerpf(1.0, DUCK_MODIFIER, duck)


func reset(t: float) -> void:
	time = t
	pos = Vector2.ZERO
	vel = Vector2.ZERO
	duck = 0.0
	for k in keys:
		keys[k] = false
	samples = [Vector3(t, 0.0, 0.0)]
	key_log = []
	wall_hits = []
	_pending = []


## Queues a key change. Changes may be queued out of order; they are kept sorted by time.
func set_key(t: float, key: String, pressed: bool) -> void:
	_insert_sorted(_pending, [t, key, pressed])
	_insert_sorted(key_log, [t, key, pressed])


## Simulates every whole tick that has ended by time t.
func advance(t: float) -> void:
	while time + TICK <= t:
		_run_to(time + TICK)
	_trim()


## Position and velocity at time t, which may be inside the current tick. Nothing is committed.
func state_at(t: float) -> Dictionary:
	var c = _clone()
	c.advance(t)
	c._run_to(maxf(t, c.time))
	return {"pos": c.pos, "vel": c.vel, "duck": c.duck}


## Seconds from t until speed is at or below the accuracy threshold if the keys stay as they are
## (-1 if that doesn't happen within `horizon`), and whether speed is falling at t.
func until_accurate(t: float, horizon: float = 0.4) -> Dictionary:
	var start: float = (state_at(t)["vel"] as Vector2).length()
	var thr := threshold()
	if start <= thr:
		return {"seconds": 0.0, "falling": false}
	var c = _clone()
	c.advance(t)
	var prev_t := t
	var prev_speed := start
	var falling := false
	var first := true
	while c.time < t + horizon:
		c._run_to(c.time + TICK)
		var speed: float = c.vel.length()
		if first:
			falling = speed < start
			first = false
		if speed <= thr:
			# Speed changes linearly within a step, so the crossing can be interpolated.
			var crossing := lerpf(prev_t, c.time, (prev_speed - thr) / (prev_speed - speed))
			return {"seconds": crossing - t, "falling": falling}
		prev_t = c.time
		prev_speed = speed
	return {"seconds": -1.0, "falling": falling}


## When speed last fell to `thr` before t (speed is linear between samples), or -1; `speed_now` is
## the speed at t.
func became_accurate(t: float, thr: float, speed_now: float) -> float:
	var later := Vector2(t, speed_now)
	for i in range(samples.size() - 1, -1, -1):
		var s: Vector3 = samples[i]
		if s.x > t:
			continue
		var speed := Vector2(s.y, s.z).length()
		if speed > thr:
			return lerpf(s.x, later.x, (speed - thr) / (speed - later.y))
		later = Vector2(s.x, speed)
	return -1.0


## The highest speed between `from` and `to`.
func peak_speed(from: float, to: float) -> float:
	var peak := 0.0
	for s: Vector3 in samples:
		if s.x >= from and s.x <= to:
			peak = maxf(peak, Vector2(s.y, s.z).length())
	return peak


## Time of the last change of key to `pressed` at or before t, or -1.
func last_change(key: String, pressed: bool, t: float) -> float:
	for i in range(key_log.size() - 1, -1, -1):
		var e: Array = key_log[i]
		if e[0] <= t and e[1] == key and e[2] == pressed:
			return e[0]
	return -1.0


## Whether key was held down at time t.
func held_at(key: String, t: float) -> bool:
	for i in range(key_log.size() - 1, -1, -1):
		var e: Array = key_log[i]
		if e[0] <= t and e[1] == key:
			return e[2]
	return false


## The first press of key between from and to, or -1.
func first_press(key: String, from: float, to: float) -> float:
	for e: Array in key_log:
		if e[1] == key and e[2] and e[0] >= from and e[0] <= to:
			return e[0]
	return -1.0


func _run_to(end: float) -> void:
	while not _pending.is_empty() and _pending[0][0] < end:
		var change: Array = _pending.pop_front()
		_step(maxf(change[0], time) - time)
		keys[change[1]] = change[2]
	_step(end - time)


func _step(dt: float) -> void:
	if dt <= 0.0:
		return
	duck = move_toward(duck, 1.0 if keys["duck"] else 0.0, DUCK_SPEED * dt)
	var speed := vel.length()
	if speed > 0.1:
		var control := maxf(speed, STOP_SPEED)
		vel *= maxf(speed - control * FRICTION * dt, 0.0) / speed
	var wish := _wish_dir()
	if wish != Vector2.ZERO:
		# Above the cap (crouching while running) nothing is added and friction slows you down.
		var cap := speed_cap()
		var add := cap - vel.dot(wish)
		if add > 0.0:
			vel += wish * minf(ACCELERATE * cap * dt, add)
	elif vel.length() < 1.0:
		vel = Vector2.ZERO
	pos += vel * dt
	var before_clamp := vel.length()
	_clamp()
	time += dt
	if _record:
		samples.append(Vector3(time, vel.x, vel.y))
		if before_clamp > threshold() and vel.length() <= threshold():
			wall_hits.append(time)


func _wish_dir() -> Vector2:
	var forward_move := float(keys["w"]) - float(keys["s"])
	var side_move := float(keys["d"]) - float(keys["a"])
	if forward_move == 0.0 and side_move == 0.0:
		return Vector2.ZERO
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return (forward * forward_move + right * side_move).normalized()


func _clamp() -> void:
	if pos.x < bounds.position.x or pos.x > bounds.end.x:
		pos.x = clampf(pos.x, bounds.position.x, bounds.end.x)
		vel.x = 0.0
	if pos.y < bounds.position.y or pos.y > bounds.end.y:
		pos.y = clampf(pos.y, bounds.position.y, bounds.end.y)
		vel.y = 0.0


static func _insert_sorted(list: Array, change: Array) -> void:
	var i := list.size()
	while i > 0 and list[i - 1][0] > change[0]:
		i -= 1
	list.insert(i, change)


func _trim() -> void:
	if samples.size() < 4096:
		return
	var cutoff := time - KEEP_SECONDS
	var first := 0
	while first < samples.size() and samples[first].x < cutoff:
		first += 1
	samples = samples.slice(first)
	key_log = key_log.filter(func(e: Array) -> bool: return e[0] >= cutoff)
	wall_hits = wall_hits.filter(func(w: float) -> bool: return w >= cutoff)


func _clone():
	var c = get_script().new()
	c.max_speed = max_speed
	c.time = time
	c.pos = pos
	c.vel = vel
	c.duck = duck
	c.yaw = yaw
	c.keys = keys.duplicate()
	c.bounds = bounds
	c._pending = _pending.duplicate(true)
	c._record = false
	return c
