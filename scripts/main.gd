extends Node
## Owns the room, the player, the screens and the active training mode.

const Defs = preload("res://scripts/defs.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Crosshair = preload("res://scripts/ui/crosshair.gd")
const Menu = preload("res://scripts/ui/menu.gd")
const SettingsScreen = preload("res://scripts/ui/settings_screen.gd")
const StatsScreen = preload("res://scripts/ui/stats_screen.gd")
const PauseScreen = preload("res://scripts/ui/pause_screen.gd")
const ResultsScreen = preload("res://scripts/ui/results_screen.gd")
const PlaylistScreen = preload("res://scripts/ui/playlist_screen.gd")
const PlaylistEditor = preload("res://scripts/ui/playlist_editor.gd")
const Viewmodel = preload("res://scripts/viewmodel.gd")
const WeaponAK = preload("res://scripts/weapon_ak.gd")
const Impacts = preload("res://scripts/impacts.gd")
const DummyScript = preload("res://scripts/dummy.gd")
## CS2's AK fires every 0.1 s (600 shots a minute); with it in hand, faster clicks don't fire.
const AK_CYCLE := 0.1
const TargetScript = preload("res://scripts/target.gd")

const MODES := {
	"grid": preload("res://scripts/modes/grid_mode.gd"),
	"flick": preload("res://scripts/modes/flick_mode.gd"),
	"micro": preload("res://scripts/modes/micro_mode.gd"),
	"track": preload("res://scripts/modes/track_mode.gd"),
	"confirm": preload("res://scripts/modes/confirm_mode.gd"),
	"tconfirm": preload("res://scripts/modes/track_confirm_mode.gd"),
	"punch": preload("res://scripts/modes/punch_mode.gd"),
	"strafeaim": preload("res://scripts/modes/strafeaim_mode.gd"),
	"strafe": preload("res://scripts/modes/strafe_mode.gd"),
}
const MODE_TITLES := {
	"grid": "Gridshot", "flick": "Flicks", "micro": "Micro Adjustments", "track": "Tracking",
	"confirm": "Target Confirmation", "tconfirm": "Tracking Confirmation", "punch": "Aim Punch",
	"strafeaim": "Strafe Aim", "strafe": "Counter-strafe",
}

enum State { MENU, PLAYING, PAUSED, RESULTS }

var state := State.MENU
var world: Node3D
var player: Node3D
var hud: Control
var crosshair: Control
var viewmodel: Control
var impacts: Node3D
var ak := WeaponAK.new()
var menu: Control
var settings_screen: Control
var stats_screen: Control
var pause_screen: Control
var results_screen: Control
var playlist_screen: Control
var playlist_editor: Control
var mode: Node = null
var mode_id := ""
## The 3D world is rendered here at the chosen resolution (the window's own by default) and scaled
## up to the window, like CS2 at a lower resolution; the AK, crosshair and menus go on top.
var game_view: SubViewport
var view_camera: Camera3D

## The playlist's runs in order (a mode id per run), and the position in it, or -1 outside it.
var _steps: Array = []
var _playlist_index := -1
## step → {"score", "variant", "best"} for each finished run.
var _playlist_runs := {}

var _paused_us := 0
var _pause_began := 0
var _last_shot := -INF
var _shots_fired := 0
var _trigger_down := false
var _ui_layer: CanvasLayer
var _ui_root: Control
var _view_rect: TextureRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = World.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	impacts = Impacts.new()
	impacts.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(impacts)
	_build_game_view()

	# The AK in first person goes over the room and under the crosshair.
	var hands_layer := CanvasLayer.new()
	hands_layer.layer = 0
	add_child(hands_layer)
	viewmodel = Viewmodel.new()
	hands_layer.add_child(viewmodel)
	# The crosshair is drawn in screen pixels on its own layer.
	var aim_layer := CanvasLayer.new()
	aim_layer.layer = 1
	add_child(aim_layer)
	crosshair = Crosshair.new()
	aim_layer.add_child(crosshair)
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 2
	add_child(_ui_layer)
	_ui_root = Control.new()
	_ui_root.theme = UI.make_theme()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)

	hud = Hud.new()
	menu = Menu.new()
	settings_screen = SettingsScreen.new()
	stats_screen = StatsScreen.new()
	pause_screen = PauseScreen.new()
	results_screen = ResultsScreen.new()
	playlist_screen = PlaylistScreen.new()
	playlist_editor = PlaylistEditor.new()
	playlist_editor.titles = MODE_TITLES
	for screen: Control in [hud, menu, settings_screen, stats_screen, pause_screen, results_screen, playlist_screen, playlist_editor]:
		_ui_root.add_child(screen)
	get_viewport().size_changed.connect(_update_ui_scale)
	Settings.changed.connect(_update_ui_scale)
	_update_ui_scale()
	get_viewport().size_changed.connect(_update_game_view)
	Settings.changed.connect(_update_game_view)
	_update_game_view()

	menu.start_requested.connect(start_mode)
	menu.playlist_requested.connect(start_playlist)
	menu.playlist_edit_requested.connect(func() -> void: _show(playlist_editor))
	menu.settings_requested.connect(func() -> void: _show(settings_screen))
	menu.stats_requested.connect(func() -> void: _show(stats_screen))
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	settings_screen.back_requested.connect(_settings_back)
	stats_screen.back_requested.connect(show_menu)
	pause_screen.resume_requested.connect(_resume)
	pause_screen.restart_requested.connect(restart)
	pause_screen.menu_requested.connect(show_menu)
	pause_screen.settings_requested.connect(func() -> void: _show(settings_screen))
	pause_screen.skip_requested.connect(_playlist_skip)
	pause_screen.jump_requested.connect(_playlist_jump)
	results_screen.again_requested.connect(restart)
	results_screen.next_requested.connect(_playlist_next)
	results_screen.menu_requested.connect(show_menu)
	playlist_screen.menu_requested.connect(show_menu)
	playlist_editor.back_requested.connect(show_menu)

	show_menu()
	if OS.get_cmdline_user_args().has("--import-check"):
		print("[import] Source 2 Viewer: %s\n[import] CS2: %s" % [Importer.find_cli(), Importer.find_cs2()])
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--import-cs2"):
		_import_cs2()
	elif OS.get_cmdline_user_args().has("--selftest"):
		_self_test()
	elif Settings.dev_mode:
		_run_tour()


func _process(delta: float) -> void:
	if state == State.MENU:
		player.turn(delta * 2.5, 0.0)
	elif state == State.PLAYING and _ak_punch():
		player.set_view_kick(ak.view_punch(game_time()))
		if _trigger_down and _ak_recoil():
			_fire()   # the AK is automatic: holding the trigger keeps firing
	elif player.view_kick != Vector2.ZERO:
		player.set_view_kick(Vector2.ZERO)


func _input(event: InputEvent) -> void:
	match state:
		State.PLAYING:
			var click := event as InputEventMouseButton
			if click and click.button_index == MOUSE_BUTTON_LEFT:
				if click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					_capture_mouse()
				else:
					_trigger_down = click.pressed
					if click.pressed:
						_fire()
				get_viewport().set_input_as_handled()
				return
			var key := event as InputEventKey
			if key == null or key.echo:
				return
			if key.physical_keycode in Defs.MOVE_KEYS:
				mode.key_event(Defs.MOVE_KEYS[key.physical_keycode], key.pressed, game_time())
			elif _pressed(event, KEY_ESCAPE):
				_pause()
				get_viewport().set_input_as_handled()
			elif _pressed(event, KEY_R):
				restart()
		State.PAUSED:
			if _pressed(event, KEY_ESCAPE):
				# From the settings opened in the pause menu, Esc goes back to the pause menu.
				if settings_screen.visible:
					_show(pause_screen)
				else:
					_resume()
				get_viewport().set_input_as_handled()
			elif _pressed(event, KEY_R) and not settings_screen.visible:
				restart()
		State.RESULTS:
			if _playlist_index >= 0 and (_pressed(event, KEY_ENTER) or _pressed(event, KEY_SPACE)):
				_playlist_next()
			elif _pressed(event, KEY_R) or _pressed(event, KEY_ENTER) or _pressed(event, KEY_SPACE):
				restart()
			elif _pressed(event, KEY_ESCAPE):
				show_menu()
		State.MENU:
			if _pressed(event, KEY_ESCAPE) and not menu.visible:
				show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING and not Settings.dev_mode:
		_pause()


## Seconds of game time. It stands still while paused, so pauses never count in a run.
func game_time() -> float:
	var us := Time.get_ticks_usec() - _paused_us
	if state == State.PAUSED:
		us = _pause_began - _paused_us
	return us / 1000000.0


func show_menu() -> void:
	_end_mode()
	_playlist_index = -1
	state = State.MENU
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	crosshair.visible = false
	viewmodel.set_active(false)
	player.reset()
	_show(menu)


func start_mode(id: String) -> void:
	_end_mode()
	mode_id = id
	mode = MODES[id].new()
	mode.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(mode)
	mode.setup(self)
	mode.finished.connect(_on_finished)
	player.reset()
	hud.visible = true
	if _playlist_index >= 0:
		hud.set_note("DAGENS PASS  %d/%d  ·  %s" % [_playlist_index + 1, _steps.size(), _step_name(_playlist_index)])
	crosshair.visible = true
	viewmodel.set_active(true)
	viewmodel.deploy()
	impacts.clear()
	ak.reset(game_time())
	_shots_fired = 0
	_last_shot = -INF
	_trigger_down = false
	_show(null)
	state = State.PLAYING
	get_tree().paused = false
	_capture_mouse()
	mode.begin()


func restart() -> void:
	start_mode(mode_id)


func _end_mode() -> void:
	if mode:
		remove_child(mode)
		mode.queue_free()
		mode = null
	hud.reset()


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	_trigger_down = false
	_pause_began = Time.get_ticks_usec()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_screen.set_playlist(_playlist_index >= 0)
	if _playlist_index >= 0:
		pause_screen.show_playlist(_steps, _playlist_index, _playlist_runs, MODE_TITLES)
	_show(pause_screen)


func _resume() -> void:
	if state != State.PAUSED:
		return
	_paused_us += Time.get_ticks_usec() - _pause_began
	state = State.PLAYING
	get_tree().paused = false
	_show(null)
	_capture_mouse()
	mode.on_resume()


## One shot, if the gun is ready. With the AK's recoil on, the bullet goes where CS2's AK would send
## it (its kick so far plus its inaccuracy); otherwise exactly where you aim, unless an enemy's hits
## have punched your aim (Aim Punch). With the AK in hand, shots never come faster than the AK fires.
func _fire() -> void:
	var t := game_time()
	var eye: Vector3 = player.eye_position()
	var dir: Vector3 = player.aim_dir()
	if _ak_recoil():
		if not ak.can_fire(t):
			return
		dir = _bullet_dir(ak.fire(t))
	else:
		if viewmodel.is_shown() and t - _last_shot < AK_CYCLE:
			return
		if _ak_punch():
			dir = _bullet_dir({"punch": ak.aim_punch(t), "spread": Vector2.ZERO})
	_last_shot = t
	mode.shot_hit = false
	mode.shoot(eye, dir)
	viewmodel.fire()
	if Settings.impacts and mode_id != "strafe" and mode_id != "track":
		var muzzle: Variant = viewmodel.muzzle_on_screen()
		_sync_view_camera()
		var start: Vector3 = view_camera.project_position(muzzle, 1.0) if muzzle != null \
			else eye + player.camera.global_basis * Vector3(0.15, -0.12, -0.6)
		impacts.shot(eye, dir, mode.shot_hit, _shots_fired % WeaponAK.TRACER_FREQUENCY == 0, start)
	_shots_fired += 1


## Where a bullet goes: where you aim, turned by the AK's kick, then off by its inaccuracy.
func _bullet_dir(shot: Dictionary) -> Vector3:
	var punch: Vector2 = shot["punch"]
	var forward := Defs.dir_from_angles(player.yaw + punch.y, player.pitch + punch.x)
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward)
	var spread: Vector2 = shot["spread"]
	return (forward + right * spread.x + up * spread.y).normalized()


## Whether this mode shoots with the AK's recoil: the target modes, when it's turned on.
func _ak_recoil() -> bool:
	return Settings.ak_recoil and mode_id in Defs.RECOIL_MODES


## Whether the AK's punch moves the view and the bullets: with its recoil, and always in Aim Punch,
## where the enemy's hits punch your aim.
func _ak_punch() -> bool:
	return _ak_recoil() or mode_id == "punch"


## Settings return to wherever they were opened from: the pause menu during a run, else the main menu.
func _settings_back() -> void:
	if state == State.PAUSED:
		_show(pause_screen)
	else:
		show_menu()


func _on_finished(result: Dictionary) -> void:
	var variant: String = result.get("variant", "")
	var previous: Variant = Stats.best(mode_id, variant)
	var is_best := Stats.add(mode_id, result)
	state = State.RESULTS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	crosshair.visible = false
	viewmodel.set_active(false)
	var badge := "NYTT PERSONBÄSTA!"
	var badge_color := UI.GOOD
	if previous == null:
		badge = "Första rundan med de här inställningarna"
		badge_color = UI.DIM
	elif not is_best:
		badge = "Personbästa: " + UI.main_value(mode_id, previous)
		badge_color = UI.DIM
	var title: String = MODE_TITLES[mode_id]
	var next_label := ""
	if _playlist_index >= 0:
		# Running a run again (R) replaces its result.
		_playlist_runs[_playlist_index] = {"score": result.get("score", 0), "variant": variant, "best": is_best and previous != null}
		title = "Dagens pass %d/%d  ·  %s" % [_playlist_index + 1, _steps.size(), _step_name(_playlist_index)]
		if _playlist_index + 1 < _steps.size():
			next_label = "Nästa: %s  (Enter)" % _step_name(_playlist_index + 1)
		else:
			next_label = "Se hela passet  (Enter)"
	results_screen.show_result(title, variant, MODES[mode_id].summary(result), badge, badge_color, next_label)
	_show(results_screen)


func start_playlist() -> void:
	_steps = []
	for entry: Array in Settings.playlist_entries():
		for i in entry[1]:
			_steps.append(entry[0])
	if _steps.is_empty():
		return
	_playlist_runs = {}
	_playlist_index = 0
	start_mode(_steps[0])


