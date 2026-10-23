extends "res://scripts/modes/mode_base.gd"
## Flicks: hold the centre, a target appears at a random angle and distance, flick and shoot.
## Hit as many as you can in 60 seconds; the clock starts with the first target.

const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")

enum Phase { CENTER, DELAY, TARGET, DONE }

const CENTER_TOLERANCE := 1.5          # degrees from the centre that count as holding the angle
const CENTER_HOLD := 0.15              # seconds to hold before a target can appear
const DELAY := Vector2(0.25, 0.75)     # random wait so the timing can't be predicted
const TIMEOUT := 1.5
const YAW_RANGE := Vector2(12.0, 65.0)
const PITCH_RANGE := 7.0
const SAMPLE_INTERVAL := 0.004

var duration := 60.0
var phase := Phase.CENTER
var shown := 0
var hits := 0
var misses := 0
var timeouts := 0
var times: Array = []
var ratios: Array = []

var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _target: Target = null
var _target_angles := Vector2.ZERO
var _start_angles := Vector2.ZERO
var _phase_time := 0.0
var _run_start := -1.0
var _hold := 0.0
var _delay := 0.0
var _distance := 0.0
var _samples: Array = []    # Vector3(time, yaw, pitch) while a target is up


func begin() -> void:
	duration = Defs.RUN_SECONDS
	_build_marker()
	_set_phase(Phase.CENTER)
	hud.message("Håll siktet i ringen", UI.DIM)
	_update_hud()


func _process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	var t := now()
	if _run_start >= 0.0 and t - _run_start >= duration:
		_finish()
		return
	var centred := _angle_to(Vector2.ZERO) <= CENTER_TOLERANCE
	match phase:
		Phase.CENTER:
			_hold = _hold + delta if centred else 0.0
			_marker_mat.albedo_color = Color(UI.GOOD, 0.95) if centred else Color(1.0, 1.0, 1.0, 0.8)
			if _hold >= CENTER_HOLD:
				_delay = randf_range(DELAY.x, DELAY.y)
				_set_phase(Phase.DELAY)
		Phase.DELAY:
			if not centred:
				_set_phase(Phase.CENTER)
			elif t - _phase_time >= _delay:
				_spawn()
		Phase.TARGET:
			var last: Vector3 = _samples[-1]
			if t - last.x >= SAMPLE_INTERVAL:
				_samples.append(Vector3(t, player.yaw, player.pitch))
			if t - _phase_time >= TIMEOUT:
				timeouts += 1
				_target.queue_free()
				_target = null
				Sfx.play("miss")
				hud.flash("För långsamt", UI.BAD)
				_set_phase(Phase.CENTER)
	_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if phase != Phase.TARGET or _target == null:
		return
	if _target.hit_distance(origin, dir) >= 0.0:
		var dt := now() - _phase_time
		hits += 1
		shot_hit = true
		times.append(dt)
		_samples.append(Vector3(now(), player.yaw, player.pitch))
		_analyse_flick()
		Sfx.play("hit")
		hud.flash("%d ms" % roundi(dt * 1000.0), UI.GOOD)
		_target.pop()
		_target = null
		_set_phase(Phase.CENTER)
	else:
		misses += 1
		Sfx.play("miss")
		hud.flash("Miss", UI.BAD)
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var rows := [
		["Träffsäkerhet", "%d %%" % roundi(float(r.get("accuracy", 0.0)) * 100.0)],
		["Snittid till träff", UI.ms(r.get("avg_ms"))],
		["Mål som dök upp", str(int(r.get("targets", 0)))],
		["För långsamt", str(int(r.get("timeouts", 0)))],
	]
	var note := ""
	var bias: Variant = r.get("flick_bias")
	if bias != null:
		var pct := roundi(float(bias) * 100.0)
		var text := "exakt"
		if pct > 0:
			text = "%d %% för lång" % pct
		elif pct < 0:
			text = "%d %% för kort" % -pct
		rows.append(["Flicklängd", text])
		if pct >= 8:
			note = "Du flickar i snitt %d %% förbi målet. Händer det hela tiden kan sensen vara lite hög." % pct
		elif pct <= -8:
			note = "Du stannar i snitt %d %% före målet. Händer det hela tiden kan sensen vara lite låg." % -pct
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


func _set_phase(p: Phase) -> void:
	phase = p
	_phase_time = now()
	if p == Phase.CENTER:
		_hold = 0.0
		_marker.visible = true


