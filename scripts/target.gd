extends Node3D
## A target with an exact ray hit test and a short pop when it's hit: either a sphere, or a CS2 head
## and shoulders where only the head counts.

const Defs = preload("res://scripts/defs.gd")
const HeadModel = preload("res://scripts/head_model.gd")

var radius := 0.2
var is_head := false
var _head_radius := HeadModel.HIT_RADIUS
var _head_half := HeadModel.HEAD_HALF
var _head_capsule: Array = []    # CS2's own head hitbox [end, end, radius], around the head's middle


func setup(p_radius: float, color: Color) -> void:
	radius = p_radius
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 0.35
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)


## A real-size head centred on this node, facing +Z: an agent's head cut from the CS2 models when
## they're available, otherwise the built-in head with shoulders. Turn the node to face the player.
func setup_head(team: int) -> void:
	is_head = true
	if Agents.in_use():
		var agent := Agents.pick(team)
		var inst := MeshInstance3D.new()
		inst.mesh = agent["head_mesh"]
		inst.position = -(agent["head_centre"] as Vector3)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
		_head_radius = agent["head_radius"]
		_head_half = agent["head_half"]
		_head_capsule = agent.get("head_capsule", [])
	else:
		HeadModel.build(self, team, true)


func hit_distance(origin: Vector3, dir: Vector3) -> float:
	if not _head_capsule.is_empty():
		var a: Vector3 = global_transform * (_head_capsule[0] as Vector3)
		var b: Vector3 = global_transform * (_head_capsule[1] as Vector3)
		return Defs.ray_capsule(origin, dir, a, b, _head_capsule[2])
	if is_head:
		var half := Vector3(0.0, _head_half, 0.0)
		return Defs.ray_capsule(origin, dir, global_position - half, global_position + half, _head_radius)
	return Defs.ray_sphere(origin, dir, global_position, radius)


## Takes the target away the moment it's hit. Callers should drop their reference right away.
func pop() -> void:
	visible = false
	queue_free()