## "Tracking 2/3": the mode of a playlist step and which of its runs it is.
func _step_name(step: int) -> String:
	var id: String = _steps[step]
	var first: int = _steps.find(id)
	return "%s %d/%d" % [MODE_TITLES[id], step - first + 1, _steps.count(id)]


func _playlist_next() -> void:
	if _playlist_index < 0:
		return
	_playlist_index += 1
	if _playlist_index < _steps.size():
		start_mode(_steps[_playlist_index])
	else:
		_finish_playlist()


## From the playlist in the pause menu: go straight to any round, earlier or later. The playlist
## carries on in order from there; rounds jumped over count as skipped unless you go back to them.
func _playlist_jump(step: int) -> void:
	if _playlist_index < 0 or step < 0 or step >= _steps.size():
		return
	_playlist_index = step
	start_mode(_steps[step])


## From the pause menu: skip the rest of this exercise's runs and go on to the next exercise.
func _playlist_skip() -> void:
	if _playlist_index < 0:
		return
	var id: String = _steps[_playlist_index]
	while _playlist_index + 1 < _steps.size() and _steps[_playlist_index + 1] == id:
		_playlist_index += 1
	_playlist_next()


func _finish_playlist() -> void:
	# Per mode in this playlist, in play order: its scores, the variant, and whether any run was a
	# new personal best.
	var order: Array = []
	for id: String in _steps:
		if not order.has(id):
			order.append(id)
	var results := {}
	for id: String in order:
		var scores: Array = []
		var variant := ""
		var best := false
		for step in _steps.size():
			if _steps[step] == id and _playlist_runs.has(step):
				var run: Dictionary = _playlist_runs[step]
				scores.append(run["score"])
				variant = run["variant"]
				best = best or run["best"]
		results[id] = {"scores": scores, "variant": variant, "best": best} if not scores.is_empty() else null
	var previous: Variant = Stats.last_playlist()
	Stats.add_playlist(results)
	_playlist_index = -1
	_end_mode()
	state = State.MENU
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.visible = false
	crosshair.visible = false
	viewmodel.set_active(false)
	player.reset()
	playlist_screen.show_summary(order, MODE_TITLES, results, previous, Stats.playlist_streak())
	_show(playlist_screen)


## The game view: the shared 3D world through its own camera, which follows yours, shown under
## everything else. The window itself doesn't draw the 3D world.
func _build_game_view() -> void:
	get_viewport().disable_3d = true
	game_view = SubViewport.new()
	game_view.msaa_3d = get_viewport().msaa_3d
	game_view.screen_space_aa = get_viewport().screen_space_aa
	game_view.use_taa = get_viewport().use_taa
	game_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(game_view)
	view_camera = Camera3D.new()
	view_camera.keep_aspect = player.camera.keep_aspect
	view_camera.near = player.camera.near
	view_camera.far = player.camera.far
	game_view.add_child(view_camera)
	view_camera.make_current()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bars := ColorRect.new()   # behind the view, for black bars
	bars.color = Color.BLACK
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bars)
	_view_rect = TextureRect.new()
	_view_rect.texture = game_view.get_texture()
	_view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Scaled up smoothly, like a graphics card stretching CS2 at a lower resolution.
	_view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_view_rect)
	RenderingServer.frame_pre_draw.connect(_sync_view_camera)


## Renders the game view at the chosen resolution (the window's own by default) and stretches it to
## the window, or keeps its shape with black bars; the AK in hand follows along.
func _update_game_view() -> void:
	var window := Vector2(get_window().size)
	var res := Vector2(Settings.render_size())
	if res == Vector2.ZERO:
		res = window
	if res.x < 1.0 or res.y < 1.0:
		res = Settings.UI_BASE   # no window yet (or none at all, without a display)
	game_view.size = Vector2i(res)
	_view_rect.stretch_mode = TextureRect.STRETCH_SCALE if Settings.stretched else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewmodel.set_view_size(Vector2i(res), not Settings.stretched)


## The view's camera takes your camera's place right before each frame is drawn, so it's never late.
func _sync_view_camera() -> void:
	view_camera.global_transform = player.camera.global_transform
	view_camera.fov = player.camera.fov


## The UI is laid out for 1920x1080; at smaller render resolutions it's scaled down to fit.
func _update_ui_scale() -> void:
	var view := get_viewport().get_visible_rect().size
	var s := minf(1.0, minf(view.x / Settings.UI_BASE.x, view.y / Settings.UI_BASE.y))
	_ui_layer.scale = Vector2(s, s)
	_ui_root.size = view / s


func _show(screen: Control) -> void:
	for s: Control in [menu, settings_screen, stats_screen, pause_screen, results_screen, playlist_screen, playlist_editor]:
		s.visible = s == screen
	if screen and screen.has_method("refresh"):
		screen.refresh()


func _capture_mouse() -> void:
	if not Settings.dev_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pressed(event: InputEvent, keycode: Key) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.physical_keycode == keycode


# --- Importing the CS2 files without a window: godot --headless --path . -- --import-cs2 ---

func _import_cs2() -> void:
	Importer.progress.connect(func(step: int, steps: int, text: String) -> void:
		print("[import] %d/%d %s" % [step + 1, steps, text]))
	Importer.finished.connect(func(ok: bool, message: String) -> void:
		print("[import] " + message)
		get_tree().quit(0 if ok else 1))
	if not Agents.is_loaded:
		await Agents.loaded
	Importer.start()


# --- Self-test without a window: godot --headless --path . -- --selftest ---

## Shooting: with the AK's recoil on, holding the trigger sprays at the AK's rate, kicks the view
## and leaves a hole per miss; with it off, holding the trigger fires once.
func _self_test() -> void:
	Stats.persist = false
	if not Agents.is_loaded:
		await Agents.loaded
	var failures := 0
	Settings.ak_recoil = true
	start_mode("grid")
	player.turn(0.0, 30.0)   # at the ceiling, away from the targets, so every shot misses
	for i in 10:
		await get_tree().process_frame
	_trigger_down = true
	_fire()
	var start := game_time()
	var times: Array[String] = ["0"]
	while game_time() - start < 0.95:
		var before := _shots_fired
		await get_tree().process_frame
		if _shots_fired != before:
			times.append(str(roundi((game_time() - start) * 1000.0)))
	_trigger_down = false
	print("[självtest] skott vid (ms): %s" % ", ".join(PackedStringArray(times)))
	var sprayed := _shots_fired
	var kick: Vector2 = player.view_kick
	var holes: int = (impacts.get("_holes") as Array).size()
	print("[självtest] rekyl på: %d skott på 0,95 s, vyn sparkade %.2f° upp, %d kulhål" % [sprayed, kick.x, holes])
	if sprayed != 10 or kick.x < 0.5 or holes != sprayed:
		failures += 1
	Settings.ak_recoil = false
	start_mode("grid")
	player.turn(0.0, 30.0)
	_trigger_down = true
	_fire()
	await _wait(0.5)
	_trigger_down = false
	print("[självtest] rekyl av: %d skott när avtryckaren hålls in" % _shots_fired)
	if _shots_fired != 1:
		failures += 1
	failures += await _punch_check()
	failures += await _strafeaim_check()
	print("OK" if failures == 0 else "FEL: %d" % failures)
	get_tree().quit(failures)


