extends "res://scripts/modes/mode_base.gd"
## Gridshot: three targets at a time on a 3×3 grid in front of you. Shoot them as fast as you can;
## every hit brings up a new one in a free spot. Runs for 60 seconds from the first hit.

const Target = preload("res://scripts/target.gd")
const HeadModel = preload("res://scripts/head_model.gd")

const COLUMNS := [-8.0, 0.0, 8.0]    # yaw of each grid column, degrees
const ROWS := [5.0, 0.0, -5.0]       # pitch of each grid row, degrees
const ACTIVE := 3

var duration := 60.0
var hits := 0
var misses := 0
var times: Array = []        # seconds between consecutive hits

var _targets := {}           # grid cell → Target
var _last_cell := -1
var _run_start := -1.0
var _last_hit := 0.0
var _done := false


func begin() -> void:
	duration = Defs.RUN_SECONDS
	for i in ACTIVE:
		_spawn()
	hud.message("Skjut ett mål för att starta klockan", UI.DIM)
	_update_hud()


func _process(_delta: float) -> void:
	if _done:
		return
	if _run_start >= 0.0 and now() - _run_start >= duration:
		_finish()
		return
	_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if _done:
		return
	var hit_cell := -1
	var nearest := INF
	for cell: int in _targets:
		var d: float = _targets[cell].hit_distance(origin, dir)
		if d >= 0.0 and d < nearest:
			nearest = d
			hit_cell = cell
	if hit_cell < 0:
		if _run_start >= 0.0:
			misses += 1
			Sfx.play("miss")
		_update_hud()
		return
	var t := now()
	if _run_start < 0.0:
		_run_start = t
		hud.message("")
	else:
		times.append(t - _last_hit)
	_last_hit = t
	hits += 1
	shot_hit = true
	Sfx.play("hit")
	_targets[hit_cell].pop()
	_targets.erase(hit_cell)
	_last_cell = hit_cell
	_spawn()
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var accuracy := float(r.get("accuracy", 0.0))
	var rows := [
		["Träffsäkerhet", "%d %%" % roundi(accuracy * 100.0)],
		["Snittid mellan träffar", UI.ms(r.get("avg_ms"))],
		["Missar", str(int(r.get("misses", 0)))],
	]
	var note := ""
	if accuracy < 0.85:
		note = "Många missar. Sakta ner en aning så att varje klick sitter, då går det fortare i längden."
	elif accuracy >= 0.97:
		note = "Nästan inga missar. Du har råd att öka tempot."
	return {"headline": str(int(r.get("score", 0))), "unit": "träffar på 60 s", "rows": rows, "note": note}


## Puts a new target in a free grid cell, never the one that was just shot.
func _spawn() -> void:
	var free: Array[int] = []
	for cell in COLUMNS.size() * ROWS.size():
		if not _targets.has(cell) and cell != _last_cell:
			free.append(cell)
	var cell: int = free.pick_random()
	var yaw: float = COLUMNS[cell % COLUMNS.size()]
	var pitch: float = ROWS[floori(float(cell) / COLUMNS.size())]
	var eye: Vector3 = player.eye_position()
	var dist := Defs.random_distance(Defs.TARGET_RANGES[Settings.grid_range])
	if pitch < 0.0:
		# Keep the bottom row above the floor however far away the target is.
		dist = minf(dist, (eye.y - Defs.MIN_TARGET_HEIGHT) / sin(deg_to_rad(-pitch)))
	var target := Target.new()
	if Settings.grid_target == 0:
		target.setup_head(randi() % 2)
	else:
		target.setup(HeadModel.HIT_RADIUS, UI.TARGET)   # a ball the size of a head
	target.position = eye + Defs.dir_from_angles(yaw, pitch) * dist
	target.rotation.y = deg_to_rad(yaw)
	add_child(target)
	_targets[cell] = target


func _finish() -> void:
	_done = true
	for cell: int in _targets:
		_targets[cell].queue_free()
	_targets.clear()
	Sfx.play("done")
	_update_hud()
	var avg: Variant = average(times)
	finished.emit({
		"variant": Defs.variant("grid", Settings),
		"score": hits,
		"hits": hits,
		"misses": misses,
		"accuracy": float(hits) / maxi(hits + misses, 1),
		"avg_ms": avg * 1000.0 if avg != null else null,
	})


func _update_hud() -> void:
	var left := duration
	if _done:
		left = 0.0
	elif _run_start >= 0.0:
		left = maxf(_run_start + duration - now(), 0.0)
	var shots := hits + misses
	var accuracy := 100 if shots == 0 else roundi(100.0 * hits / shots)
	var avg: Variant = average(times)
	var stats := "%s s kvar · %d %% · %s" % [UI.dec(left, 1), accuracy, UI.ms(avg * 1000.0 if avg != null else null)]
	hud.set_texts("GRIDSHOT", "%d träffar" % hits, stats)
	hud.set_progress(1.0 - left / duration)
