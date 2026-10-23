extends Node3D
## A CS2-sized player facing +Z. With the CS2 models available it's a real agent with its weapon,
## played with CS2's own idle/run/walk and crouch animations; otherwise a simple built-in figure.
## Hit tests use CS2's own hitboxes when they were exported with the model, otherwise capsules
## between the skeleton's bones, or fixed capsules on the simple figure.

const Defs = preload("res://scripts/defs.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const HeadModel = preload("res://scripts/head_model.gd")

const HEAD_HEIGHT := 1.69
## The simple figure squats to this height when crouched: the head 0.43 m (17 units) lower, as in
## CS2's crouch animations.
const CROUCH_SCALE := 0.745
## Simple figure: body capsules as [from, to, radius] in meters.
const BODY := [
	[Vector3(-0.1, 0.08, 0.0), Vector3(-0.1, 0.8, 0.0), 0.075],
	[Vector3(0.1, 0.08, 0.0), Vector3(0.1, 0.8, 0.0), 0.075],
	[Vector3(0.0, 0.88, 0.0), Vector3(0.0, 1.28, 0.0), 0.17],
	[Vector3(-0.2, 1.4, 0.0), Vector3(0.2, 1.4, 0.0), 0.085],
	[Vector3(-0.25, 1.37, 0.02), Vector3(-0.1, 1.12, 0.24), 0.055],
	[Vector3(0.25, 1.37, 0.02), Vector3(0.12, 1.1, 0.22), 0.055],
]
## Where the head and a body capsule overlap, the head counts unless the body part is this much
## closer (meters), like an arm clearly in front of the face. Only for the approximate capsules.
const HEAD_PRIORITY := 0.1
## The simple figure's rifle ends here.
const SIMPLE_MUZZLE := Vector3(0.02, 1.12, 0.62)
## A muzzle flash is at least this wide (meters), and grows with distance to stay this many degrees
## wide. It lasts this long.
const FLASH_SIZE := 0.25
const FLASH_DEG := 0.7
const FLASH_SECONDS := 0.05
## CS2 agent without exported hitboxes: body capsules between bones, as [from bone, to bone, radius].
## The neck is thin and ends below the head.
const BONE_CAPSULES := [
	["pelvis", "spine_1", 0.15],
	["spine_1", "spine_3", 0.16],
	["spine_3", "neck_0", 0.075],
	["arm_upper_L", "arm_lower_L", 0.06],
	["arm_lower_L", "hand_L", 0.05],
	["arm_upper_R", "arm_lower_R", 0.06],
	["arm_lower_R", "hand_R", 0.05],
	["leg_upper_L", "leg_lower_L", 0.085],
	["leg_lower_L", "ankle_L", 0.06],
	["leg_upper_R", "leg_lower_R", 0.085],
	["leg_lower_R", "ankle_R", 0.06],
]

var team := HeadModel.T
## "knife" or "rifle": which weapon the agent holds and which animation set it uses.
var weapon_kind := "rifle"
## "run" or "walk": which of CS2's locomotion clips the agent moves with.
var gait := "run"

var _head_mats: Array = []
var _body_mats: Array = []
var _glow := ""
var _agent := {}
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _has_crouch := false
var _head_node: Node3D
var _bones := {}
var _weapon_mount: BoneAttachment3D
var _muzzle := Vector3.ZERO      # on the weapon mount's bone
var _flash: MeshInstance3D
var _flash_light: OmniLight3D
var _flash_left := 0.0
var _flash_drawn := 0            # frames drawn when the flash came on

static var _flash_material: StandardMaterial3D


func _ready() -> void:
	if Agents.in_use():
		_build_agent()
	else:
		_build_simple()


func _process(delta: float) -> void:
	# A muzzle flash lasts FLASH_SECONDS, but is always drawn at least twice, also at low frame rates.
	if _flash and _flash.visible:
		_flash_left -= delta
		if _flash_left <= 0.0 and Engine.get_frames_drawn() - _flash_drawn >= 2:
			_flash.visible = false
			_flash_light.visible = false


func head_centre() -> Vector3:
	for h: Dictionary in _agent.get("hitboxes", []):
		if h["group"] == Agents.HEAD_GROUP:
			return _hitbox_ends(h)[2]
	if _skeleton:
		var head: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones["head_0"])
		return head * (_agent["head_local"] as Vector3)
	return to_global(Vector3(0.0, HEAD_HEIGHT, 0.0))


