extends "res://scripts/modes/mode_base.gd"
## Click Timing: hold a doorway while CS2 bots run past it behind the wall, one at a time and from
## either side, at CS2 speeds. You get one shot per bot, so it's the timing of the click that's
## trained, not spraying: a fixed crosshair has the head under it for only about 40 ms. Every shot
## shows how many ms too early or too late it was, and the run whether you tend to shoot early or late.
## With counter-strafe you strafe with A/D like in CS2 while you wait: a shot only counts after
## strafing, and one fired before you're accurate again goes wide, as in CS2.

const Dummy = preload("res://scripts/dummy.gd")
const Sim = preload("res://scripts/movement_sim.gd")
const SpeedMeter = preload("res://scripts/ui/speed_meter.gd")

enum Phase { READY, RUN, DONE }

const WALL_THICKNESS := 16.0           # units, like a wall in CS2
const DOOR_HEIGHT := 112.0             # units
const FRAME_WIDTH := 5.0               # units: the door frame on the wall's face,
const FRAME_DEPTH := 2.0               # standing out this far
const PATH_DEPTH := Vector2(24.0, 80.0)   # units behind the wall the bots run
const BODY_HALF := 24.0                # units: a bot this far past what you see of its path is out of sight
const LEAD := Vector2(0.15, 0.8)       # seconds a bot runs out of sight before it reaches the door
const PAUSE := Vector2(0.5, 1.2)       # seconds from one bot leaving to the next one starting
const AIM_MARGIN := 20.0               # units around the door where a shot counts as timed
## Units to either side of the middle of the head where a shot was on time, so a miss there went
## over or under.
const HEAD_HALF := 4.5
const LANE_HALF_WIDTH := 3.0           # meters you can strafe to each side, with counter-strafe
const LOOKBACK := 0.8                  # a shot counts after strafing within this many seconds,
const MOVING_FRACTION := 0.5           # at this share of your max speed or more

var duration := 60.0
var max_speed := 250.0
var strafing := false                  # counter-strafe: you move with A/D like in CS2
var phase := Phase.READY
var kills := 0
var bots := 0                          # bots that came past, shot or not
var shots := 0
var early := 0
var late := 0
var off_height := 0                    # on time, but over or under
var body_hits := 0
var no_shot := 0
var moving_shots := 0                  # fired before you were accurate again
var still_shots := 0                   # fired without strafing first; they don't count
var errors: Array = []                 # seconds off for every timed shot: below 0 early, above 0 late
var stop_delays: Array = []            # seconds from being accurate again to the shot
var run_start := 0.0
var sim: Sim
var meter: SpeedMeter

var _mixed := false                    # every bot gets a CS2 speed at random
var _door := 64.0                      # units wide
var _wall := 0.0                       # meters to the wall's face
var _boxes: Array = []                 # the wall's pieces as [lo, hi], for bullets
var _dummy: Dummy = null
var _armed := false                    # the bot on its way hasn't been shot at yet
var _side := 1.0                       # +1: running towards +x
var _speed := 0.0                      # meters/s
var _path_z := 0.0
var _x0 := 0.0
var _t0 := 0.0
var _next_bot := INF
var _held := {"w": false, "a": false, "s": false, "d": false}
var _weapon: Dictionary = Defs.WEAPONS[0]   # your AK: its speed and how wide it shoots on the move
var _pb := -1


func begin() -> void:
	duration = Defs.RUN_SECONDS
	_mixed = Settings.timing_speed >= Defs.TRACK_SPEEDS.size()
	if not _mixed:
		max_speed = Defs.TRACK_SPEEDS[Settings.timing_speed]["speed"]
	_door = Defs.DOORS[Settings.timing_door]["width"]
	_wall = Defs.TRACK_DISTS[Settings.timing_dist] * Defs.UNIT
	strafing = Settings.timing_move == 1
	var best: Variant = Stats.best("timing", Defs.variant("timing", Settings))
	if best != null:
		_pb = int(best.get("score", 0))
	_build_wall()
	if strafing:
		sim = Sim.new()
		sim.max_speed = _weapon["speed"]
		var half := LANE_HALF_WIDTH / Defs.UNIT
		sim.bounds = Rect2(-half, -1.0, half * 2.0, 2.0)
		sim.reset(now())
		add_lane(LANE_HALF_WIDTH)
		meter = SpeedMeter.new()
		meter.sim = sim
		hud.add_widget(meter)
		hud.message("Strafea med A/D medan du väntar och kontra innan skottet: ett skott per gubbe", UI.DIM)
	else:
		hud.message("Ett skott per gubbe: tajma klicket när han springer förbi dörren", UI.DIM)
	_update_hud()


