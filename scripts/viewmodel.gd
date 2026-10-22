extends Control
## The AK in first person, like CS2's viewmodel: CS2's own arms holding the AK, played with CS2's own
## first-person clips (pulling it out, holding it, firing). It has its own camera with CS2's
## viewmodel FOV and default offsets and is drawn on top of the game view, so it never clips into
## anything. Needs the CS2 files imported (Settings → CS2-filer); without them nothing shows.

const UNIT := 0.0254
## viewmodel_offset_x, _y, _z in units (right, forward, up): CS2's default "desktop" position.
const OFFSET := Vector3(1.0, 1.0, -1.0)
const FLASH_SECONDS := 0.045

var _viewport: SubViewport
var _camera: Camera3D
var _rig: Node3D
var _player: AnimationPlayer
var _flash: Node3D
var _flash_light: OmniLight3D
var _tip: Node3D
var _flash_left := 0.0
var _flash_frames := 0
var _active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_build_stage()
	get_viewport().size_changed.connect(_resize)
	Settings.changed.connect(_apply_settings)
	# Built when the CS2 files have loaded, and again after they're imported anew.
	Agents.loaded.connect(_build_rig)
	if Agents.is_loaded:
		_build_rig()
	_resize()
	visible = false


## Shows the AK while a mode is running (if it's turned on and the export is there).
func set_active(on: bool) -> void:
	_active = on
	_apply_settings()


## Whether the AK is in your hands right now, which also means it fires at its own rate.
func is_shown() -> bool:
	return visible


## Pulls the AK out, as when you switch to it in CS2.
func deploy() -> void:
	if _player and _player.has_animation("draw"):
		_player.stop()
		_player.play("draw")


## One shot: the firing clip from the start, and a muzzle flash.
func fire() -> void:
	if _player == null or not visible:
		return
	_player.stop()
	_player.play("shoot" if _player.has_animation("shoot") else "idle")
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.15)
	_flash_light.visible = true
	_flash_left = FLASH_SECONDS
	_flash_frames = 2


## Where the AK's muzzle shows on screen, in the game view's coordinates, or null without the AK.
func muzzle_on_screen() -> Variant:
	if not visible or _tip == null:
		return null
	var pixel := _camera.unproject_position(_tip.global_position)
	return pixel * get_viewport().get_visible_rect().size / Vector2(_viewport.size)


func _process(delta: float) -> void:
	# The flash lasts FLASH_SECONDS, but always gets drawn at least twice, also at low frame rates.
	if _flash and _flash.visible:
		_flash_left -= delta
		_flash_frames -= 1
		if _flash_left <= 0.0 and _flash_frames <= 0:
			_flash.visible = false
			_flash_light.visible = false


func _apply_settings() -> void:
	visible = _active and Settings.viewmodel and _rig != null
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	# viewmodel_fov is horizontal at 4:3, like CS2's main FOV; wider screens see more at the sides.
	_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(Settings.viewmodel_fov) / 2.0) * 0.75))


func _resize() -> void:
	_viewport.size = get_viewport().get_texture().get_size()


## Camera and light. The arms point along +Z with the eye at the origin, as CS2 exports them.
func _build_stage() -> void:
	_camera = Camera3D.new()
	_camera.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.01
	_camera.far = 5.0
	_viewport.add_child(_camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.52)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.95, 0.86)
	_viewport.add_child(sun)


## CS2's arms with the AK on their weapon bone, and the clips moved onto them.
func _build_rig() -> void:
	if _rig:
		_rig.free()
		_rig = null
		_player = null
		_tip = null
		_flash = null
		_flash_light = null
	if not Agents.has_viewmodel():
		_apply_settings()
		return
	_rig = Node3D.new()
	_rig.position = Vector3(-OFFSET.x, OFFSET.z, OFFSET.y) * UNIT   # right is -X, forward +Z
	_viewport.add_child(_rig)
	var arms: Node3D = Agents.viewmodel_arms.duplicate()
	_rig.add_child(arms)
	var skeleton := Agents.find_skeleton(arms)
	var hold := BoneAttachment3D.new()
	hold.bone_name = "wpn"
	skeleton.add_child(hold)
	var ak: Node3D = (Agents.weapons[Agents.VIEWMODEL_WEAPON] as Node3D).duplicate()
	ak.transform = Agents.weapon_attach[Agents.VIEWMODEL_WEAPON]
	hold.add_child(ak)
	_build_flash(skeleton)

	_player = AnimationPlayer.new()
	_rig.add_child(_player)
	_player.root_node = _player.get_path_to(_rig)
	var library := AnimationLibrary.new()
	for clip: String in Agents.viewmodel_clips:
		library.add_animation(clip, _retarget(Agents.viewmodel_clips[clip], _rig, skeleton, Agents.find_skeleton(ak)))
	_player.add_animation_library("", library)
	_player.animation_finished.connect(func(clip: StringName) -> void:
		if clip != &"idle":
			_player.play("idle"))
	_player.play("idle")
	_apply_settings()


## The clip with its tracks moved from the clip's own skeletons onto the arms and the AK, keeping
## only bones they have. The AK's own root bones stay put: the hand's "wpn" bone carries the AK, and
## the clip only moves its parts (bolt, magazine, trigger).
static func _retarget(source: Animation, rig: Node3D, arms: Skeleton3D, ak: Skeleton3D) -> Animation:
	var anim := source.duplicate() as Animation
	for t in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(t))
		var bone := path.get_slice(":", 1)
		var target: Skeleton3D = arms if path.contains("characters_viewmodel") else (ak if path.contains("weapons_ak47") else null)
		if target == ak and bone in ["weapon", "weapon_offset"]:
			target = null
		if target == null or bone == "" or target.find_bone(bone) < 0:
			anim.remove_track(t)
			continue
		anim.track_set_path(t, NodePath("%s:%s" % [rig.get_path_to(target), bone]))
	return anim


## A short star of light at the muzzle, and a light so the arms catch it.
func _build_flash(skeleton: Skeleton3D) -> void:
	var tip := BoneAttachment3D.new()
	tip.bone_name = "wpnTip"
	skeleton.add_child(tip)
	_tip = tip
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
	gradient.set_color(1, Color(1.0, 0.55, 0.15, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = mat
	_flash = Node3D.new()
	_flash.add_child(mesh)
	_flash.visible = false
	tip.add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.light_energy = 1.6
	_flash_light.omni_range = 0.6
	_flash_light.visible = false
	tip.add_child(_flash_light)