## {"part": "head" | "body" | "", "dist": distance along the ray, -1 on a miss}
func hit_test(origin: Vector3, dir: Vector3) -> Dictionary:
	var hitboxes: Array = _agent.get("hitboxes", [])
	if not hitboxes.is_empty():
		return _hit_cs2(origin, dir, hitboxes)
	var centre := head_centre()
	var head_radius: float = _agent.get("head_radius", HeadModel.HIT_RADIUS)
	var half := Vector3(0.0, _agent.get("head_half", HeadModel.HEAD_HALF), 0.0)
	var head := Defs.ray_capsule(origin, dir, centre - half, centre + half, head_radius)
	var body := -1.0
	if _skeleton:
		for c: Array in BONE_CAPSULES:
			body = _nearest(body, Defs.ray_capsule(origin, dir, _bone_position(c[0]), _bone_position(c[1]), c[2]))
	else:
		for c: Array in BODY:
			body = _nearest(body, Defs.ray_capsule(origin, dir, to_global(c[0]), to_global(c[1]), c[2]))
	if head >= 0.0 and (body < 0.0 or head <= body + HEAD_PRIORITY):
		return {"part": "head", "dist": head}
	if body >= 0.0:
		return {"part": "body", "dist": body}
	return {"part": "", "dist": -1.0}


## Like a bullet in CS2: the first of the model's own hitboxes along the ray decides.
func _hit_cs2(origin: Vector3, dir: Vector3, hitboxes: Array) -> Dictionary:
	var nearest := -1.0
	var group := 0
	for h: Dictionary in hitboxes:
		var ends := _hitbox_ends(h)
		var t := Defs.ray_capsule(origin, dir, ends[0], ends[1], h["radius"])
		if t >= 0.0 and (nearest < 0.0 or t < nearest):
			nearest = t
			group = h["group"]
	if nearest < 0.0:
		return {"part": "", "dist": -1.0}
	return {"part": "head" if group == Agents.HEAD_GROUP else "body", "dist": nearest}


## A CS2 hitbox's capsule ends and middle in world space, as posed right now.
func _hitbox_ends(h: Dictionary) -> Array[Vector3]:
	var bone := _skeleton.global_transform * _skeleton.get_bone_global_pose(h["bone"])
	var a: Vector3 = bone * (h["a"] as Vector3)
	var b: Vector3 = bone * (h["b"] as Vector3)
	return [a, b, (a + b) / 2.0]


## Turns the agent to face a point (the player), like an enemy aiming at you.
func face(point: Vector3) -> void:
	var to := point - global_position
	rotation.y = atan2(to.x, to.z)


## Whether the crouch shows: the CS2 model has its crouch clips, or it's the simple figure.
func can_crouch() -> bool:
	return _skeleton == null or _has_crouch


## Blends CS2's idle and sideways run (or walk) clips by the sideways velocity (units/s along world
## x), like CS2's own locomotion blending: speeding up, stopping and ADAD reversals flow through
## the blend instead of restarting clips, and the playback rate keeps the feet matched to the speed.
## The crouched clips blend the same way and are mixed in by `duck` (0 standing, 1 crouched).
func set_motion(vel_x: float, duck: float = 0.0) -> void:
	if _skeleton == null:
		scale.y = lerpf(1.0, CROUCH_SCALE, duck)
		if _head_node:
			_head_node.scale.y = 1.0 / scale.y   # squat, but keep the head round
		return
	if _tree == null:
		return
	# Facing the player, moving towards +x is the agent's own left: "west".
	var side := "w" if vel_x > 0.0 else "e"
	_set_blend("move", "rate", vel_x, Agents.ANIM_SPEED["%s_%s" % [gait, side]])
	if _has_crouch:
		_set_blend("crouch", "crouch_rate", vel_x, Agents.ANIM_SPEED["crouch_" + side])
		_tree.set("parameters/duck/blend_amount", duck)


