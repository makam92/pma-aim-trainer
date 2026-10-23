extends Node
## CS2 player and weapon models that the import (scripts/cs2_import.gd) reads out of the player's own
## CS2 install into user://models. They're loaded at runtime and never ship with the game; without
## them everything falls back to the simple built-in models.

const DIR := "user://models"
const VIEWMODEL_DIR := "user://viewmodel"
const VIEWMODEL_WEAPON := "weapon_rif_ak47"
const VIEWMODEL_CLIPS := {"draw": "draw_ak", "idle": "idle_ak", "shoot": "shoot1_ak"}
const T := 0
const CT := 1
const UNIT := 0.0254          # meters per CS2 unit, for the hitboxes
## CS2's hit group for the head; the neck (8) and everything else count as body.
const HEAD_GROUP := 1
## Material-name fragments that mark the head surfaces of an agent's body mesh.
const HEAD_MATERIALS := ["head", "balaclava", "lenses", "helmet", "hat", "mask", "hair", "goggles", "face", "beard", "glasses"]
## Weapon meshes face +Z with +Y up (glTF); the wpn bone faces its +X with +Z up (Source).
const WEAPON_BASIS := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
## Ground speed (units/s) each in-place animation is made for, measured from the feet with
## tools/analyze_anims.gd. Playback speed is scaled so the feet match the real speed.
const ANIM_SPEED := {"run_e": 159.0, "run_w": 140.0, "walk_e": 89.0, "walk_w": 75.0, "crouch_e": 64.0, "crouch_w": 65.0}
const WEAPON_FILES := {
	"knife": {T: "weapon_knife_default_t", CT: "weapon_knife_default_ct"},
	"rifle": {T: "weapon_rif_ak47", CT: "weapon_rif_m4a1_silencer"},
}

signal loaded

## team → Array of agents: {"name", "template", "head_mesh", "head_centre", "head_local", "head_radius",
## "head_half", "hitboxes", and with CS2's hitboxes "head_capsule": [end, end, radius] for the loose head}
var agents := {T: [], CT: []}
## file stem → template Node3D
var weapons := {}
## file stem → where the weapon model goes on a hand's "wpn" bone (see _attach_transform)
var weapon_attach := {}
## file stem → the end of the barrel on that bone, for muzzle flashes (see _muzzle)
var weapon_muzzle := {}
## First person (imported into user://viewmodel): CS2's viewmodel arms as a
## template, and the AK's first-person clips by name ("draw", "idle", "shoot"), whose tracks still
## point at the clip's own skeletons. Null and empty without the export.
var viewmodel_arms: Node3D = null
var viewmodel_clips := {}
var load_ms := 0
var is_loaded := false


func _ready() -> void:
	# Load after the first frame so the window and menu show up right away.
	_load_now.call_deferred()


func _exit_tree() -> void:
	unload()


func _load_now() -> void:
	load_all()
	is_loaded = true
	loaded.emit()


func load_all() -> void:
	var start := Time.get_ticks_msec()
	for path in _glb_files(ProjectSettings.globalize_path(DIR)):
		if path.ends_with("_physics.glb"):
			continue
		var scene := _load_glb(path)
		if scene == null:
			continue
		var stem := path.get_file().get_basename()
		if path.replace("\\", "/").contains("/agents/"):
			var agent := _prepare_agent(scene, stem)
			if not agent.is_empty():
				var skeleton := find_skeleton(scene)
				agent["hitboxes"] = _load_hitboxes(path.get_basename() + ".hitboxes.json", skeleton)
				# The head hitbox again for the loose heads, around the middle of the cut-out head.
				for h: Dictionary in agent["hitboxes"]:
					if h["group"] == HEAD_GROUP:
						var rest := skeleton.get_bone_global_rest(h["bone"])
						var middle: Vector3 = agent["head_centre"]
						agent["head_capsule"] = [rest * (h["a"] as Vector3) - middle, rest * (h["b"] as Vector3) - middle, h["radius"]]
				agents[T if stem.begins_with("tm_") else CT].append(agent)
		elif path.replace("\\", "/").contains("/weapons/"):
			_prepare_weapon(scene)
			weapons[stem] = scene
			weapon_attach[stem] = _attach_transform(scene)
			weapon_muzzle[stem] = _muzzle(scene, weapon_attach[stem])
		else:
			scene.free()
	_load_viewmodel()
	load_ms = Time.get_ticks_msec() - start


