extends RefCounted
## Shared constants and geometry helpers. Lengths are in meters; CS2 world units are inches.

const HeadModel = preload("res://scripts/head_model.gd")

const UNIT := 0.0254                 # meters per CS2 unit
const EYE_HEIGHT := 64.0 * UNIT      # standing eye height in CS2
const M_YAW := 0.022                 # CS2 m_yaw/m_pitch: degrees per mouse count at sensitivity 1
const CS_VFOV := 73.7397953          # CS2 shows 90° horizontally at 4:3, which is this vertical FOV
const TARGET_DIST := 12.0            # how far away targets float
const ROOM_MIN := Vector3(-40.0, 0.0, -50.0)   # room for targets 1500 units away, even on ultrawide
const ROOM_MAX := Vector3(40.0, 12.0, 24.0)

const MOVE_KEYS := {KEY_W: "w", KEY_A: "a", KEY_S: "s", KEY_D: "d"}

const TARGET_TYPES := ["CS2-huvud", "Klot"]
## Every mode runs for this long.
const RUN_SECONDS := 60.0
## The standard daily playlist: every mode PLAYLIST_REPS times in a row, in this order (Gridshot
## warms up). Settings.playlist holds the player's own rounds and order.
const PLAYLIST := ["grid", "flick", "micro", "track", "confirm", "tconfirm", "punch", "strafeaim", "strafe"]
const PLAYLIST_REPS := 3
const PLAYLIST_MAX_REPS := 5
## Targets never come lower than this above the floor (meters), however far away they are.
const MIN_TARGET_HEIGHT := 0.5
## Target distances in CS2 units for Flicks and Target Confirmation. Targets are real head size,
## so nearer ones look bigger.
const TARGET_RANGES := [
	{"name": "Blandat", "near": 250.0, "far": 1100.0},
	{"name": "Nära", "near": 250.0, "far": 500.0},
	{"name": "Medel", "near": 500.0, "far": 850.0},
	{"name": "Långt", "near": 850.0, "far": 1400.0},
]
const CONFIRM_LIMITS := [0.0, 1.5, 1.0, 0.75]
## How far from the crosshair Micro Adjustments targets appear, in degrees.
const MICRO_OFFSETS := [
	{"name": "Liten", "min": 0.5, "max": 1.5},
	{"name": "Mellan", "min": 1.0, "max": 3.0},
	{"name": "Stor", "min": 2.0, "max": 5.0},
]

## Max speed (units/s) and time between shots (s) are CS2 values. Movement inaccuracy (radians
## at full speed) is an approximation that only decides how far an inaccurate shot scatters.
const WEAPONS := [
	{"name": "AK-47", "speed": 215.0, "cycle": 0.1, "move_inacc": 0.175},
	{"name": "M4A1-S", "speed": 225.0, "cycle": 0.1, "move_inacc": 0.125},
	{"name": "M4A4", "speed": 225.0, "cycle": 0.09, "move_inacc": 0.14},
	{"name": "Desert Eagle", "speed": 230.0, "cycle": 0.225, "move_inacc": 0.3},
	{"name": "USP-S", "speed": 240.0, "cycle": 0.17, "move_inacc": 0.05},
	{"name": "Glock-18", "speed": 240.0, "cycle": 0.15, "move_inacc": 0.04},
]
const STAND_INACC := 0.004

## Tracking bots run at CS2 max player speeds: knife 250, pistols 240, M4 225, AK 215, AWP 200,
## and shift-walking at 52 % of the knife speed.
const TRACK_SPEEDS := [
	{"name": "Kniv", "speed": 250.0},
	{"name": "Pistol", "speed": 240.0},
	{"name": "M4", "speed": 225.0},
	{"name": "AK-47", "speed": 215.0},
	{"name": "AWP", "speed": 200.0},
	{"name": "Gå (shift)", "speed": 130.0},
]
const TRACK_DISTS := [400.0, 800.0, 1500.0]   # CS2 units, like distances on real maps
const TRACK_ZONES := [{"id": "head", "name": "Huvud"}, {"id": "body", "name": "Hela kroppen"}]
## Aim Punch: whether you wear kevlar when the enemy hits you.
const ARMOR := ["Utan kevlar", "Med kevlar"]


## Modes where the AK's recoil and inaccuracy change where shots land (Counter-strafe has its own
## weapons, tracking doesn't shoot, and Strafe Aim is about aiming while you move).
const RECOIL_MODES := ["grid", "flick", "micro", "confirm", "tconfirm", "punch"]


## The options a run used, so personal bests only compare runs with the same settings.
static func variant(mode: String, s: Object) -> String:
	var text := _options_text(mode, s)
	if s.ak_recoil and mode in RECOIL_MODES:
		text += " · AK-rekyl"
	return text


