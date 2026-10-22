extends SceneTree
## Measures the ground speed and direction of a model's in-place run/walk animations from the feet:
## while a foot is planted it slides backwards at the speed the character is meant to move.
## Bone poses are evaluated straight from the animation tracks.
##   godot --headless --path . --script res://tools/analyze_anims.gd -- <path to agent .glb>

const STEPS := 240


func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		print("Kunde inte läsa ", path)
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		for track in anim.get_track_count():
			var track_path := str(anim.track_get_path(track))
			if anim.track_get_type(track) == Animation.TYPE_ROTATION_3D and (track_path.ends_with(":root_motion") or track_path.ends_with(":pelvis") or track_path.ends_with(":spine_0")):
				var q0: Quaternion = anim.track_get_key_value(track, 0)
				var euler := Basis(q0).get_euler() * (180.0 / PI)
				print("%s rot %s: %d nycklar, euler vid 0: %s" % [anim_name, track_path.get_slice(":", 1), anim.track_get_key_count(track), str(euler)])
		for bone_name in ["wpn", "hand_R", "head_0"]:
			var b := skeleton.find_bone(bone_name)
			if b >= 0:
				print("%s @0 %s: %s" % [anim_name, bone_name, str(bone_global(anim, skeleton, b, 0.0))])
		if anim.length < 0.05:
			continue
		var vel_sum := Vector3.ZERO
		var count := 0
		for foot in ["ankle_L", "ankle_R"]:
			var bone := skeleton.find_bone(foot)
			var points: Array[Vector3] = []
			var lowest := INF
			for i in STEPS + 1:
				var p := bone_position(anim, skeleton, bone, anim.length * i / STEPS)
				points.append(p)
				lowest = minf(lowest, p.y)
			for i in STEPS:
				if points[i].y < lowest + 0.02 and points[i + 1].y < lowest + 0.02:
					vel_sum += (points[i + 1] - points[i]) / (anim.length / STEPS)
					count += 1
		var ground := -vel_sum / maxi(count, 1)
		var flat := Vector2(ground.x, ground.z)
		print("%s: %.3f s, markfart %.2f m/s (%.0f u/s), riktning x %.2f z %.2f" % [
			anim_name, anim.length, flat.length(), flat.length() / 0.0254, ground.x / maxf(flat.length(), 0.001), ground.z / maxf(flat.length(), 0.001)])
	scene.free()
	quit()


## Skeleton-space position of a bone at time t, composing track values (or rest poses) up the chain.
static func bone_position(anim: Animation, skeleton: Skeleton3D, bone: int, t: float) -> Vector3:
	return bone_global(anim, skeleton, bone, t).origin


static func bone_global(anim: Animation, skeleton: Skeleton3D, bone: int, t: float) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		xf = bone_local(anim, skeleton, b, t) * xf
		b = skeleton.get_bone_parent(b)
	return xf


static func bone_local(anim: Animation, skeleton: Skeleton3D, bone: int, t: float) -> Transform3D:
	var rest := skeleton.get_bone_rest(bone)
	var pos := rest.origin
	var rot := rest.basis.get_rotation_quaternion()
	var suffix := ":" + skeleton.get_bone_name(bone)
	for track in anim.get_track_count():
		if not str(anim.track_get_path(track)).ends_with(suffix):
			continue
		match anim.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				pos = anim.position_track_interpolate(track, t)
			Animation.TYPE_ROTATION_3D:
				rot = anim.rotation_track_interpolate(track, t)
	return Transform3D(Basis(rot), pos)