## The first bot is on its way as the run starts.
func go() -> void:
	phase = Phase.RUN
	run_start = now()
	hud.message("")
	_next_bot = run_start + randf_range(PAUSE.x, PAUSE.y)


func _process(_delta: float) -> void:
	var t := now()
	if sim:
		sim.yaw = deg_to_rad(player.yaw)
		sim.advance(t)
		var state := sim.state_at(t)
		var p: Vector2 = state["pos"]
		player.position = Vector3(p.x * Defs.UNIT, 0.0, p.y * Defs.UNIT)
		meter.speed = (state["vel"] as Vector2).length()
		meter.queue_redraw()
	if phase != Phase.RUN:
		return
	if t - run_start >= duration:
		_complete()
		return
	if _dummy:
		_place_bot(t)
		var seen := _window(player.eye_position().x)
		var past := seen.y if _side > 0.0 else -seen.x
		if _side * _dummy.position.x > past + BODY_HALF * Defs.UNIT:
			_bot_gone()
	elif t >= _next_bot:
		_spawn_bot(t)
	_update_hud()


func key_event(key: String, pressed: bool, t: float) -> void:
	if sim == null or _held[key] == pressed:
		return
	_held[key] = pressed
	sim.set_key(t, key, pressed)


## Keys may have changed while the game was paused, or been held through the countdown.
func on_resume() -> void:
	for code in Defs.MOVE_KEYS:
		key_event(Defs.MOVE_KEYS[code], Input.is_physical_key_pressed(code), now())


