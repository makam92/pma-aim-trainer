extends Node3D
## The training room: grid walls with a line at eye height, light and environment.
## Two looks: "Dust" (sand-coloured like CS2's desert maps) and a dark one.

const Defs = preload("res://scripts/defs.gd")

const THEMES := [
	{
		"wall": Color(0.62, 0.55, 0.44), "line": Color(0.55, 0.48, 0.38), "major": Color(0.48, 0.42, 0.33),
		"floor": Color(0.5, 0.45, 0.36), "eye": Color(0.8, 0.36, 0.1), "sky": Color(0.6, 0.67, 0.75),
		"ambient": 0.7, "sun": 1.0,
	},
	{
		"wall": Color(0.13, 0.14, 0.17), "line": Color(0.21, 0.225, 0.27), "major": Color(0.29, 0.31, 0.37),
		"floor": Color(0.1, 0.105, 0.125), "eye": Color(0.62, 0.45, 0.16), "sky": Color(0.05, 0.055, 0.07),
		"ambient": 0.55, "sun": 0.85,
	},
]

const GRID_SHADER := """
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.13, 0.14, 0.17);
uniform vec3 line_color : source_color = vec3(0.21, 0.225, 0.27);
uniform vec3 major_color : source_color = vec3(0.29, 0.31, 0.37);
uniform vec3 eye_color : source_color = vec3(0.62, 0.45, 0.16);
uniform float eye_height = 1.6256;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p) {
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	vec3 col = mix(base_color, line_color, grid(p));
	col = mix(col, major_color, grid(p / 5.0));
	if (n.y < 0.5) {
		float eye = 1.0 - min(abs(world_pos.y - eye_height) / (fwidth(world_pos.y) * 1.5), 1.0);
		col = mix(col, eye_color, eye);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""

var _env: Environment
var _sun: DirectionalLight3D
var _walls: ShaderMaterial
var _floor: ShaderMaterial


func _ready() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.85, 0.85, 0.88)
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(_sun)

	var shader := Shader.new()
	shader.code = GRID_SHADER
	_walls = ShaderMaterial.new()
	_walls.shader = shader
	_floor = ShaderMaterial.new()
	_floor.shader = shader

	var lo := Defs.ROOM_MIN
	var hi := Defs.ROOM_MAX
	var size := hi - lo
	var mid := (hi + lo) / 2.0
	_plane(Vector2(size.x, size.z), Vector3(mid.x, lo.y, mid.z), Vector3.ZERO, _floor)
	_plane(Vector2(size.x, size.z), Vector3(mid.x, hi.y, mid.z), Vector3(180.0, 0.0, 0.0), _walls)
	_plane(Vector2(size.x, size.y), Vector3(mid.x, mid.y, lo.z), Vector3(90.0, 0.0, 0.0), _walls)
	_plane(Vector2(size.x, size.y), Vector3(mid.x, mid.y, hi.z), Vector3(-90.0, 0.0, 0.0), _walls)
	_plane(Vector2(size.y, size.z), Vector3(lo.x, mid.y, mid.z), Vector3(0.0, 0.0, -90.0), _walls)
	_plane(Vector2(size.y, size.z), Vector3(hi.x, mid.y, mid.z), Vector3(0.0, 0.0, 90.0), _walls)

	Settings.changed.connect(_apply_theme)
	_apply_theme()


func _apply_theme() -> void:
	var theme: Dictionary = THEMES[clampi(Settings.room_theme, 0, THEMES.size() - 1)]
	_env.background_color = theme["sky"]
	_env.ambient_light_energy = theme["ambient"]
	_sun.light_energy = theme["sun"]
	for mat: ShaderMaterial in [_walls, _floor]:
		mat.set_shader_parameter("base_color", theme["floor"] if mat == _floor else theme["wall"])
		mat.set_shader_parameter("line_color", theme["line"])
		mat.set_shader_parameter("major_color", theme["major"])
		mat.set_shader_parameter("eye_color", theme["eye"])


func _plane(plane_size: Vector2, pos: Vector3, rotation_deg: Vector3, mat: Material) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = plane_size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.rotation_degrees = rotation_deg
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
