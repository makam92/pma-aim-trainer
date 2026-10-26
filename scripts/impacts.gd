extends Node3D
## Where shots land: a bullet hole with a puff of dust where a miss hits the wall, floor or
## ceiling, and on every third shot a tracer from the gun, like CS2's AK. Holes keep the same size on
## screen at any distance, so a miss far away still shows how far off it was. They stay until the
## next run (the newest MAX_HOLES of them).

const Defs = preload("res://scripts/defs.gd")
const MAX_HOLES := 60
const HOLE_DEG := 0.35          # how big a hole looks, at least HOLE_MIN wide
const HOLE_MIN := 0.025
const PUFF_DEG := 0.9
const PUFF_SECONDS := 0.35
const TRACER_SPEED := 160.0     # m/s; slower than a real bullet so the eye can catch it
const TRACER_LENGTH := 2.5
const TRACER_WIDTH := 0.0022    # times the distance to the camera, about 2 px

var _holes: Array[Node3D] = []
var _tracers: Array[Dictionary] = []
var _hole_mat: StandardMaterial3D
var _puff_mat: StandardMaterial3D
var _tracer_mat: StandardMaterial3D
var _camera: Camera3D


func _ready() -> void:
	_hole_mat = _material(_radial([Color(0.03, 0.025, 0.02, 0.95), Color(0.08, 0.06, 0.04, 0.85), Color(0.1, 0.08, 0.06, 0.0)]), false)
	_puff_mat = _material(_radial([Color(0.78, 0.72, 0.62, 0.7), Color(0.7, 0.65, 0.56, 0.0)]), true)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tracer_mat.albedo_color = Color(1.0, 0.8, 0.45, 0.9)


func clear() -> void:
	for hole in _holes:
		hole.queue_free()
	_holes.clear()
	for tracer in _tracers:
		(tracer["node"] as Node).queue_free()
	_tracers.clear()


## A shot from `origin` along `dir`. Misses leave a hole where they hit the room, or the mode's own
## wall when `surface` has where ({"dist", "normal"}); a tracer starts at `muzzle` (where the gun's
## muzzle shows on screen).
func shot(origin: Vector3, dir: Vector3, hit: bool, tracer: bool, muzzle: Vector3, surface: Dictionary = {}) -> void:
	_camera = get_viewport().get_camera_3d()
	var dist := Defs.ray_box_exit(origin, dir, Defs.ROOM_MIN, Defs.ROOM_MAX)
	if surface.has("dist"):
		dist = surface["dist"]
	if dist <= 0.0:
		return
	var point := origin + dir * dist
	if not hit:
		_add_hole(point, surface["normal"] if surface.has("normal") else _normal_at(point), dist)
	if tracer:
		_add_tracer(muzzle, point)


func _process(delta: float) -> void:
	if _tracers.is_empty() or _camera == null:
		return
	var eye := _camera.global_position
	for i in range(_tracers.size() - 1, -1, -1):
		var tracer: Dictionary = _tracers[i]
		tracer["travelled"] += TRACER_SPEED * delta
		var from: Vector3 = tracer["from"]
		var axis: Vector3 = tracer["axis"]
		var head := minf(tracer["travelled"], tracer["length"])
		var tail := maxf(head - TRACER_LENGTH, 0.0)
		var node: MeshInstance3D = tracer["node"]
		if tail >= tracer["length"] - 0.01:
			node.queue_free()
			_tracers.remove_at(i)
			continue
		# A ribbon along the bullet's path, turned to face the camera.
		var centre := from + axis * (head + tail) / 2.0
		var side := axis.cross(eye - centre).normalized()
		var width := TRACER_WIDTH * eye.distance_to(centre)
		node.global_transform = Transform3D(Basis(side * width, axis * (head - tail), axis.cross(side)), centre)


func _add_hole(point: Vector3, normal: Vector3, dist: float) -> void:
	var size := maxf(HOLE_MIN, dist * tan(deg_to_rad(HOLE_DEG)))
	var hole := _quad(size, _hole_mat)
	add_child(hole)
	var up := Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
	hole.global_transform = Transform3D(Basis.looking_at(-normal, up), point + normal * 0.003)
	_holes.append(hole)
	if _holes.size() > MAX_HOLES:
		_holes.pop_front().queue_free()
	var puff := _quad(dist * tan(deg_to_rad(PUFF_DEG)), _puff_mat.duplicate() as StandardMaterial3D)
	add_child(puff)
	puff.global_position = point + normal * (size * 0.5)
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "scale", Vector3.ONE * 2.2, PUFF_SECONDS).set_ease(Tween.EASE_OUT)
	tween.tween_property(puff.material_override, "albedo_color:a", 0.0, PUFF_SECONDS)
	tween.chain().tween_callback(puff.queue_free)


func _add_tracer(from: Vector3, to: Vector3) -> void:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	node.mesh = quad
	node.material_override = _tracer_mat
	add_child(node)
	_tracers.append({"node": node, "from": from, "axis": (to - from).normalized(), "length": from.distance_to(to), "travelled": 0.0})


static func _normal_at(p: Vector3) -> Vector3:
	const EDGE := 0.01
	if p.y <= Defs.ROOM_MIN.y + EDGE:
		return Vector3.UP
	if p.y >= Defs.ROOM_MAX.y - EDGE:
		return Vector3.DOWN
	if p.x <= Defs.ROOM_MIN.x + EDGE:
		return Vector3.RIGHT
	if p.x >= Defs.ROOM_MAX.x - EDGE:
		return Vector3.LEFT
	if p.z <= Defs.ROOM_MIN.z + EDGE:
		return Vector3.BACK
	return Vector3.FORWARD


static func _quad(size: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	node.mesh = quad
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _material(texture: Texture2D, billboard: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if billboard else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return mat


static func _radial(colors: Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(range(colors.size()).map(func(i: int) -> float: return float(i) / (colors.size() - 1)))
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture
