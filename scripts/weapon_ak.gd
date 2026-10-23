extends RefCounted
## CS2's AK-47 when it fires, with its own values from CS2 (scripts/weapons.vdata) and the engine's
## recoil system: a recoil pattern made from the AK's recoil seed, an aim punch that kicks with every
## shot and decays (bullets follow twice the punch, the view 45 % of that), and inaccuracy that
## grows with each shot and recovers. Angles are in degrees; inaccuracy and spread in radians.

# CS2's AK-47.
const CYCLE := 0.1
const SPREAD := 0.0006
const INACCURACY_STAND := 0.00641
const INACCURACY_FIRE := 0.0078
const RECOVERY_STAND := 0.368
const RECOVERY_STAND_FINAL := 0.506
const RECOVERY_START_BULLET := 2
const RECOVERY_END_BULLET := 5
const RECOIL_ANGLE := 0.0
const RECOIL_ANGLE_VARIANCE := 70.0
const RECOIL_MAGNITUDE := 30.0
const RECOIL_MAGNITUDE_VARIANCE := 0.0
const RECOIL_SEED := 223
const TRACER_FREQUENCY := 3

# The engine's recoil settings (their console defaults).
const RECOIL_SCALE := 2.0            # weapon_recoil_scale: bullets go where twice the aim punch points
const VIEW_TRACKING := 0.45          # view_recoil_tracking: the view follows this much of that
const RECOIL_VARIANCE := 0.55        # weapon_recoil_variance: how far each kick turns from the last
const SUPPRESSION_SHOTS := 4         # weapon_recoil_suppression_shots
const SUPPRESSION_FACTOR := 0.75     # weapon_recoil_suppression_factor
const DECAY_EXP := 8.0               # weapon_recoil_decay2_exp
const DECAY_LIN := 18.0              # weapon_recoil_decay2_lin
const VEL_DECAY := 4.5               # weapon_recoil_vel_decay
const INDEX_DECAY := 2.0             # weapon_recoil_decay_coefficient
const INDEX_DECAY_THRESHOLD := 1.1   # the index only decays once you stop firing
## A hit from an enemy keeps pushing the punch on for a moment, at this many times its jump per second.
const HIT_PUSH := 15.0
const TABLE_SIZE := 64
const TICK := 1.0 / 64.0

## [angle, magnitude] per shot.
static var _table: Array = []

var punch := Vector2.ZERO            ## aim punch (pitch up, yaw left), degrees
var punch_vel := Vector2.ZERO
var recoil_index := 0.0
var penalty := INACCURACY_STAND      ## current inaccuracy, radians
var shots := 0
var time := 0.0
var next_fire := -INF
var last_shot := -INF
var rng := RandomNumberGenerator.new()


func reset(t: float) -> void:
	punch = Vector2.ZERO
	punch_vel = Vector2.ZERO
	recoil_index = 0.0
	penalty = INACCURACY_STAND
	shots = 0
	time = t
	next_fire = -INF
	last_shot = -INF


func can_fire(t: float) -> bool:
	return t >= next_fire


## Fires at time t. Returns where the bullet goes relative to where you aim: "punch" (degrees,
## pitch up and yaw left) and "spread" (radians, right and up), and whether it shows a tracer.
func fire(t: float) -> Dictionary:
	advance(t)
	# Firing again right on cue keeps the AK's rhythm; a later shot starts a new one.
	next_fire = next_fire + CYCLE if t - next_fire < CYCLE else t + CYCLE
	var theta := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(0.0, penalty)
	var theta2 := rng.randf_range(0.0, TAU)
	var radius2 := rng.randf_range(0.0, SPREAD)
	var shot := {
		"punch": punch * RECOIL_SCALE,
		"spread": Vector2(cos(theta), sin(theta)) * radius + Vector2(cos(theta2), sin(theta2)) * radius2,
		"tracer": shots % TRACER_FREQUENCY == 0,
	}
	# The kick from this shot moves the following ones; a positive recoil angle kicks to the left.
	var kick: Array = recoil_table()[int(recoil_index) % TABLE_SIZE]
	var angle := deg_to_rad(kick[0])
	punch_vel += Vector2(cos(angle), sin(angle)) * float(kick[1])
	recoil_index += 1.0
	penalty += INACCURACY_FIRE
	shots += 1
	last_shot = t
	return shot


## The view's share of the kick right now (pitch up, yaw left), degrees.
func view_punch(t: float) -> Vector2:
	advance(t)
	return punch * RECOIL_SCALE * VIEW_TRACKING