## One shot per bot: after it, and between bots, the gun waits for the next one.
func can_shoot() -> bool:
	if phase != Phase.RUN or _armed:
		return true
	if _dummy != null:
		hud.message("Ett skott per gubbe", UI.DIM)
	return false


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if phase != Phase.RUN or not _armed:
		return
	_armed = false
	shots += 1
	var t := now()
	_place_bot(t)
	var aimed := dir
	var speed := 0.0
	var counts := true
	if sim:
		sim.advance(t)
		speed = (sim.state_at(t)["vel"] as Vector2).length()
		counts = sim.peak_speed(t - LOOKBACK, t) >= sim.max_speed * MOVING_FRACTION
		if counts and speed > sim.threshold():
			moving_shots += 1
			dir = _scatter(dir, speed)
			shot_dir = dir
		elif counts:
			var became := sim.became_accurate(t, sim.threshold(), speed)
			if became >= 0.0:
				stop_delays.append(t - became)
	var hit: Dictionary = _dummy.hit_test(origin, dir)
	var part: String = hit["part"]
	var wall := _wall_hit(origin, dir)
	if part != "" and wall.has("dist") and float(wall["dist"]) < float(hit["dist"]):
		part = ""   # the bullet stops in the wall
	shot_hit = part != ""
	if not counts:
		still_shots += 1
		Sfx.play("miss")
		hud.flash("STOD STILL", UI.BAD)
		_update_hud()
		return
	var timing: Variant = _timing(origin, aimed)
	if timing != null:
		errors.append(timing["error"])
	if part == "head":
		_kill(timing)
		return
	Sfx.play("hit" if part == "body" else "miss")
	if speed > (sim.threshold() if sim else INF):
		hud.flash("I RÖRELSE · %d u/s" % roundi(speed), UI.BAD)
	elif part == "body":
		body_hits += 1
		_dummy.flash("body")
		hud.flash("KROPPSTRÄFF", UI.BAD)
	elif timing == null:
		hud.flash("MISS", UI.BAD)
	elif absf(timing["across"]) <= HEAD_HALF * Defs.UNIT:
		off_height += 1
		hud.flash("FÖR HÖGT" if float(timing["height"]) > 0.0 else "FÖR LÅGT", UI.BAD)
	else:
		var is_early: bool = timing["error"] < 0.0
		if is_early:
			early += 1
		else:
			late += 1
		var word := "FÖR TIDIGT" if is_early else "FÖR SENT"
		hud.flash(word + (" · %d ms" % roundi(absf(timing["error"]) * 1000.0) if Settings.hit_times else ""), UI.BAD)
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var kills := int(r.get("score", 0))
	var early := int(r.get("early", 0))
	var late := int(r.get("late", 0))
	var shots := int(r.get("shots", 0))
	var strafed: bool = r.get("strafing", false)
	var moving := int(r.get("moving_shots", 0))
	var still := int(r.get("still_shots", 0))
	var rows := [
		["Träffade gubbar", "%d av %d" % [kills, int(r.get("bots", 0))]],
		["Träffsäkerhet", "%d %%" % roundi(float(r.get("accuracy", 0.0)) * 100.0)],
		["Snitt från perfekt", UI.ms(r.get("off_ms"))],
		["Tendens", _bias_text(r.get("bias_ms"))],
		["För tidigt / för sent", "%d / %d" % [early, late]],
		["Rätt tid, för högt/lågt", str(int(r.get("off_height", 0)))],
		["Kroppsträffar", str(int(r.get("body_hits", 0)))],
		["Utan skott", str(int(r.get("no_shot", 0)))],
	]
	if strafed:
		rows.append(["Skott efter stopp", UI.ms(r.get("stop_ms"))])
		rows.append(["I rörelse / stod still", "%d / %d" % [moving, still]])
	var note := ""
	if shots == 0:
		note = "Du sköt inte på någon gubbe. Lägg siktet i dörren i huvudhöjd och klicka när han springer förbi."
	elif strafed and moving * 3 >= shots:
		note = "Många skott gick iväg innan du hunnit stanna. Kontra lite tidigare, så att du står still när huvudet kommer in i siktet."
	elif strafed and still * 3 >= shots:
		note = "Många skott kom efter att du stått still för länge. Fortsätt strafea medan du väntar och kontra när du ser gubben."
	elif int(r.get("no_shot", 0)) * 3 > int(r.get("bots", 1)):
		note = "Många gubbar sprang förbi utan att du sköt. Klicka när huvudet är på väg in i siktet, inte när det redan är där."
	elif early + late >= 4 and early >= late * 2:
		note = "Du skjuter oftast för tidigt: huvudet har inte hunnit fram till siktet. Vänta in det en aning längre."
	elif early + late >= 4 and late >= early * 2:
		note = "Du skjuter oftast för sent: huvudet har redan passerat siktet. Klicka lite tidigare, redan när han är på väg in."
	elif int(r.get("off_height", 0)) * 3 >= shots:
		note = "Timingen sitter, men skotten går över eller under. Håll siktet i huvudhöjd i dörren."
	elif float(r.get("accuracy", 0.0)) >= 0.7:
		note = "Bra timing! Prova högre fart, en smalare dörr" + (" eller counter-strafe." if not strafed else ".")
	return {"headline": str(kills), "unit": "kills på 60 s", "rows": rows, "note": note}


## "12 ms för tidigt", "i tid", or "–" without timed shots.
static func _bias_text(bias: Variant) -> String:
	if bias == null:
		return "–"
	var n := roundi(float(bias))
	if absi(n) < 5:
		return "i tid"
	return "%d ms för %s" % [absi(n), "tidigt" if n < 0 else "sent"]


