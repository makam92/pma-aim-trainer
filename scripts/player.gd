extends Node3D
## First-person view. Raw mouse counts turn the view exactly like CS2: 0.022° × sensitivity per count.

const Defs = preload("res://scripts/defs.gd")

var yaw := 0.0     ## degrees, positive turns left
var pitch := 0.0   ## degrees, positive looks up
## The view's share of the weapon's kick (pitch up, yaw left), on top of where you aim, like CS2's
## view punch. Aiming and shooting start from yaw and pitch.
var view_kick := Vector2.ZERO
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = Defs.CS_VFOV
	camera.near = 0.05
	camera.far = 200.0
	camera.position = Vector3(0.0, Defs.EYE_HEIGHT, 0.0)
	add_child(camera)
	camera.make_current()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# screen_relative is the raw, unscaled motion; with a captured mouse on Windows it comes
	# from raw input, so Windows pointer speed and acceleration don't affect it.
	var k := Settings.sensitivity * Defs.M_YAW
	turn(-motion.screen_relative.x * k, -motion.screen_relative.y * k)


func turn(d_yaw: float, d_pitch: float) -> void:
	yaw += d_yaw
	pitch = clampf(pitch + d_pitch, -89.0, 89.0)
	camera.rotation_degrees = Vector3(pitch + view_kick.x, yaw + view_kick.y, 0.0)


func set_view_kick(kick: Vector2) -> void:
	view_kick = kick
	turn(0.0, 0.0)


func reset() -> void:
	yaw = 0.0
	pitch = 0.0
	view_kick = Vector2.ZERO
	position = Vector3.ZERO
	turn(0.0, 0.0)


func eye_position() -> Vector3:
	return camera.global_position


func aim_dir() -> Vector3:
	return Defs.dir_from_angles(yaw, pitch)