## Where bullets go right now relative to where you aim, from the punch alone (pitch up, yaw left),
## degrees: for shooting without the AK's own recoil and spread.
func aim_punch(t: float) -> Vector2:
	advance(t)
	return punch * RECOIL_SCALE


## A hit from an enemy punches your aim like CS2's aim punch: it jumps by `kick` (pitch up, yaw left,
## degrees), is pushed on the same way for a moment, then settles like the recoil does. Bullets fired
## right after the hit go high, twice as far as the punch.
func take_hit(t: float, kick: Vector2) -> void:
	advance(t)
	punch += kick
	punch_vel += kick * HIT_PUSH


## Runs the decays tick by tick up to time t.
func advance(t: float) -> void:
	while time + TICK <= t:
		time += TICK
		_tick()


func _tick() -> void:
	var length := punch.length()
	if length > 0.0:
		var shorter := maxf(length - length * DECAY_EXP * TICK - DECAY_LIN * TICK, 0.0)
		punch *= shorter / length
	punch += punch_vel * TICK * 0.5
	punch_vel *= exp(-VEL_DECAY * TICK)
	punch += punch_vel * TICK * 0.5
	if time > last_shot + CYCLE * INDEX_DECAY_THRESHOLD:
		recoil_index *= exp(-INDEX_DECAY * TICK)
	var recovery := RECOVERY_STAND
	if recoil_index > RECOVERY_START_BULLET:
		var weight := clampf((recoil_index - RECOVERY_START_BULLET) / (RECOVERY_END_BULLET - RECOVERY_START_BULLET), 0.0, 1.0)
		recovery = lerpf(RECOVERY_STAND, RECOVERY_STAND_FINAL, weight)
	# The extra inaccuracy from firing falls to a tenth over the recovery time.
	penalty = lerpf(INACCURACY_STAND, penalty, exp(-TICK * log(10.0) / recovery))


## The AK's recoil pattern: an angle and size per shot, made from its recoil seed with the
## engine's random stream. Each angle turns part of the way from the last, and the first few kicks
## are softer.
static func recoil_table() -> Array:
	if not _table.is_empty():
		return _table
	var random := UniformRandom.new(RECOIL_SEED)
	var angle := 0.0
	var magnitude := 0.0
	for j in TABLE_SIZE:
		var new_angle := RECOIL_ANGLE + random.randf_range(-RECOIL_ANGLE_VARIANCE, RECOIL_ANGLE_VARIANCE)
		var new_magnitude := RECOIL_MAGNITUDE + random.randf_range(-RECOIL_MAGNITUDE_VARIANCE, RECOIL_MAGNITUDE_VARIANCE)
		if j > 0:
			angle = lerpf(angle, new_angle, RECOIL_VARIANCE)
			magnitude = lerpf(magnitude, new_magnitude, RECOIL_VARIANCE)
		else:
			angle = new_angle
			magnitude = new_magnitude
		if j < SUPPRESSION_SHOTS:
			magnitude *= lerpf(SUPPRESSION_FACTOR, 1.0, float(j) / SUPPRESSION_SHOTS)
		_table.append([angle, magnitude])
	return _table


## The Source engine's uniform random stream (Park-Miller with a Bays-Durham shuffle), so a seed
## gives the same numbers as in the game.
class UniformRandom:
	const NTAB := 32
	const IA := 16807
	const IM := 2147483647
	const IQ := 127773
	const IR := 2836
	const NDIV := 1 + (IM - 1) / NTAB
	const AM := 1.0 / IM
	const RNMX := 1.0 - 1.2e-7

	var _idum := 0
	var _iy := 0
	var _iv: Array[int] = []

	func _init(seed_value: int) -> void:
		_iv.resize(NTAB)
		_idum = seed_value if seed_value < 0 else -seed_value
		_iy = 0

	func randf_range(low: float, high: float) -> float:
		var fl := AM * _next()
		if fl > RNMX:
			fl = RNMX
		return fl * (high - low) + low

	func _next() -> int:
		var k := 0
		if _idum <= 0 or _iy == 0:
			_idum = 1 if -_idum < 1 else -_idum
			for j in range(NTAB + 7, -1, -1):
				k = _idum / IQ
				_idum = IA * (_idum - k * IQ) - IR * k
				if _idum < 0:
					_idum += IM
				if j < NTAB:
					_iv[j] = _idum
			_iy = _iv[0]
		k = _idum / IQ
		_idum = IA * (_idum - k * IQ) - IR * k
		if _idum < 0:
			_idum += IM
		var j := _iy / NDIV
		_iy = _iv[j]
		_iv[j] = _idum
		return _iy
