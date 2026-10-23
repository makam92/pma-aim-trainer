extends Node
## Player settings, saved to user://settings.cfg.

signal changed

const Defs = preload("res://scripts/defs.gd")
const PATH := "user://settings.cfg"
const CROSSHAIR_COLORS := [
	{"name": "Grön", "color": Color(0.25, 1.0, 0.4)},
	{"name": "Cyan", "color": Color(0.25, 0.95, 1.0)},
	{"name": "Gul", "color": Color(1.0, 0.92, 0.25)},
	{"name": "Magenta", "color": Color(1.0, 0.35, 0.95)},
	{"name": "Röd", "color": Color(1.0, 0.3, 0.3)},
	{"name": "Vit", "color": Color(1.0, 1.0, 1.0)},
]
const FPS_CAPS := [144, 240, 360, 500, 1000, 0]
## Render resolutions; (0, 0) means the screen's own. With the others the game is rendered at that
## size and scaled up to fill the screen, stretched or with black bars, like running CS2 at that
## resolution (main.gd renders it; menus, HUD and crosshair stay at the screen's own resolution).
const RESOLUTIONS := [
	Vector2i(0, 0), Vector2i(1920, 1080), Vector2i(1680, 1050), Vector2i(1600, 900), Vector2i(1440, 1080),
	Vector2i(1280, 1024), Vector2i(1280, 960), Vector2i(1024, 768), Vector2i(800, 600),
]
## The UI is laid out for this size and scaled to the window.
const UI_BASE := Vector2(1920.0, 1080.0)
const SAVED := [
	"sensitivity", "dpi",
	"crosshair_color", "crosshair_length", "crosshair_gap", "crosshair_thickness",
	"crosshair_outline", "crosshair_dot",
	"volume", "fullscreen", "vsync", "fps_cap", "room_theme", "use_cs2_models", "resolution", "stretched",
	"bot_crouch", "viewmodel", "ak_sound", "viewmodel_fov", "impacts", "ak_recoil",
	"grid_target", "grid_range",
	"flick_target", "flick_range",
	"micro_target", "micro_range", "micro_offset",
	"confirm_target", "confirm_range", "confirm_limit",
	"strafe_weapon",
	"track_speed", "track_dist", "track_zone",
	"tconf_speed", "tconf_range", "tconf_zone",
	"punch_armor", "punch_range", "punch_zone",
	"saim_target", "saim_range", "saim_speed",
	"playlist",
]

var sensitivity := 1.0
var dpi := 800
var crosshair_color := 0
var crosshair_length := 5
var crosshair_gap := 3
var crosshair_thickness := 2
var crosshair_outline := true
var crosshair_dot := false
var volume := 0.6
var fullscreen := true
var vsync := false
var fps_cap := 3
var room_theme := 0
var use_cs2_models := true
var resolution := 0
var stretched := true
## Whether the bots in Tracking and Tracking Confirmation crouch now and then.
var bot_crouch := true
## The AK in your hands like CS2's viewmodel (then shots also follow its fire rate), CS2's own AK
## sound for shots, and CS2's viewmodel_fov (54-68).
var viewmodel := true
var ak_sound := true
var viewmodel_fov := 60
## Bullet holes, dust and tracers where shots land, and the AK's own recoil, spray and inaccuracy
## from CS2 (off: every shot goes exactly where you aim).
var impacts := true
var ak_recoil := false

# Mode options, as indices into the lists in defs.gd.
var grid_target := 0
var grid_range := 1
var flick_target := 0
var flick_range := 0
var micro_target := 0
var micro_range := 2
var micro_offset := 1
var confirm_target := 0
var confirm_range := 0
var confirm_limit := 0
var strafe_weapon := 0
var track_speed := 0
var track_dist := 1
var track_zone := 0
var tconf_speed := 0
var tconf_range := 1
var tconf_zone := 0
var punch_armor := 0
var punch_range := 0
var punch_zone := 0
var saim_target := 0
var saim_range := 1
var saim_speed := 3
## Your own daily playlist as [mode id, rounds] pairs in play order; empty means the standard one.
var playlist: Array = []

## The screenshot tour (--tour=DIR) and the self-test (--selftest) never write settings.
var dev_mode := false

var _applied_vsync := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tour") or arg == "--selftest":
			dev_mode = true
	if not dev_mode:
		_load()
	apply()


func update(key: String, value: Variant) -> void:
	set(key, value)
	save()
	apply()


func save() -> void:
	if dev_mode:
		return
	var cfg := ConfigFile.new()
	for key: String in SAVED:
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var want_full := fullscreen and not dev_mode
		var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED
		var current := DisplayServer.window_get_mode()
		var is_full := current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_FULLSCREEN
		if want_full != is_full:
			DisplayServer.window_set_mode(mode)
			if not want_full:
				_center_window()
		if int(vsync) != _applied_vsync:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
			_applied_vsync = int(vsync)
	Engine.max_fps = FPS_CAPS[fps_cap]
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	_apply_resolution()
	changed.emit()


## The window itself always draws at the screen's own resolution, so text and the crosshair stay
## sharp; only the game view is rendered at render_size().
func _apply_resolution() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(UI_BASE)


## The size the game is rendered at, or (0, 0) for the screen's own resolution.
func render_size() -> Vector2i:
	return RESOLUTIONS[clampi(resolution, 0, RESOLUTIONS.size() - 1)]


## How much the game view is scaled up in a window of this size (pixels), horizontally and
## vertically: 1 at the screen's own resolution, the same both ways with black bars.
func view_stretch(window: Vector2) -> Vector2:
	var res := Vector2(render_size())
	if res == Vector2.ZERO or window.x <= 0.0 or window.y <= 0.0:
		return Vector2.ONE
	var s := window / res
	return s if stretched else Vector2.ONE * minf(s.x, s.y)


## The daily playlist with every mode exactly once, in play order: [[mode id, rounds], ...].
## Modes missing from your own list (new ones, say) come last with 0 rounds.
func playlist_entries() -> Array:
	var entries: Array = []
	var seen := {}
	for entry: Variant in playlist:
		if entry is Array and entry.size() == 2 and Defs.PLAYLIST.has(entry[0]) and not seen.has(entry[0]):
			entries.append([str(entry[0]), clampi(int(entry[1]), 0, Defs.PLAYLIST_MAX_REPS)])
			seen[entry[0]] = true
	for id: String in Defs.PLAYLIST:
		if not seen.has(id):
			entries.append([id, Defs.PLAYLIST_REPS if playlist.is_empty() else 0])
	return entries


func crosshair_rgb() -> Color:
	return CROSSHAIR_COLORS[crosshair_color]["color"]


func edpi() -> float:
	return sensitivity * dpi


func cm_per_360() -> float:
	return 360.0 / (sensitivity * 0.022 * dpi) * 2.54


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var size := Vector2i(mini(1600, screen_size.x - 80), mini(900, screen_size.y - 120))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + (screen_size - size) / 2)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in SAVED:
		set(key, cfg.get_value("settings", key, get(key)))