func _spawn() -> void:
	# Keep targets on screen: at 16:9 CS2 shows about 53° to each side, at 5:4 about 43°.
	var screen := Vector2(main.game_view.size)
	var half_fov := rad_to_deg(atan(tan(deg_to_rad(Defs.CS_VFOV / 2.0)) * screen.x / screen.y))
	var max_yaw := minf(YAW_RANGE.y, half_fov - 5.0)
	var yaw := randf_range(YAW_RANGE.x, max_yaw) * (1.0 if randf() < 0.5 else -1.0)
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.flick_range])
	var eye: Vector3 = player.eye_position()
	# Far targets can't go as low, or they'd end up under the floor.
	var pitch := randf_range(maxf(-PITCH_RANGE, Defs.lowest_pitch(dist, eye.y)), PITCH_RANGE)
	_target_angles = Vector2(yaw, pitch)
	_target = Target.new()
	if Settings.flick_target == 0:
		_target.setup_head(randi() % 2)
	else:
		_target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	_distance = dist
	_target.position = eye + Defs.dir_from_angles(yaw, pitch) * dist
	_target.rotation.y = deg_to_rad(yaw)
	add_child(_target)
	shown += 1
	if _run_start < 0.0:
		_run_start = now()
	_start_angles = Vector2(player.yaw, player.pitch)
	_samples = [Vector3(now(), player.yaw, player.pitch)]
	_marker.visible = false
	hud.message("")
	_set_phase(Phase.TARGET)


## Where the fast first part of the flick stopped, relative to the target: 1.0 is spot on,
## above 1 is an overflick and below 1 an underflick.
func _analyse_flick() -> void:
	var goal := _target_angles - _start_angles
	var dist := goal.length()
	if dist < 8.0 or _samples.size() < 4:
		return
	var speeds: Array[float] = []
	var peak := 0.0
	for i in range(1, _samples.size()):
		var a: Vector3 = _samples[i - 1]
		var b: Vector3 = _samples[i]
		var speed := Vector2(b.y - a.y, b.z - a.z).length() / maxf(b.x - a.x, 0.0001)
		speeds.append(speed)
		peak = maxf(peak, speed)
	if peak < 60.0:
		return
	var end := _samples.size() - 1
	for i in range(speeds.find(peak), speeds.size()):
		if speeds[i] < peak * 0.12:
			end = i
			break
	var stop: Vector3 = _samples[end]
	var reached := Vector2(stop.y, stop.z) - _start_angles
	ratios.append(reached.dot(goal) / (dist * dist))


func _finish() -> void:
	phase = Phase.DONE
	_marker.visible = false
	if _target:
		_target.queue_free()
		_target = null
	Sfx.play("done")
	_update_hud()
	var bias: Variant = average(ratios)
	var avg: Variant = average(times)
	finished.emit({
		"variant": Defs.variant("flick", Settings),
		"score": hits,
		"targets": shown,
		"hits": hits,
		"misses": misses,
		"timeouts": timeouts,
		"accuracy": float(hits) / maxi(hits + misses, 1),
		"avg_ms": avg * 1000.0 if avg != null else null,
		"flick_bias": bias - 1.0 if bias != null else null,
	})


func _update_hud() -> void:
	var left := duration
	if phase == Phase.DONE:
		left = 0.0
	elif _run_start >= 0.0:
		left = maxf(_run_start + duration - now(), 0.0)
	var shots := hits + misses
	var accuracy := 100 if shots == 0 else roundi(100.0 * hits / shots)
	var avg: Variant = average(times)
	var stats := "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, UI.ms(avg * 1000.0 if avg != null else null)]
	var info := "%d träffar" % hits
	if phase == Phase.TARGET and _target != null:
		info += "  ·  %d u" % roundi(_distance / Defs.UNIT)
	hud.set_texts("FLICKS", info, stats)
	hud.set_progress(1.0 - left / duration)


func _angle_to(angles: Vector2) -> float:
	var aim: Vector3 = player.aim_dir()
	return rad_to_deg(aim.angle_to(Defs.dir_from_angles(angles.x, angles.y)))


func _build_marker() -> void:
	var mesh := TorusMesh.new()
	var r := Defs.radius_for(0.6)
	mesh.inner_radius = r * 0.72
	mesh.outer_radius = r
	mesh.rings = 48
	mesh.ring_segments = 8
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker = MeshInstance3D.new()
	_marker.mesh = mesh
	_marker.material_override = _marker_mat
	_marker.position = player.eye_position() + Vector3(0.0, 0.0, -Defs.TARGET_DIST)
	_marker.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(_marker)