## Fully into the sideways clip at half its speed; below that it fades towards standing still.
func _set_blend(space: String, rate: String, vel_x: float, ref: float) -> void:
	var speed := absf(vel_x)
	_tree.set("parameters/%s/blend_position" % space, signf(vel_x) * clampf(speed / (ref * 0.5), 0.0, 1.0))
	_tree.set("parameters/%s/scale" % rate, clampf(speed / ref, 0.7, 2.0) if speed > 20.0 else 1.0)


## A short white flash on the part that was shot.
func flash(part: String) -> void:
	for mat: StandardMaterial3D in (_head_mats if part == "head" else _body_mats):
		mat.emission = Color(1.0, 0.95, 0.85)
		mat.emission_energy_multiplier = 1.2
		create_tween().tween_property(mat, "emission_energy_multiplier", 0.0, 0.25)


## The end of the agent's gun barrel, in the world.
func muzzle_position() -> Vector3:
	if _weapon_mount:
		return _weapon_mount.global_transform * _muzzle
	return to_global(SIMPLE_MUZZLE)


## A muzzle flash at the end of the gun for a moment, as when the agent fires, lighting it up.
func muzzle_flash() -> void:
	if _flash == null:
		_flash = MeshInstance3D.new()
		_flash.mesh = QuadMesh.new()
		_flash.material_override = _flash_look()
		_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flash)
		_flash_light = OmniLight3D.new()
		_flash_light.light_color = Color(1.0, 0.72, 0.4)
		_flash_light.light_energy = 2.5
		_flash_light.omni_range = 2.0
		add_child(_flash_light)
	var at := muzzle_position()
	var size := FLASH_SIZE
	var camera := get_viewport().get_camera_3d()
	if camera:
		size = maxf(size, camera.global_position.distance_to(at) * tan(deg_to_rad(FLASH_DEG)))
	(_flash.mesh as QuadMesh).size = Vector2(size, size)
	_flash.global_position = at
	_flash_light.global_position = at
	_flash.visible = true
	_flash_light.visible = true
	_flash_left = FLASH_SECONDS
	_flash_drawn = Engine.get_frames_drawn()


