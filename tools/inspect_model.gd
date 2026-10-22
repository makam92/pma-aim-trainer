extends SceneTree
## Prints the structure of a .glb model: nodes, meshes, key skeleton bones and animations.
##   godot --headless --path . --script res://tools/inspect_model.gd -- <path to .glb> [--all-bones]

const KEY_BONES := ["root_motion", "pelvis", "spine_2", "neck_0", "head_0", "arm_upper_L", "hand_R", "leg_lower_L", "ankle_L"]

var _all_bones := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	_all_bones = args.has("--all-bones")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		print("Kunde inte läsa %s (fel %d)" % [path, err])
		quit(1)
		return
	var root := doc.generate_scene(state)
	_dump(root, 0, Transform3D.IDENTITY)
	for player in root.find_children("*", "AnimationPlayer", true, false):
		_dump_animations(player as AnimationPlayer)
	root.free()
	quit()


func _dump(node: Node, depth: int, parent_xf: Transform3D) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var pad := "  ".repeat(depth)
	var line := "%s%s (%s)" % [pad, node.name, node.get_class()]
	if node is Node3D and (node as Node3D).transform != Transform3D.IDENTITY:
		line += " xf=%s" % str((node as Node3D).transform)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		line += " aabb=%s skin=%s" % [str(mi.get_aabb()), str(mi.skin != null)]
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			line += "\n%s    yta %d: %s" % [pad, s, mat.resource_name if mat else "-"]
	print(line)
	if node is Skeleton3D:
		var sk := node as Skeleton3D
		print("%s  %d ben" % [pad, sk.get_bone_count()])
		for i in sk.get_bone_count():
			var bone_name := sk.get_bone_name(i)
			if _all_bones or bone_name in KEY_BONES:
				var pos := xf * sk.get_bone_global_rest(i).origin
				print("%s    ben %d %s (förälder %d) vila %s" % [pad, i, bone_name, sk.get_bone_parent(i), str(pos)])
	for child in node.get_children():
		_dump(child, depth + 1, xf)


func _dump_animations(player: AnimationPlayer) -> void:
	print("AnimationPlayer %s, rot %s" % [player.name, str(player.root_node)])
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		var line := "  %s: %.3f s, %d spår, loop %d" % [anim_name, anim.length, anim.get_track_count(), anim.loop_mode]
		for t in anim.get_track_count():
			var path := str(anim.track_get_path(t))
			if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and (path.ends_with(":root_motion") or path.ends_with(":pelvis")):
				var count := anim.track_get_key_count(t)
				var first: Vector3 = anim.track_get_key_value(t, 0)
				var last: Vector3 = anim.track_get_key_value(t, count - 1)
				line += "\n    %s: %d nycklar, från %s till %s" % [path, count, str(first), str(last)]
		print(line)
