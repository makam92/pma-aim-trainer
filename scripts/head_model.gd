extends RefCounted
## A CS2-style head at real size: a vertical capsule about 19 cm wide and 25 cm tall, like CS2's
## head hitbox. T wears a balaclava, CT a helmet and goggles. Built around the head centre at the
## parent's origin, facing +Z.

const HEAD_RADIUS := 0.095
const HEAD_HALF := 0.03          # half of the straight middle part of the capsule
const HIT_RADIUS := 0.1          # the hitbox: a vertical capsule, slightly larger than the face
const SKIN := Color(0.78, 0.58, 0.45)
const T := 0
const CT := 1


## Adds the meshes to `parent` and returns the head's materials (for hit flashes and glow).
static func build(parent: Node3D, team: int, shoulders: bool) -> Array:
	var mats: Array = []
	var head := CapsuleMesh.new()
	head.radius = HEAD_RADIUS
	head.height = (HEAD_RADIUS + HEAD_HALF) * 2.0
	if team == T:
		mats.append(add_mesh(parent, head, Color(0.15, 0.15, 0.16), Vector3.ZERO))
		var opening := BoxMesh.new()
		opening.size = Vector3(0.13, 0.042, 0.05)
		mats.append(add_mesh(parent, opening, SKIN, Vector3(0.0, 0.015, 0.074)))
		var eyes := BoxMesh.new()
		eyes.size = Vector3(0.1, 0.014, 0.01)
		mats.append(add_mesh(parent, eyes, Color(0.08, 0.06, 0.05), Vector3(0.0, 0.016, 0.097)))
	else:
		mats.append(add_mesh(parent, head, SKIN, Vector3.ZERO))
		var helmet := SphereMesh.new()
		helmet.radius = HEAD_RADIUS + 0.012
		helmet.height = helmet.radius
		helmet.is_hemisphere = true
		mats.append(add_mesh(parent, helmet, Color(0.29, 0.33, 0.29), Vector3(0.0, HEAD_HALF, 0.0)))
		var goggles := BoxMesh.new()
		goggles.size = Vector3(0.15, 0.036, 0.05)
		mats.append(add_mesh(parent, goggles, Color(0.07, 0.07, 0.09), Vector3(0.0, 0.012, 0.074)))
	if shoulders:
		var jacket := jacket_color(team)
		var neck := CylinderMesh.new()
		neck.top_radius = 0.05
		neck.bottom_radius = 0.058
		neck.height = 0.12
		add_mesh(parent, neck, jacket.darkened(0.2), Vector3(0.0, -HEAD_RADIUS - HEAD_HALF - 0.035, 0.0))
		var torso := CapsuleMesh.new()
		torso.radius = 0.085
		torso.height = 0.44
		add_mesh(parent, torso, jacket, Vector3(0.0, -0.3, -0.01), Vector3(0.0, 0.0, 90.0))
	return mats


static func jacket_color(team: int) -> Color:
	return Color(0.45, 0.38, 0.27) if team == T else Color(0.2, 0.25, 0.34)


static func add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 0.0
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.rotation_degrees = rot
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return mat