## The wall with the doorway, from side to side of the room and up to its ceiling, and a frame
## around the door.
func _build_wall() -> void:
	var half := _door / 2.0 * Defs.UNIT
	var front := -_wall
	var back := -(_wall + WALL_THICKNESS * Defs.UNIT)
	var top := DOOR_HEIGHT * Defs.UNIT
	var lo := Defs.ROOM_MIN
	var hi := Defs.ROOM_MAX
	var wall: Material = main.world.partition
	_add_box(Vector3(lo.x, 0.0, back), Vector3(-half, hi.y, front), wall)
	_add_box(Vector3(half, 0.0, back), Vector3(hi.x, hi.y, front), wall)
	_add_box(Vector3(-half, top, back), Vector3(half, hi.y, front), wall)
	var frame := FRAME_WIDTH * Defs.UNIT
	var out := front + FRAME_DEPTH * Defs.UNIT
	var wood: Material = main.world.frame
	_add_box(Vector3(-half - frame, 0.0, front), Vector3(-half, top + frame, out), wood)
	_add_box(Vector3(half, 0.0, front), Vector3(half + frame, top + frame, out), wood)
	_add_box(Vector3(-half, top, front), Vector3(half, top + frame, out), wood)


func _add_box(lo: Vector3, hi: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = hi - lo
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = (lo + hi) / 2.0
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	_boxes.append([lo, hi])


## Bullets stop in the wall.
func surface(origin: Vector3, dir: Vector3) -> Dictionary:
	return _wall_hit(origin, dir)


func _wall_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var nearest := {}
	for box: Array in _boxes:
		var hit := Defs.ray_box_entry(origin, dir, box[0], box[1])
		if hit.has("dist") and (nearest.is_empty() or float(hit["dist"]) < float(nearest["dist"])):
			nearest = hit
	return nearest


## The stretch of the bots' path (x from, to; meters) that shows through the door from an eye at
## x = eye_x: a little wider than the door, as the path is further away.
func _window(eye_x: float) -> Vector2:
	var half := _door / 2.0 * Defs.UNIT
	var lo := -INF
	var hi := INF
	for face: float in [_wall, _wall + WALL_THICKNESS * Defs.UNIT]:
		var k := -_path_z / face
		lo = maxf(lo, eye_x + (-half - eye_x) * k)
		hi = minf(hi, eye_x + (half - eye_x) * k)
	return Vector2(lo, hi)


## The next bot, out of sight behind the wall on a random side (from anywhere you can strafe to),
## already running at full speed towards the door.
func _spawn_bot(t: float) -> void:
	_clear_bot()
	if _mixed:
		var pick: Dictionary = Defs.TRACK_SPEEDS.pick_random()
		max_speed = pick["speed"]
	_speed = max_speed * Defs.UNIT
	_side = 1.0 if randf() < 0.5 else -1.0
	_path_z = -(_wall + WALL_THICKNESS * Defs.UNIT + randf_range(PATH_DEPTH.x, PATH_DEPTH.y) * Defs.UNIT)
	# From one side of your lane you see furthest along the path on the other side.
	var reach := _window(-LANE_HALF_WIDTH if strafing else 0.0).y
	_x0 = -_side * (reach + BODY_HALF * Defs.UNIT + _speed * randf_range(LEAD.x, LEAD.y))
	_t0 = t
	_next_bot = INF
	_dummy = Dummy.new()
	_dummy.team = randi() % 2
	_dummy.weapon_kind = "rifle" if max_speed <= 225.0 and max_speed >= 200.0 else "knife"
	_dummy.gait = "walk" if max_speed <= 140.0 else "run"
	add_child(_dummy)
	_place_bot(t)
	_armed = true
	hud.message("")


func _place_bot(t: float) -> void:
	_dummy.position = Vector3(_x0 + _side * _speed * (t - _t0), 0.0, _path_z)
	_dummy.face(player.eye_position())
	_dummy.set_motion(_side * max_speed)


## How far off in time a shot was: when the head gets to the spot on its path you aimed at,
## compared with when you fired. {"error": seconds, below 0 too early; "across": meters it still
## had to go; "height": meters you aimed over it}, or null when you didn't aim at the door.
func _timing(origin: Vector3, dir: Vector3) -> Variant:
	if dir.z > -1e-4:
		return null
	var aim := origin + dir * ((_path_z - origin.z) / dir.z)
	var seen := _window(origin.x)
	var margin := AIM_MARGIN * Defs.UNIT
	if aim.x < seen.x - margin or aim.x > seen.y + margin or aim.y > DOOR_HEIGHT * Defs.UNIT + margin:
		return null
	var head := _dummy.head_centre()
	var ahead := (aim.x - head.x) * _side
	return {"error": -ahead / _speed, "across": ahead, "height": aim.y - head.y}


## A shot fired before you're accurate again goes wide like in CS2, the more the faster you move
## (the AK's movement inaccuracy, as in Counter-strafe).
func _scatter(dir: Vector3, speed: float) -> Vector3:
	var x := clampf(remap(speed, sim.threshold(), sim.max_speed * 0.95, 0.0, 1.0), 0.0, 1.0)
	var r := randf() * float(_weapon["move_inacc"]) * sqrt(x)
	var angle := randf() * TAU
	var basis: Basis = player.camera.global_transform.basis
	return (dir + basis.x * cos(angle) * r + basis.y * sin(angle) * r).normalized()


func _kill(timing: Variant) -> void:
	kills += 1
	bots += 1
	Sfx.play("head", 1.0 + 0.5 * minf(kills / 30.0, 1.0))
	if Settings.hit_times and timing != null:
		var ms := roundi(float(timing["error"]) * 1000.0)
		hud.flash("i tid" if absi(ms) < 3 else "%d ms %s" % [absi(ms), "tidigt" if ms < 0 else "sent"], UI.GOOD)
	_clear_bot()
	_next_bot = now() + randf_range(PAUSE.x, PAUSE.y)
	_update_hud()


## Out of sight on the other side: the next one comes after a short pause.
func _bot_gone() -> void:
	bots += 1
	if _armed:
		no_shot += 1
		hud.flash("INGET SKOTT", UI.DIM)
	_armed = false
	_clear_bot()
	hud.message("")
	_next_bot = now() + randf_range(PAUSE.x, PAUSE.y)


func _clear_bot() -> void:
	if _dummy:
		_dummy.queue_free()
	_dummy = null


func _complete() -> void:
	phase = Phase.DONE
	_armed = false
	_clear_bot()
	hud.message("")
	Sfx.play("done")
	_update_hud()
	var counted := shots - still_shots
	finished.emit({
		"variant": Defs.variant("timing", Settings),
		"score": kills,
		"strafing": strafing,
		"bots": bots,
		"shots": shots,
		"early": early,
		"late": late,
		"off_height": off_height,
		"body_hits": body_hits,
		"no_shot": no_shot,
		"moving_shots": moving_shots,
		"still_shots": still_shots,
		"accuracy": float(kills) / maxi(counted, 1),
		"off_ms": to_ms(average(errors.map(func(e: float) -> float: return absf(e)))),
		"bias_ms": to_ms(average(errors)),
		"stop_ms": to_ms(average(stop_delays)),
	})


func _update_hud() -> void:
	var left := duration
	if phase == Phase.RUN:
		left = maxf(run_start + duration - now(), 0.0)
	elif phase == Phase.DONE:
		left = 0.0
	var info := "%d kills" % kills
	if _mixed and _dummy != null:
		info += "  ·  %d u/s" % max_speed
	var counted := shots - still_shots
	var accuracy := 100 if counted == 0 else roundi(100.0 * kills / counted)
	var pb := "PB %d" % _pb if _pb >= 0 else "inget PB än"
	var speed_text := Defs.MIXED_SPEED if _mixed \
		else "%s %d u/s" % [Defs.TRACK_SPEEDS[Settings.timing_speed]["name"], max_speed]
	var door: Dictionary = Defs.DOORS[Settings.timing_door]
	var title := "CLICK TIMING · %s · %s %d u" % [speed_text, str(door["name"]).to_upper(), door["width"]]
	if strafing:
		title += " · COUNTER-STRAFE"
	hud.set_texts(title, info, "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, pb])
	hud.set_progress(1.0 - left / duration)