## A round glow, white-hot in the middle and orange at the edge, always facing the camera.
static func _flash_look() -> StandardMaterial3D:
	if _flash_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.96, 0.8, 1.0))
		gradient.set_color(1, Color(1.0, 0.5, 0.12, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_material.albedo_texture = texture
	return _flash_material


## Lights up the part the crosshair is on, for tracking. Pass "" to clear.
func glow(part: String) -> void:
	if part == _glow:
		return
	_glow = part
	for mat: StandardMaterial3D in _head_mats:
		mat.emission = UI.GOOD
		mat.emission_energy_multiplier = 0.7 if part == "head" else 0.0
	for mat: StandardMaterial3D in _body_mats:
		mat.emission = UI.ACCENT
		mat.emission_energy_multiplier = 0.45 if part == "body" else 0.0


func _build_agent() -> void:
	_agent = Agents.pick(team)
	var model := Agents.instance(_agent, team, weapon_kind)
	add_child(model)
	_skeleton = Agents.find_skeleton(model)
	_player = Agents.find_player(model)
	for bone_name in ["head_0"] + BONE_CAPSULES.map(func(c: Array) -> String: return c[0]) + BONE_CAPSULES.map(func(c: Array) -> String: return c[1]):
		_bones[bone_name] = _skeleton.find_bone(bone_name)
	# Own copies of the materials, so flashes and glow only affect this agent (and not its weapon).
	var mounts := model.find_children("*", "BoneAttachment3D", true, false)
	var weapon_meshes := mounts.map(func(a: Node) -> Array: return a.find_children("*", "MeshInstance3D", true, false))
	if not mounts.is_empty():
		_weapon_mount = mounts[0]
		_muzzle = Agents.weapon_muzzle.get(Agents.weapon_file(weapon_kind, team), Vector3.ZERO)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if weapon_meshes.any(func(list: Array) -> bool: return list.has(node)):
			continue
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if source == null:
				continue
			var mat := source.duplicate() as StandardMaterial3D
			mat.emission_enabled = true
			mat.emission_energy_multiplier = 0.0
			mi.set_surface_override_material(s, mat)
			(_head_mats if Agents.is_head_material(source.resource_name) else _body_mats).append(mat)
	_build_animation_tree()
	set_motion(0.0)


## Two blend spaces, standing and crouched, each from moving right (-1) through standing still (0)
## to moving left (+1) with its own time scale, mixed by the crouch amount. All clips in a blend
## space keep ticking (sync), so the stride never jumps when the blend moves. Models exported
## before the crouch clips were added just stand.
func _build_animation_tree() -> void:
	var stand := _blend_space(["idle", gait + "_e", gait + "_w"])
	if stand == null:
		return
	var root := AnimationNodeBlendTree.new()
	root.add_node("move", stand)
	root.add_node("rate", AnimationNodeTimeScale.new())
	root.connect_node("rate", 0, "move")
	var crouched := _blend_space(["idle_crouch", "crouch_e", "crouch_w"])
	_has_crouch = crouched != null
	if _has_crouch:
		root.add_node("crouch", crouched)
		root.add_node("crouch_rate", AnimationNodeTimeScale.new())
		root.connect_node("crouch_rate", 0, "crouch")
		root.add_node("duck", AnimationNodeBlend2.new())
		root.connect_node("duck", 0, "rate")
		root.connect_node("duck", 1, "crouch_rate")
		root.connect_node("output", 0, "duck")
	else:
		root.connect_node("output", 0, "rate")
	_player.stop()
	_tree = AnimationTree.new()
	_player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.tree_root = root
	_tree.active = true


## A blend space over [standing still, moving right, moving left] clips, or null if the model lacks
## one of them.
func _blend_space(clip_names: Array) -> AnimationNodeBlendSpace1D:
	var clips: Array[String] = []
	for clip: String in clip_names:
		clips.append(Agents.animation_named(_player, "%s_%s" % [clip, weapon_kind]))
		if clips[-1] == "":
			return null
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = -1.0
	space.max_space = 1.0
	space.sync = true
	space.add_blend_point(_clip_node(clips[1]), -1.0, -1, &"right")
	space.add_blend_point(_clip_node(clips[0]), 0.0, -1, &"idle")
	space.add_blend_point(_clip_node(clips[2]), 1.0, -1, &"left")
	return space


static func _clip_node(anim_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	return node


func _build_simple() -> void:
	var jacket := HeadModel.jacket_color(team)
	for i in BODY.size():
		var c: Array = BODY[i]
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var mesh := CapsuleMesh.new()
		mesh.radius = c[2]
		mesh.height = a.distance_to(b) + mesh.radius * 2.0
		var color := jacket.darkened(0.35) if i < 2 else jacket
		var mat := HeadModel.add_mesh(self, mesh, color, (a + b) / 2.0)
		var inst: MeshInstance3D = get_child(get_child_count() - 1)
		inst.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		_body_mats.append(mat)
	var rifle := BoxMesh.new()
	rifle.size = Vector3(0.05, 0.08, 0.6)
	HeadModel.add_mesh(self, rifle, Color(0.12, 0.12, 0.13), Vector3(0.02, 1.12, 0.32))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.05
	neck.bottom_radius = 0.06
	neck.height = 0.12
	HeadModel.add_mesh(self, neck, jacket.darkened(0.2), Vector3(0.0, 1.52, 0.0))
	_head_node = Node3D.new()
	_head_node.position = Vector3(0.0, HEAD_HEIGHT, 0.0)
	add_child(_head_node)
	_head_mats = HeadModel.build(_head_node, team, false)


func _bone_position(bone_name: String) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones[bone_name]).origin


func _nearest(current: float, t: float) -> float:
	if t >= 0.0 and (current < 0.0 or t < current):
		return t
	return current