func _load_viewmodel() -> void:
	var dir := ProjectSettings.globalize_path(VIEWMODEL_DIR)
	var arms_path := dir.path_join("weapons/models/shared/arms/weapon_arms.glb")
	if not FileAccess.file_exists(arms_path):
		return
	viewmodel_arms = _load_glb(arms_path)
	for clip: String in VIEWMODEL_CLIPS:
		var scene := _load_glb(dir.path_join("animation/anims/viewmodel/rifle/rifle_ak/%s.glb" % VIEWMODEL_CLIPS[clip]))
		if scene == null:
			continue
		var player := find_player(scene)
		if player and not player.get_animation_list().is_empty():
			viewmodel_clips[clip] = player.get_animation(player.get_animation_list()[0]).duplicate()
		scene.free()


## The AK in first person needs the arms, its clips and the AK model itself.
func has_viewmodel() -> bool:
	return viewmodel_arms != null and viewmodel_clips.has("idle") and weapons.has(VIEWMODEL_WEAPON)


## Loads everything again, after the CS2 files were imported anew.
func reload() -> void:
	unload()
	is_loaded = false
	_load_now()


func unload() -> void:
	for team in agents:
		for agent: Dictionary in agents[team]:
			(agent["template"] as Node).free()
		agents[team] = []
	for stem in weapons:
		(weapons[stem] as Node).free()
	weapons.clear()
	weapon_attach.clear()
	weapon_muzzle.clear()
	if viewmodel_arms:
		viewmodel_arms.free()
		viewmodel_arms = null
	viewmodel_clips.clear()


func available() -> bool:
	return is_loaded and (not agents[T].is_empty() or not agents[CT].is_empty())


## Whether new targets and bots should use the CS2 models right now.
func in_use() -> bool:
	# Looked up at runtime so this script also compiles in tests, where there are no autoloads.
	var settings := get_node_or_null("/root/Settings")
	return available() and (settings == null or settings.use_cs2_models)


## A random agent for the team, or one from the other team if this one has none.
func pick(team: int) -> Dictionary:
	var list: Array = agents[team] if not agents[team].is_empty() else agents[1 - team]
	return list[randi() % list.size()] if not list.is_empty() else {}


## A new copy of the agent's model, holding the given weapon kind ("knife" or "rifle").
func instance(agent: Dictionary, team: int, weapon_kind: String) -> Node3D:
	var model: Node3D = (agent["template"] as Node3D).duplicate()
	var skeleton := find_skeleton(model)
	var file := weapon_file(weapon_kind, team)
	if skeleton and weapons.has(file):
		var attach := BoneAttachment3D.new()
		attach.bone_name = "wpn"
		skeleton.add_child(attach)
		var weapon: Node3D = (weapons[file] as Node3D).duplicate()
		weapon.transform = weapon_attach[file]
		attach.add_child(weapon)
	return model


## Where a weapon model goes on a hand's "wpn" bone: CS2 lines up the weapon's own "weapon" bone
## with it, and that bone sits a few centimetres from the model's origin. Exports without the
## weapon's skeleton fall back to just turning it.
static func _attach_transform(scene: Node3D) -> Transform3D:
	var skeleton := find_skeleton(scene)
	var bone := skeleton.find_bone("weapon") if skeleton else -1
	if bone < 0:
		return Transform3D(WEAPON_BASIS, Vector3.ZERO)
	var to_scene := skeleton.get_bone_global_rest(bone)
	var node: Node = skeleton
	while node != scene:
		to_scene = (node as Node3D).transform * to_scene
		node = node.get_parent()
	return to_scene.affine_inverse()


## The weapon model an agent of the team holds for a weapon kind ("knife" or "rifle").
static func weapon_file(weapon_kind: String, team: int) -> String:
	return WEAPON_FILES.get(weapon_kind, {}).get(team, "")


## The end of a weapon's barrel on the hand's "wpn" bone, which points along the barrel (+X): the
## model's front-most vertex there.
static func _muzzle(scene: Node3D, attach: Transform3D) -> Vector3:
	var front := Vector3.ZERO
	var best := -INF
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var to_scene := (node as Node3D).transform
		var parent := node.get_parent()
		while parent != scene:
			to_scene = (parent as Node3D).transform * to_scene
			parent = parent.get_parent()
		var to_bone := attach * to_scene
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			for v: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := to_bone * v
				if p.x > best:
					best = p.x
					front = p
	return front