static func _options_text(mode: String, s: Object) -> String:
	match mode:
		"grid":
			return "%s · %s · 60 s" % [TARGET_TYPES[s.grid_target], TARGET_RANGES[s.grid_range]["name"]]
		"flick":
			return "%s · %s · 60 s" % [TARGET_TYPES[s.flick_target], TARGET_RANGES[s.flick_range]["name"]]
		"micro":
			return "%s · %s · %s · 60 s" % [TARGET_TYPES[s.micro_target], TARGET_RANGES[s.micro_range]["name"],
				micro_offset_text(MICRO_OFFSETS[s.micro_offset])]
		"confirm":
			var limit: float = CONFIRM_LIMITS[s.confirm_limit]
			var limit_text := "ingen tidsgräns" if limit <= 0.0 else str(limit).replace(".", ",") + " s per mål"
			return "%s · %s · 60 s · %s" % [TARGET_TYPES[s.confirm_target], TARGET_RANGES[s.confirm_range]["name"], limit_text]
		"strafe":
			return "%s · 60 s" % WEAPONS[s.strafe_weapon]["name"]
		"tconfirm":
			var bot: Dictionary = TRACK_SPEEDS[s.tconf_speed]
			return "%s %d u/s · %s · %s · 60 s" % [bot["name"], bot["speed"], TARGET_RANGES[s.tconf_range]["name"],
				str(TRACK_ZONES[s.tconf_zone]["name"]).to_lower()] + (" · crouch" if s.bot_crouch else "")
		"punch":
			return "%s · %s · %s · 60 s" % [ARMOR[s.punch_armor], TARGET_RANGES[s.punch_range]["name"],
				str(TRACK_ZONES[s.punch_zone]["name"]).to_lower()]
		"strafeaim":
			var own: Dictionary = TRACK_SPEEDS[s.saim_speed]
			return "%s · %s · %s %d u/s · 60 s" % [TARGET_TYPES[s.saim_target], TARGET_RANGES[s.saim_range]["name"],
				own["name"], own["speed"]]
		"track":
			var speed: Dictionary = TRACK_SPEEDS[s.track_speed]
			return "%s %d u/s · %d u · 60 s · %s" % [speed["name"], speed["speed"], TRACK_DISTS[s.track_dist],
				str(TRACK_ZONES[s.track_zone]["name"]).to_lower()] + (" · crouch" if s.bot_crouch else "")
	return ""


## "0,5–1,5°", "1–3°"
static func micro_offset_text(offset: Dictionary) -> String:
	var numbers: Array[String] = []
	for value: float in [offset["min"], offset["max"]]:
		numbers.append(str(roundi(value)) if is_equal_approx(value, roundf(value)) else str(value).replace(".", ","))
	return "%s–%s°" % numbers


static func dir_from_angles(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## Radius that makes a target at `dist` look `deg` degrees in radius.
static func radius_for(deg: float, dist: float = TARGET_DIST) -> float:
	return dist * tan(deg_to_rad(deg))


## The lowest pitch (degrees) a target `dist` meters away can have and still float at least
## MIN_TARGET_HEIGHT above the floor, seen from eyes at `eye_height`.
static func lowest_pitch(dist: float, eye_height: float) -> float:
	return rad_to_deg(asin(clampf((MIN_TARGET_HEIGHT - eye_height) / dist, -1.0, 1.0)))


## A random distance in meters within a range of CS2 units, spread evenly on a log scale so that
## near and far targets both come up often.
static func random_distance(span: Dictionary) -> float:
	var near: float = span["near"]
	var far: float = span["far"]
	return near * pow(far / near, randf()) * UNIT


## Distance along a normalized ray to a sphere, or -1 if it misses.
static func ray_sphere(origin: Vector3, dir: Vector3, centre: Vector3, radius: float) -> float:
	var oc := origin - centre
	var b := oc.dot(dir)
	var h := b * b - (oc.dot(oc) - radius * radius)
	if h < 0.0:
		return -1.0
	h = sqrt(h)
	var t := -b - h
	if t < 0.0:
		t = -b + h
	return t if t >= 0.0 else -1.0


## Distance along a normalized ray to a capsule between a and b, or -1 if it misses.
static func ray_capsule(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var ba := b - a
	var oa := origin - a
	var baba := ba.dot(ba)
	var bard := ba.dot(dir)
	var baoa := ba.dot(oa)
	var qa := baba - bard * bard
	var qb := baba * dir.dot(oa) - baoa * bard
	var qc := baba * oa.dot(oa) - baoa * baoa - radius * radius * baba
	var h := qb * qb - qa * qc
	if h >= 0.0 and qa > 1e-9:
		var t := (-qb - sqrt(h)) / qa
		var y := baoa + t * bard
		if t >= 0.0 and y > 0.0 and y < baba:
			return t
	var ta := ray_sphere(origin, dir, a, radius)
	var tb := ray_sphere(origin, dir, b, radius)
	if ta < 0.0:
		return tb
	if tb < 0.0:
		return ta
	return minf(ta, tb)


## Distance along a ray that starts inside an axis-aligned box to where it leaves the box.
static func ray_box_exit(origin: Vector3, dir: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t := INF
	for i in 3:
		if dir[i] > 1e-6:
			t = minf(t, (hi[i] - origin[i]) / dir[i])
		elif dir[i] < -1e-6:
			t = minf(t, (lo[i] - origin[i]) / dir[i])
	return t