## Aim Punch: his first hit kicks the view and sends a shot fired straight at his head over it; once
## the punch has settled, the same shot kills. Without shooting back you die after three hits, or
## four with kevlar, which also punches much less.
func _punch_check() -> int:
	var failures := 0
	for armor in 2:
		Settings.punch_armor = armor
		start_mode("punch")
		mode.shoot(player.eye_position(), Vector3.FORWARD)   # the start target, straight ahead
		while mode.get("hits_taken") == 0:
			await get_tree().process_frame
		await get_tree().process_frame
		var kick: float = player.view_kick.x
		var enemy: Node3D = mode.get("_dummy")
		_aim_at(enemy.head_centre())
		var high: float = ak.aim_punch(game_time()).x
		_fire()
		var at_once: bool = mode.get("kills") == 1
		if not at_once:
			while game_time() - float(mode.get("_last_hit")) < 0.35:
				await get_tree().process_frame
			_aim_at(enemy.head_centre())
			_fire()
		var settled: bool = mode.get("kills") == 1
		# The next duel without shooting back.
		var taken: int = mode.get("hits_taken")
		var waited := 0.0
		while mode.get("deaths") == 0 and waited < 6.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
		var to_die: int = mode.get("hits_taken") - taken
		print("[självtest] aim punch %s: vyn sparkade %s° upp och kulan gick %s° över, skott direkt på huvudet: %s, efter rycket: %s, död efter %d träffar" % [
			Defs.ARMOR[armor].to_lower(), UI.dec(kick), UI.dec(high), "kill" if at_once else "miss",
			"–" if at_once else ("kill" if settled else "miss"), to_die])
		var expected_hits := 3 if armor == 0 else 4
		var kick_ok := kick > 1.0 if armor == 0 else kick > 0.1 and kick < 0.8
		if not kick_ok or not settled or to_die != expected_hits or (armor == 0 and at_once):
			failures += 1
	Settings.punch_armor = 0
	return failures


## Strafe Aim: a shot on a target at full speed counts; one fired after stopping doesn't.
func _strafeaim_check() -> int:
	start_mode("strafeaim")
	await _wait(0.1)
	mode.key_event("d", true, game_time())
	await _wait(0.6)
	var targets: Array = mode.get("_targets")
	_aim_at((targets[0] as Node3D).global_position)
	_fire()
	var moving_hit: bool = mode.get("hits") == 1
	mode.key_event("d", false, game_time())
	await _wait(0.6)
	_aim_at((targets[0] as Node3D).global_position)
	_fire()
	var still_ignored: bool = mode.get("hits") == 1 and mode.get("still_shots") == 1
	print("[självtest] strafe aim: träff i full fart räknas: %s, skott efter att du stannat räknas inte: %s" % [
		"ja" if moving_hit else "NEJ", "ja" if still_ignored else "NEJ"])
	return int(not moving_hit) + int(not still_ignored)


# --- Screenshot tour for development: godot --path . -- --tour=<folder> ---

