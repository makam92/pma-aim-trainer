extends SceneTree
## Targets must always be visible: never under the floor, through the ceiling or outside the room,
## whatever distance and pitch they get.
##   godot --headless --path . --script res://tests/test_targets.gd

const Defs = preload("res://scripts/defs.gd")

const EYE := 1.6256
const FLICK_PITCH := 7.0
const FLICK_YAW := 60.0
const CONFIRM_PITCH := Vector2(-9.0, 13.0)
const CONFIRM_YAW := 38.0
const MICRO_YAW := 30.0        # micro_mode.gd: MAX_YAW, TOP_PITCH, and 0.5° above the lowest pitch
const MICRO_TOP := 12.0


func _initialize() -> void:
	var failures := 0
	var lowest := INF
	for span: Dictionary in Defs.TARGET_RANGES:
		for i in 20000:
			var dist := Defs.random_distance(span)
			var flick := Vector2(randf_range(-FLICK_YAW, FLICK_YAW), randf_range(maxf(-FLICK_PITCH, Defs.lowest_pitch(dist, EYE)), FLICK_PITCH))
			var confirm := Vector2(randf_range(-CONFIRM_YAW, CONFIRM_YAW), randf_range(maxf(CONFIRM_PITCH.x, Defs.lowest_pitch(dist, EYE)), CONFIRM_PITCH.y))
			var micro := Vector2(randf_range(-MICRO_YAW, MICRO_YAW), randf_range(Defs.lowest_pitch(dist, EYE) + 0.5, MICRO_TOP))
			for angles: Vector2 in [flick, confirm, micro]:
				var p := Vector3(0.0, EYE, 0.0) + Defs.dir_from_angles(angles.x, angles.y) * dist
				lowest = minf(lowest, p.y)
				var inside := p.x > Defs.ROOM_MIN.x and p.x < Defs.ROOM_MAX.x and p.z > Defs.ROOM_MIN.z and p.z < Defs.ROOM_MAX.z
				if p.y < Defs.MIN_TARGET_HEIGHT - 0.001 or p.y > Defs.ROOM_MAX.y - 0.2 or not inside:
					failures += 1
	print("Lägsta mål: %.2f m över golvet" % lowest)
	print("OK" if failures == 0 else "FEL: %d mål utanför rummet" % failures)
	quit(failures)