static func find_skeleton(model: Node) -> Skeleton3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


static func find_player(model: Node) -> AnimationPlayer:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	return found[0] if not found.is_empty() else null


## Full name of the animation whose name ends with `suffix` (like "run_e_knife"), or "".
static func animation_named(player: AnimationPlayer, suffix: String) -> String:
	for anim_name in player.get_animation_list():
		if String(anim_name).ends_with(suffix):
			return anim_name
	return ""


static func is_head_material(material_name: String) -> bool:
	var lower := material_name.to_lower()
	for fragment: String in HEAD_MATERIALS:
		if lower.contains(fragment):
			return true
	return false


func _prepare_agent(scene: Node3D, stem: String) -> Dictionary:
	var skeleton := find_skeleton(scene)
	var player := find_player(scene)
	if skeleton == null or player == null or skeleton.find_bone("head_0") < 0:
		scene.free()
		return {}
	# First-person arms and sleeves overlap the third-person body.
	for node in scene.find_children("*firstperson*", "MeshInstance3D", true, false):
		node.get_parent().remove_child(node)
		node.free()
	for anim_name in player.get_animation_list():
		var anim := player.get_animation(anim_name)
		if anim.length > 0.05:
			anim.loop_mode = Animation.LOOP_LINEAR
	var head := _head_from_body(scene, skeleton)
	if head.is_empty():
		scene.free()
		return {}
	head["name"] = stem
	head["template"] = scene
	return head


## CS2's own hitboxes for an agent, saved next to its model by the import, as
## [{"bone": index, "a", "b": capsule ends in the bone's space (meters), "radius", "group"}], or []
## for models exported before that.
static func _load_hitboxes(path: String, skeleton: Skeleton3D) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array:
		return []
	# The hitboxes name bones in lower case ("hand_l"); the skeleton has "hand_L".
	var bones := {}
	for b in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(b).to_lower()] = b
	var hitboxes: Array = []
	for h: Variant in parsed:
		var bone_name := str(h.get("bone", "")).to_lower() if h is Dictionary else ""
		if not bones.has(bone_name):
			continue
		var lo: Array = h["min"]
		var hi: Array = h["max"]
		hitboxes.append({
			"bone": bones[bone_name],
			"a": Vector3(lo[0], lo[1], lo[2]) * UNIT,
			"b": Vector3(hi[0], hi[1], hi[2]) * UNIT,
			"radius": float(h["radius"]) * UNIT,
			"group": int(h["group"]),
		})
	return hitboxes


## Cuts the head surfaces out of the bind-pose body mesh and measures the skull for the hitbox.
func _head_from_body(scene: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var head_bone := skeleton.find_bone("head_0")
	var head_rest := skeleton.get_bone_global_rest(head_bone)
	var mesh := ArrayMesh.new()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var source: Mesh = (node as MeshInstance3D).mesh
		for s in source.get_surface_count():
			var mat := source.surface_get_material(s)
			if mat == null or not is_head_material(mat.resource_name):
				continue
			var arrays := source.surface_get_arrays(s)
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			mesh.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				# Only the skull counts, not the neck below the head bone.
				if v.y >= head_rest.origin.y - 0.02:
					lo = lo.min(v)
					hi = hi.max(v)
	if mesh.get_surface_count() == 0 or lo == Vector3.INF:
		return {}
	var size := hi - lo
	var centre := (lo + hi) / 2.0
	var radius := size.x / 2.0
	return {
		"head_mesh": mesh,
		"head_centre": centre,
		"head_local": head_rest.affine_inverse() * centre,
		"head_radius": radius,
		"head_half": maxf(size.y / 2.0 - radius, 0.0),
	}


func _prepare_weapon(scene: Node3D) -> void:
	# Weapons come with a legacy and an HD mesh; keep the HD one when there is one.
	var hd := scene.find_children("*body_hd*", "MeshInstance3D", true, false)
	if not hd.is_empty():
		for node in scene.find_children("*body_legacy*", "MeshInstance3D", true, false):
			node.get_parent().remove_child(node)
			node.free()


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("Kunde inte läsa modellen %s" % path)
		return null
	return doc.generate_scene(state) as Node3D


func _glb_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".glb"):
			found.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		found.append_array(_glb_files(dir_path.path_join(sub)))
	return found