func _run_tour() -> void:
	Stats.persist = false
	if not Agents.is_loaded:
		await Agents.loaded
	print("[tour] CS2-modeller: %s (%d ms)" % ["ja" if Agents.available() else "nej", Agents.load_ms])
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tour="):
			dir = arg.substr(7)
	if OS.get_cmdline_user_args().has("--closeup"):
		await _closeups(dir)
		get_tree().quit()
		return
	await _snap(dir, "01_menu")
	_show(settings_screen)
	await _snap(dir, "02_settings")
	_fake_history()
	_show(stats_screen)
	await _snap(dir, "03_stats")
	stats_screen.show_tab("tconfirm")
	await _snap(dir, "03_stats_tconfirm")
	stats_screen.show_tab("punch")
	await _snap(dir, "03_stats_punch")
	stats_screen.show_tab("playlist")
	await _snap(dir, "03_stats_playlist")
	stats_screen.show_tab("grid")
	start_mode("flick")
	await _snap(dir, "04_flick_ring")
	await _wait(1.0)
	await _snap(dir, "04_flick_target")
	start_mode("confirm")
	await _wait(0.3)
	await _snap(dir, "05_confirm")
	mode.call("_fail", "MISS")
	await _wait(0.1)
	await _snap(dir, "06_confirm_fail")
	start_mode("strafe")
	await _wait(0.2)
	mode.key_event("d", true, game_time())
	await _wait(0.55)
	mode.key_event("d", false, game_time())
	mode.key_event("a", true, game_time())
	await _wait(0.085)
	mode.shoot(player.eye_position(), player.aim_dir())
	await _wait(0.06)
	mode.key_event("a", false, game_time())
	await _wait(0.3)
	await _snap(dir, "07_strafe")
	await _strafe_checks()
	await _snap(dir, "07_strafe_overlap")
	_pause()
	await _snap(dir, "08_pause")
	pause_screen.settings_requested.emit()
	await _snap(dir, "08_pause_settings")
	_settings_back()
	print("[tour] tillbaka till paus: %s" % pause_screen.visible)
	_resume()
	Settings.resolution = 5
	Settings.apply()
	show_menu()
	await _snap(dir, "12_menu_1280x1024")
	start_mode("strafe")
	await _wait(0.3)
	await _snap(dir, "12_strafe_1280x1024")
	await _crosshair_check(dir)
	Settings.resolution = 0
	Settings.apply()
	start_mode("track")
	await _wait(1.0)
	await _snap(dir, "10_track_countdown")
	await _wait(2.5)
	await _snap(dir, "10_track_running")
	Settings.flick_target = 1
	start_mode("flick")
	await _wait(1.3)
	await _snap(dir, "04_flick_sphere")
	Settings.flick_target = 0
	Settings.room_theme = 1
	Settings.apply()
	start_mode("confirm")
	await _wait(0.2)
	mode.call("_on_hit")
	await _snap(dir, "05_confirm_dark")
	Settings.room_theme = 0
	Settings.apply()
	# The daily playlist: a result in the middle of it, then the summary at the end.
	start_playlist()
	_playlist_index = 4
	mode_id = "track"
	_on_finished(_fake_result("track"))
	await _snap(dir, "13_playlist_results")
	for step in _steps.size():
		var fake := _fake_result(_steps[step])
		_playlist_runs[step] = {"score": roundi(float(fake["score"]) * (0.92 + 0.04 * (step % 3))),
			"variant": fake["variant"], "best": step == 5}
	_playlist_index = _steps.size() - 1
	_playlist_next()
	await _snap(dir, "13_playlist_summary")
	show_menu()
	await _snap(dir, "13_menu_after_playlist")
	# Your own playlist: Counter-strafe once, then Gridshot twice; the rest skipped.
	Settings.update("playlist", [["strafe", 1], ["grid", 2], ["flick", 0]])
	_show(playlist_editor)
	await _snap(dir, "17_playlist_editor")
	show_menu()
	await _snap(dir, "17_menu_own_playlist")
	start_playlist()
	print("[pass] egen lista: %s" % ", ".join(PackedStringArray(_steps)))
	Settings.update("playlist", [])
	start_playlist()
	print("[pass] standard: %d rundor, %s först" % [_steps.size(), _steps[0]])
	# The playlist beside the pause menu, in round 2: jump straight to Tracking 1/3.
	_playlist_runs[0] = {"score": 86, "variant": Defs.variant("grid", Settings), "best": false}
	_playlist_index = 1
	start_mode(_steps[1])
	_pause()
	await _snap(dir, "19_pause_playlist")
	var first_tracking: int = _steps.find("track")
	_playlist_jump(first_tracking)
	print("[pass] hopp till Tracking 1/3: %s" % (mode_id == "track" and _playlist_index == first_tracking and state == State.PLAYING))
	show_menu()
	start_mode("grid")
	await _wait(0.4)
	await _snap(dir, "15_grid")
	start_mode("tconfirm")
	await _wait(0.2)
	mode.call("shoot", player.eye_position(), player.aim_dir())
	await _wait(1.2)
	await _snap(dir, "16_tconfirm")
	# A shot straight at the bot's head must count as a kill; a shot into the air is a miss that
	# keeps the run going.
	var eye: Vector3 = player.eye_position()
	mode.call("shoot", eye, (mode.get("_dummy").head_centre() - eye).normalized())
	print("[tconfirm] kill på huvudet: %s" % (mode.get("kills") == 1))
	mode.call("shoot", eye, Vector3.UP)
	print("[tconfirm] miss utan omstart: %s" % (mode.get("misses") == 1 and mode.get("kills") == 1 and mode.get("phase") == 1))
	# The AK in first person: held, and the frame right after a shot.
	start_mode("flick")
	await _wait(1.4)
	await _snap(dir, "23_viewmodel")
	viewmodel.fire()
	await _wait(0.02)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("23_viewmodel_shot.png"))
	print("[ak] i handen: %s, AK-ljud: %s" % [viewmodel.is_shown(), Sfx.has_ak_sound()])
	# The AK must sit where CS2's own AK skeleton has it on the hand's weapon bone: its trigger
	# 5 cm below and 2 cm behind that bone.
	var rig: Node3D = viewmodel.get("_rig")
	var arm_bones := Agents.find_skeleton(rig)
	var ak_bones: Skeleton3D = null
	for found: Skeleton3D in rig.find_children("*", "Skeleton3D", true, false):
		if found.find_bone("trigger") >= 0:
			ak_bones = found
	var wpn_frame := arm_bones.global_transform * arm_bones.get_bone_global_pose(arm_bones.find_bone("wpn"))
	var expected := wpn_frame * Transform3D(Agents.WEAPON_BASIS, Vector3.ZERO) * Vector3(0.0049, -0.0519, -0.0176)
	var trigger := (ak_bones.global_transform * ak_bones.get_bone_global_pose(ak_bones.find_bone("trigger"))).origin
	print("[ak] avtryckaren %.1f cm från där CS2 har den" % (trigger.distance_to(expected) * 100.0))
	# The AK's spray on the back wall: 30 bullets with the trigger held and nobody pulling down.
	Settings.ak_recoil = true
	start_mode("flick")
	await _wait(0.6)
	_trigger_down = true
	_fire()
	await _wait(0.35)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("24_spray_tracer.png"))
	await _wait(2.6)
	_trigger_down = false
	print("[ak] spray: %d skott, %d kulhål" % [_shots_fired, (impacts.get("_holes") as Array).size()])
	await _wait(0.8)
	await _snap(dir, "24_spray")
	Settings.ak_recoil = false
	# Micro Adjustments: a target close to the crosshair; aiming straight at it and shooting must hit.
	start_mode("micro")
	await _wait(0.8)
	await _snap(dir, "18_micro")
	var micro_target: Node3D = mode.get("_target")
	mode.call("shoot", eye, (micro_target.global_position - eye).normalized())
	print("[micro] träff: %s, nästa mål efter paus: %s" % [mode.get("hits") == 1, mode.get("_target") == null])
	# Aim Punch: the frame his first hit lands, his muzzle flash up close, and losing a duel.
	start_mode("punch")
	mode.shoot(player.eye_position(), Vector3.FORWARD)
	while mode.get("hits_taken") == 0:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("25_punch_hit.png"))
	# Up close, without the AK in hand in front of it.
	var enemy: Node3D = mode.get("_dummy")
	enemy.position = Vector3(0.6, 0.0, -3.0)
	enemy.call("face", player.eye_position())
	viewmodel.set_active(false)
	await get_tree().process_frame
	_aim_at(enemy.call("muzzle_position"))
	enemy.call("muzzle_flash")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("25_punch_flash.png"))
	viewmodel.set_active(true)
	while mode.get("deaths") == 0:
		await get_tree().process_frame
	await _snap(dir, "25_punch_dead")
	# Strafe Aim: at full speed, then a shot after stopping.
	start_mode("strafeaim")
	await _wait(0.3)
	mode.key_event("d", true, game_time())
	await _wait(0.4)
	await _snap(dir, "26_strafeaim")
	mode.key_event("d", false, game_time())
	await _wait(0.6)
	_fire()
	await _snap(dir, "26_strafeaim_still")
	for id: String in Defs.PLAYLIST:
		mode_id = id
		_on_finished(_fake_result(id))
		await _snap(dir, "09_results_" + id)
	get_tree().quit()


## The crosshair as it shows on screen, at the screen's own resolution and at 1280x1024 stretched,
## for a few looks: both sides must be the same, around the middle of the screen.
func _crosshair_check(dir: String) -> void:
	var saved := [Settings.crosshair_color, Settings.crosshair_length, Settings.crosshair_gap,
		Settings.crosshair_thickness, Settings.crosshair_outline, Settings.crosshair_dot, Settings.resolution]
	Settings.crosshair_color = 3   # magenta, which nothing else on screen is
	Settings.crosshair_outline = false
	Settings.crosshair_dot = false
	start_mode("grid")
	hud.visible = false
	viewmodel.set_active(false)
	for res: int in [0, 5]:
		for look: Array in [[2, 1, 2], [3, 2, 1], [5, 3, 3]]:
			Settings.resolution = res
			Settings.crosshair_length = look[0]
			Settings.crosshair_gap = look[1]
			Settings.crosshair_thickness = look[2]
			Settings.apply()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var shape := _crosshair_shape(image)
			print("[hårkors] %-9s längd %d, mellanrum %d, tjocklek %d: %s" % [
				"1280x1024" if res == 5 else "egen", look[0], look[1], look[2], shape["text"]])
			if res == 5 and look[0] == 2:
				var middle := Vector2i(image.get_size() / 2)
				var crop := image.get_region(Rect2i(middle - Vector2i(16, 12), Vector2i(32, 24)))
				crop.resize(256, 192, Image.INTERPOLATE_NEAREST)
				crop.save_png(dir.path_join("27_crosshair_1280x1024.png"))
	Settings.crosshair_color = saved[0]
	Settings.crosshair_length = saved[1]
	Settings.crosshair_gap = saved[2]
	Settings.crosshair_thickness = saved[3]
	Settings.crosshair_outline = saved[4]
	Settings.crosshair_dot = saved[5]
	Settings.resolution = saved[6]
	Settings.apply()


