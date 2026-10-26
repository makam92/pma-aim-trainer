extends Node
## Base for the training modes. main.gd calls the hooks; a mode emits `finished` when a run ends.

signal finished(result: Dictionary)

const Defs = preload("res://scripts/defs.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

var main: Node
var player: Node3D
var hud: Control
## Set by shoot() when the shot hit a target, so no bullet hole goes on the wall behind it.
var shot_hit := false
## Where the bullet went: the direction shoot() got, unless the mode sent it elsewhere (moving
## inaccuracy), so its hole lands where it really hit.
var shot_dir := Vector3.FORWARD


func setup(host: Node) -> void:
	main = host
	player = host.player
	hud = host.hud


## Sets the run up. With the countdown on, the room and the first targets can be seen during it, but
## nothing moves, no shots reach the mode and the clock waits for go().
func begin() -> void:
	pass


## The countdown is over (or off): the run starts now and its clock runs from here.
func go() -> void:
	pass


func shoot(_origin: Vector3, _dir: Vector3) -> void:
	pass


## Whether the gun fires at all right now; when it doesn't, there's no shot, sound or bullet.
func can_shoot() -> bool:
	return true


## Where a bullet along `dir` hits a wall the mode built: {"dist", "normal"}, or {} when it goes on
## to the room's own walls.
func surface(_origin: Vector3, _dir: Vector3) -> Dictionary:
	return {}


func key_event(_key: String, _pressed: bool, _t: float) -> void:
	pass


func on_resume() -> void:
	pass


## Game time in seconds. It stands still while the game is paused.
func now() -> float:
	return main.game_time()


## The time a hit took, under the crosshair, unless that's turned off in the settings.
func flash_time(seconds: float) -> void:
	if Settings.hit_times:
		hud.flash(UI.ms(seconds * 1000.0), UI.GOOD)


## Mean of a list of numbers, or of `key` in a list of dictionaries. Null for an empty list.
static func average(items: Array, key: String = "") -> Variant:
	if items.is_empty():
		return null
	var sum := 0.0
	for item: Variant in items:
		sum += float(item[key] if key != "" else item)
	return sum / items.size()


## Seconds in milliseconds, keeping null.
static func to_ms(seconds: Variant) -> Variant:
	return null if seconds == null else float(seconds) * 1000.0


## How far the fast first part of a flick went, from `start` towards `goal` (yaw, pitch in degrees),
## judged from aim samples taken during it (Vector3(time, yaw, pitch)): 1.0 is spot on, above 1 an
## overflick and below 1 an underflick. Null when the flick was too short or slow to tell.
static func flick_ratio(samples: Array, start: Vector2, goal_angles: Vector2) -> Variant:
	var goal := goal_angles - start
	var dist := goal.length()
	if dist < 8.0 or samples.size() < 4:
		return null
	var speeds: Array[float] = []
	var peak := 0.0
	for i in range(1, samples.size()):
		var a: Vector3 = samples[i - 1]
		var b: Vector3 = samples[i]
		var speed := Vector2(b.y - a.y, b.z - a.z).length() / maxf(b.x - a.x, 0.0001)
		speeds.append(speed)
		peak = maxf(peak, speed)
	if peak < 60.0:
		return null
	var end := samples.size() - 1
	for i in range(speeds.find(peak), speeds.size()):
		if speeds[i] < peak * 0.12:
			end = i
			break
	var stop: Vector3 = samples[end]
	var reached := Vector2(stop.y, stop.z) - start
	return reached.dot(goal) / (dist * dist)


## "exakt", "9 % för lång", "6 % för kort" for an average flick ratio minus 1.
static func flick_length_text(bias: float) -> String:
	var pct := roundi(bias * 100.0)
	if pct > 0:
		return "%d %% för lång" % pct
	if pct < 0:
		return "%d %% för kort" % -pct
	return "exakt"


## A tip when flicks keep going past or stopping short, or "".
static func flick_length_note(bias: float) -> String:
	var pct := roundi(bias * 100.0)
	if pct >= 8:
		return "Du flickar i snitt %d %% förbi målet. Händer det hela tiden kan sensen vara lite hög." % pct
	if pct <= -8:
		return "Du stannar i snitt %d %% före målet. Händer det hela tiden kan sensen vara lite låg." % -pct
	return ""


## Lines on the floor along both edges of the lane you strafe in, `half_width` meters to each side.
func add_lane(half_width: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(UI.ACCENT, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for x: float in [-half_width, half_width]:
		var line := BoxMesh.new()
		line.size = Vector3(0.05, 0.01, 4.0)
		var inst := MeshInstance3D.new()
		inst.mesh = line
		inst.material_override = mat
		inst.position = Vector3(x, 0.006, 0.0)
		add_child(inst)