## The crosshair's pixels in a screenshot (magenta): whether they mirror left to right and top to
## bottom, and how far their middle is from the screen's.
func _crosshair_shape(image: Image) -> Dictionary:
	var middle := image.get_size() / 2
	var on := {}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for y in range(middle.y - 40, middle.y + 40):
		for x in range(middle.x - 40, middle.x + 40):
			var c := image.get_pixel(x, y)
			if c.r > 0.85 and c.b > 0.75 and c.g < 0.55:
				on[Vector2i(x, y)] = true
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if on.is_empty():
		return {"ok": false, "text": "syns inte"}
	var mirrored_x := true
	var mirrored_y := true
	for p: Vector2i in on:
		mirrored_x = mirrored_x and on.has(Vector2i(lo.x + hi.x - p.x, p.y))
		mirrored_y = mirrored_y and on.has(Vector2i(p.x, lo.y + hi.y - p.y))
	var centre := Vector2(lo + hi + Vector2i.ONE) / 2.0
	var off := centre - Vector2(middle)
	var ok := mirrored_x and mirrored_y and absf(off.x) <= 0.5 and absf(off.y) <= 0.5
	return {"ok": ok, "text": "%s, %dx%d px, mitten %+.1f/%+.1f px från skärmens%s" % [
		"lika på båda sidor" if mirrored_x and mirrored_y else "OLIKA SIDOR", hi.x - lo.x + 1, hi.y - lo.y + 1,
		off.x, off.y, "" if ok else "  ← FEL"]}


## Plays scripted key presses and shots in the counter-strafe mode and prints how each shot was judged.
func _strafe_checks() -> void:
	var cases := [
		["stillastående", [[0.7, "shoot"]]],
		["för tidigt", [[0.1, "a", true], [0.55, "a", false], [0.0, "d", true], [0.03, "shoot"], [0.1, "d", false]]],
		["släpper bara", [[0.4, "d", true], [0.55, "d", false], [0.12, "shoot"]]],
		["i rörelse", [[0.4, "a", true], [0.5, "shoot"], [0.05, "a", false]]],
		["för lång kontra", [[0.4, "a", true], [0.55, "a", false], [0.0, "d", true], [0.3, "shoot"], [0.05, "d", false]]],
		["mot kanten", [[0.4, "d", true], [1.8, "d", false], [0.05, "shoot"]]],
		["båda samtidigt", [[0.6, "a", true], [0.55, "d", true], [0.08, "a", false], [0.06, "shoot"], [0.05, "d", false]]],
	]
	for case: Array in cases:
		for step: Array in case[1]:
			if step[0] > 0.0:
				await _wait(step[0])
			if step[1] == "shoot":
				mode.shoot(player.eye_position(), player.aim_dir())
			else:
				mode.key_event(step[1], step[2], game_time())
		var verdict: Dictionary = mode.graph.describe(mode.graph.shot)
		print("[strafe] %-16s → %s  |  %s" % [case[0], verdict["title"], verdict["detail"]])
	await _wait(0.3)


## The game view must show the world exactly where your aim and shots go: a small marker in front of
## you shows up on screen right where the camera projects it, at the screen's own resolution and at
## 1280x1024 stretched.
func _alignment_check() -> void:
	start_mode("strafe")
	mode.process_mode = Node.PROCESS_MODE_DISABLED
	crosshair.visible = false
	hud.visible = false
	viewmodel.set_active(false)
	var marker := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.03
	ball.height = 0.06
	marker.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	marker.material_override = mat
	add_child(marker)
	await _wait(0.3)   # its material gets ready to draw
	for res: int in [0, 5]:
		Settings.resolution = res
		Settings.apply()
		var worst := 0.0
		var root_worst := 0.0   # your own camera, as the hitbox checks use it
		for offset: Vector3 in [Vector3(0.0, 0.0, -3.0), Vector3(1.2, 0.5, -3.0), Vector3(-1.5, -0.6, -4.0), Vector3(0.3, -0.9, -2.0)]:
			marker.global_position = player.eye_position() + offset
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var expected := view_camera.unproject_position(marker.global_position) * Vector2(image.get_size()) / Vector2(game_view.size)
			var sum := Vector2.ZERO
			var count := 0
			for y in range(int(expected.y) - 40, int(expected.y) + 40):
				for x in range(int(expected.x) - 40, int(expected.x) + 40):
					var c := image.get_pixel(clampi(x, 0, image.get_width() - 1), clampi(y, 0, image.get_height() - 1))
					if c.r > 0.8 and c.b > 0.8 and c.g < 0.3:
						sum += Vector2(x + 0.5, y + 0.5)
						count += 1
			var seen := sum / maxi(count, 1)
			worst = maxf(worst, seen.distance_to(expected) if count > 0 else INF)
			var to_view := get_viewport().get_visible_rect().size / Vector2(image.get_size())
			var root_guess: Vector2 = player.camera.unproject_position(marker.global_position) / to_view
			root_worst = maxf(root_worst, seen.distance_to(root_guess) if count > 0 else INF)
		print("[vy] %s: markören syns som mest %.2f px från där vyns kamera räknar, %.2f px från din kamera" % [
			"1280x1024" if res == 5 else "egen upplösning", worst, root_worst])
	marker.queue_free()
	Settings.resolution = 0
	Settings.apply()


## Close-ups of the agents, for checking models, weapons and animations.
func _closeups(dir: String) -> void:
	Settings.viewmodel = false   # the AK in hand would cover the bots
	start_mode("strafe")
	mode.dummy.position = Vector3(0.0, 0.0, -2.6)
	await _snap(dir, "11_closeup_idle")
	# An ADAD reversal at full knife speed, captured frame by frame.
	Settings.strafe_weapon = 0
	start_mode("strafe")
	var dummy: Node3D = mode.dummy
	var vel := 0.0
	var x := -0.8
	var t := 0.0
	var frames := [0.7, 0.82, 0.9, 0.98, 1.06, 1.14, 1.3]
	while not frames.is_empty():
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		vel = move_toward(vel, 250.0 if t < 0.8 else -250.0, 1450.0 * dt)
		x = clampf(x + vel * Defs.UNIT * dt, -1.0, 1.0)
		dummy.position = Vector3(x, 0.0, -3.0)
		dummy.set_motion(vel)
		if t >= frames[0]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join("14_adad_%d.png" % (7 - frames.size())))
			frames.pop_front()
	Settings.track_speed = 3
	start_mode("track")
	mode.dist = 3.2
	await _wait(2.2)
	await _snap(dir, "11_closeup_run_rifle")
	await _wait(0.37)
	await _snap(dir, "11_closeup_run_rifle_b")
	Settings.track_speed = 0
	start_mode("track")
	mode.dist = 3.2
	await _wait(2.4)
	await _snap(dir, "11_closeup_run_knife")
	# Crouching during the countdown, while the bot stands still: the head must drop about 17 units.
	start_mode("track")
	mode.dist = 3.2
	await _wait(0.4)
	var standing: float = mode.dummy.head_centre().y
	mode.sim.set_key(mode.now(), "duck", true)
	await _wait(0.5)
	var crouched: float = mode.dummy.head_centre().y
	print("[crouch] kan croucha: %s, huvudet sjönk %.1f units" % [mode.dummy.can_crouch(), (standing - crouched) / Defs.UNIT])
	await _snap(dir, "11_closeup_crouch")
	await _hitbox_check(dir)
	await _alignment_check()


## How well the hitboxes match what you see: the visible head is lit green, a ray is shot through
## every pixel around it, and the results are counted, for a few poses.
func _hitbox_check(dir: String) -> void:
	for pose: String in ["stå", "spring", "crouch", "crouch-gå"]:
		Settings.strafe_weapon = 0
		start_mode("strafe")
		crosshair.visible = false
		var bot: Node3D = mode.dummy
		bot.position = Vector3(0.0, 0.0, -2.2)
		bot.face(player.eye_position())
		var speed := 250.0 if pose == "spring" else (85.0 if pose == "crouch-gå" else 0.0)
		for i in 40:
			bot.set_motion(speed, 1.0 if pose.begins_with("crouch") else 0.0)
			await get_tree().process_frame
		bot.glow("head")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var camera := get_viewport().get_camera_3d()
		var to_view := get_viewport().get_visible_rect().size / Vector2(image.get_size())
		var centre := camera.unproject_position(bot.head_centre()) / to_view
		var counts := {"head": 0, "body": 0, "": 0}
		var blame := {}
		var outside := 0
		var marked := image.duplicate() as Image
		for y in range(int(centre.y) - 110, int(centre.y) + 110):
			for x in range(int(centre.x) - 110, int(centre.x) + 110):
				var c := image.get_pixel(x, y)
				var point := Vector2(x, y) * to_view
				var origin := camera.project_ray_origin(point)
				var ray := camera.project_ray_normal(point)
				var part: String = bot.hit_test(origin, ray)["part"]
				if c.g > 0.5 and c.g > c.r + 0.2 and c.g > c.b + 0.1:
					counts[part] += 1
					marked.set_pixel(x, y, {"head": Color.GREEN, "body": Color.RED, "": Color.BLUE}[part])
					if part == "body":
						var culprit := _nearest_capsule(bot, origin, ray)
						blame[culprit] = blame.get(culprit, 0) + 1
				elif part == "head":
					outside += 1
					marked.set_pixel(x, y, Color.YELLOW)
		var total := maxi(counts["head"] + counts["body"] + counts[""], 1)
		print("[hitbox] %-9s %-10s synligt huvud %d px: huvud %d %%, kropp %d %%, miss %d %%  ·  huvudträff utanför huvudet: %d px  ·  skymt av %s" % [
			pose, bot.get("_agent").get("name", "enkel"), total, roundi(100.0 * counts["head"] / total),
			roundi(100.0 * counts["body"] / total), roundi(100.0 * counts[""] / total), outside, str(blame)])
		marked.save_png(dir.path_join("20_hitbox_%s.png" % pose))
		if pose == "stå" or pose == "crouch":
			bot.glow("")
			var overlay := _draw_hitboxes(bot)
			await _snap(dir, "21_hitboxes_%s_front" % pose)
			# Side view: the mode turns the bot towards you every frame, so hold it still meanwhile.
			mode.process_mode = Node.PROCESS_MODE_DISABLED
			bot.rotation.y += PI / 2.0
			overlay.free()
			overlay = _draw_hitboxes(bot)
			await _snap(dir, "21_hitboxes_%s_side" % pose)
			overlay.free()
			mode.process_mode = Node.PROCESS_MODE_PAUSABLE
			bot.face(player.eye_position())
		if pose == "stå":
			var skeleton: Skeleton3D = bot.get("_skeleton")
			var heights: Array[String] = []
			for bone_name: String in ["spine_1", "spine_2", "spine_3", "neck_0", "head_0", "clavicle_R", "hand_R", "hand_L"]:
				var p: Vector3 = bot.call("_bone_position", bone_name) if bot.get("_bones").has(bone_name) else \
					skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin
				heights.append("%s y %.2f z %.2f" % [bone_name, p.y, p.z - bot.position.z])
			var agent: Dictionary = bot.get("_agent")
			print("[hitbox] %s  ·  huvudcentrum y %.2f z %.2f, radie %.3f, halv %.3f" % [", ".join(heights),
				bot.head_centre().y, bot.head_centre().z - bot.position.z, agent["head_radius"], agent["head_half"]])
	# A loose head (Gridshot, Flicks, Micro, Target Confirmation): the pixels that change when it's
	# hidden are the head; each one is shot through.
	start_mode("strafe")
	crosshair.visible = false
	mode.dummy.visible = false
	var head := TargetScript.new()
	head.setup_head(0)
	mode.add_child(head)
	head.position = player.eye_position() + Vector3(0.0, 0.0, -1.6)
	await _wait(0.2)
	await RenderingServer.frame_post_draw
	var shown := get_viewport().get_texture().get_image()
	head.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var empty := get_viewport().get_texture().get_image()
	var cam := get_viewport().get_camera_3d()
	var scale_to_view := get_viewport().get_visible_rect().size / Vector2(shown.get_size())
	var middle := cam.unproject_position(head.global_position) / scale_to_view
	var visible_px := 0
	var hits := 0
	var outside_px := 0
	for y in range(int(middle.y) - 140, int(middle.y) + 140):
		for x in range(int(middle.x) - 140, int(middle.x) + 140):
			var a := shown.get_pixel(x, y)
			var b := empty.get_pixel(x, y)
			var point := Vector2(x, y) * scale_to_view
			var hit: bool = head.hit_distance(cam.project_ray_origin(point), cam.project_ray_normal(point)) >= 0.0
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
				visible_px += 1
				hits += int(hit)
			elif hit:
				outside_px += 1
	print("[hitbox] löst huvud: synligt %d px, träff %d %%, miss %d %%  ·  träff utanför huvudet: %d px" % [
		visible_px, roundi(100.0 * hits / maxi(visible_px, 1)), roundi(100.0 * (visible_px - hits) / maxi(visible_px, 1)), outside_px])
	shown.save_png(dir.path_join("22_loose_head.png"))
	head.visible = true
	var capsule: Array = head.get("_head_capsule")
	var ends := [head.global_transform * (capsule[0] as Vector3), head.global_transform * (capsule[1] as Vector3)]
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule[2]
	mesh.height = (ends[0] as Vector3).distance_to(ends[1]) + mesh.radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color(0.2, 1.0, 0.3, 0.4)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = ((ends[0] as Vector3) + (ends[1] as Vector3)) / 2.0
	inst.basis = Basis(Quaternion(Vector3.UP, ((ends[1] as Vector3) - (ends[0] as Vector3)).normalized()))
	mode.add_child(inst)
	await _snap(dir, "22_loose_head_capsule")
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var agent_mesh: Mesh = (head.get_child(0) as MeshInstance3D).mesh
	for s in agent_mesh.get_surface_count():
		for v: Vector3 in agent_mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			lo = lo.min(v)
			hi = hi.max(v)
	print("[hitbox] löst huvud i modellens rum: x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f  ·  kapsel %s - %s r %.3f (relativt mitten)" % [
		lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, str(capsule[0]), str(capsule[1]), capsule[2]])



## The body hitbox a ray hits first, for finding which ones cover the head: a CS2 hitbox as
## "bone/group", or an approximate capsule as "from-to".
func _nearest_capsule(bot: Node3D, origin: Vector3, ray: Vector3) -> String:
	var best := INF
	var culprit := ""
	var skeleton: Skeleton3D = bot.get("_skeleton")
	for h: Dictionary in bot.get("_agent").get("hitboxes", []):
		var ends: Array[Vector3] = bot.call("_hitbox_ends", h)
		var t := Defs.ray_capsule(origin, ray, ends[0], ends[1], h["radius"])
		if t >= 0.0 and t < best:
			best = t
			culprit = "%s/%d" % [skeleton.get_bone_name(h["bone"]), h["group"]]
	if culprit != "":
		return culprit
	for c: Array in DummyScript.BONE_CAPSULES:
		var t := Defs.ray_capsule(origin, ray, bot.call("_bone_position", c[0]), bot.call("_bone_position", c[1]), c[2])
		if t >= 0.0 and t < best:
			best = t
			culprit = "%s-%s" % [c[0], c[1]]
	return culprit


## The bot's CS2 hitboxes as see-through capsules drawn on top: head green, neck yellow, body red.
func _draw_hitboxes(bot: Node3D) -> Node3D:
	var root := Node3D.new()
	mode.add_child(root)
	for h: Dictionary in bot.get("_agent").get("hitboxes", []):
		var ends: Array[Vector3] = bot.call("_hitbox_ends", h)
		var mesh := CapsuleMesh.new()
		mesh.radius = h["radius"]
		mesh.height = ends[0].distance_to(ends[1]) + mesh.radius * 2.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		var group: int = h["group"]
		mat.albedo_color = Color(0.2, 1.0, 0.3, 0.5) if group == 1 else (Color(1.0, 0.9, 0.2, 0.5) if group == 8 else Color(1.0, 0.25, 0.2, 0.28))
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = mat
		inst.position = ends[2]
		if ends[0].distance_to(ends[1]) > 0.001:
			inst.basis = Basis(Quaternion(Vector3.UP, (ends[1] - ends[0]).normalized()))
		root.add_child(inst)
	return root


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Turns the view straight at a point.
func _aim_at(point: Vector3) -> void:
	var d: Vector3 = (point - player.eye_position()).normalized()
	player.yaw = rad_to_deg(atan2(-d.x, -d.z))
	player.pitch = rad_to_deg(asin(d.y))
	player.turn(0.0, 0.0)


func _snap(dir: String, file: String) -> void:
	await _wait(0.25)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(file + ".png"))


## Three and a half weeks of slowly improving runs and playlists, for the statistics screenshots.
func _fake_history() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var now_local := Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system())
	for i in 40:
		var days_ago := 24 - int(i * 24 / 39.0)
		var stamp := Time.get_datetime_string_from_unix_time(now_local - days_ago * 86400 - (40 - i) * 600, true)
		var p := i / 39.0
		Stats.data["grid"].append({"variant": Defs.variant("grid", Settings), "score": roundi(70 + 18 * p + rng.randf_range(-5, 5)), "date": stamp})
		Stats.data["flick"].append({"variant": Defs.variant("flick", Settings), "score": roundi(27 + 9 * p + rng.randf_range(-3, 3)), "date": stamp})
		Stats.data["micro"].append({"variant": Defs.variant("micro", Settings), "score": roundi(48 + 14 * p + rng.randf_range(-4, 4)), "date": stamp})
		Stats.data["confirm"].append({"variant": Defs.variant("confirm", Settings), "score": roundi(30 + 12 * p + rng.randf_range(-4, 4)), "date": stamp})
		Stats.data["strafe"].append({"variant": Defs.variant("strafe", Settings), "score": roundi(1150 + 450 * p + rng.randf_range(-120, 120)), "date": stamp})
		Stats.data["track"].append({"variant": Defs.variant("track", Settings), "score": roundi(2800 + 1500 * p + rng.randf_range(-300, 300)), "date": stamp})
		Stats.data["tconfirm"].append({"variant": Defs.variant("tconfirm", Settings), "score": roundi(18 + 8 * p + rng.randf_range(-3, 3)), "date": stamp})
		Stats.data["punch"].append({"variant": Defs.variant("punch", Settings), "score": roundi(24 + 9 * p + rng.randf_range(-3, 3)), "date": stamp})
		Stats.data["strafeaim"].append({"variant": Defs.variant("strafeaim", Settings), "score": roundi(44 + 14 * p + rng.randf_range(-4, 4)), "date": stamp})
	for days_ago: int in [20, 17, 16, 12, 10, 9, 6, 5, 3, 2, 1]:
		var results := {}
		for id: String in Defs.PLAYLIST:
			var fake := _fake_result(id)
			results[id] = {"scores": [fake["score"], fake["score"], fake["score"]], "variant": fake["variant"], "best": false}
		Stats.data["playlist"].append({"date": Time.get_datetime_string_from_unix_time(now_local - days_ago * 86400, true), "results": results})


func _fake_result(id: String) -> Dictionary:
	match id:
		"grid":
			return {"variant": Defs.variant("grid", Settings), "score": 86, "hits": 86, "misses": 7,
				"accuracy": 0.925, "avg_ms": 690.0}
		"micro":
			return {"variant": Defs.variant("micro", Settings), "score": 58, "hits": 58, "misses": 6,
				"accuracy": 0.906, "avg_ms": 610.0, "directness": 0.81}
		"tconfirm":
			return {"variant": Defs.variant("tconfirm", Settings), "score": 24, "zone": "head", "shots": 31,
				"misses": 5, "body_hits": 2, "accuracy": 0.774, "per_kill_ms": 2500.0}
		"punch":
			return {"variant": Defs.variant("punch", Settings), "score": 31, "deaths": 6, "armor": 0, "zone": "head",
				"shots": 52, "misses": 14, "body_hits": 7, "accuracy": 0.596, "kill_ms": 712.0, "recover_ms": 538.0,
				"hits_taken": 58, "punched_shots": 19, "punched_kills": 4}
		"strafeaim":
			return {"variant": Defs.variant("strafeaim", Settings), "score": 54, "hits": 54, "misses": 11,
				"still_shots": 6, "accuracy": 0.831, "avg_ms": 1090.0, "avg_speed": 0.86}
		"flick":
			return {"variant": Defs.variant("flick", Settings), "score": 34, "targets": 38, "hits": 34,
				"misses": 3, "timeouts": 2, "accuracy": 0.919, "avg_ms": 436.0, "flick_bias": 0.09}
		"confirm":
			return {"variant": Defs.variant("confirm", Settings), "score": 41, "per_target_ms": 1463.0, "attempts": 4}
		"track":
			return {"variant": Defs.variant("track", Settings), "score": 4210, "zone": "head", "head_pct": 0.421,
				"body_pct": 0.874, "react_pct": 0.18, "steady_pct": 0.52, "avg_error_deg": 0.94,
				"best_streak": 1.84, "changes": 41, "bot_speed": 250.0}
	return {"variant": Defs.variant("strafe", Settings), "score": 1640, "shots": 20, "accurate": 17,
		"accuracy": 0.85, "avg_delay_ms": 62.0, "early": 3, "avg_early_ms": 38.0, "moving": 0,
		"avg_stop_ms": 84.0, "counter_rate": 0.9, "overlaps": 2, "headshots": 11}
