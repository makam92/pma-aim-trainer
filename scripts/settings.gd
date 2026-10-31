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
	"bot_crouch", "viewmodel", "ak_sound", "viewmodel_fov", "impacts", "ak_recoil", "countdown", "hit_times",
	"grid_target", "grid_range",
	"flick_target", "flick_range",
	"micro_target", "micro_range", "micro_offset",
	"confirm_target", "confirm_range", "confirm_limit",
	"strafe_weapon",
	"track_speed", "track_dist", "track_zone",
	"tconf_speed", "tconf_range", "tconf_zone", "tconf_lives",
	"punch_armor", "punch_range", "punch_zone",
	"timing_speed", "timing_dist", "timing_door", "timing_move",
	"saim_target", "saim_range", "saim_speed",
	"playlist", "playlists", "playlist_selected",
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
## A 3-2-1 countdown before every run, and the time shown under the crosshair after a hit.
var countdown := true
var hit_times := true

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
var tconf_lives := 0
var punch_armor := 0
var punch_range := 0
var punch_zone := 0
var timing_speed := 0
var timing_dist := 1
var timing_door := 1
var timing_move := 0
var saim_target := 0
var saim_range := 1
var saim_speed := 3
## Your own daily playlist as [mode id, rounds] pairs in play order; empty means the standard one.
var playlist: Array = []
## Your own playlists besides the daily one (a short warmup, say), oldest first:
## {"id", "name", "entries"} with entries like `playlist`.
var playlists: Array = []
## The playlist picked in the menu: Defs.DAILY_PLAYLIST or the id of one of your own.
var playlist_selected := Defs.DAILY_PLAYLIST

## The screenshot tour (--tour=DIR) and the self-test (--selftest) never write settings.
var dev_mode := false

var _applied_vsync := -1


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tour") or arg == "--selftest":
			dev_mode = true
	if not dev_mode:
		_load()
	else:
		AudioServer.set_bus_mute(0, true)   # tests and the screenshot tour run silently,
		countdown = false                   # and start right away unless a check turns it on
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


## A playlist with every mode exactly once, in play order: [[mode id, rounds], ...]. Modes missing
## from its list (new ones, say) come last with 0 rounds; an empty daily list is the standard one.
func playlist_entries(id: String = Defs.DAILY_PLAYLIST) -> Array:
	var daily := id == Defs.DAILY_PLAYLIST
	var source: Variant = playlist if daily else _own_playlist(id).get("entries", [])
	if not source is Array:
		source = []
	var entries: Array = []
	var seen := {}
	for entry: Variant in source:
		if entry is Array and entry.size() == 2 and Defs.PLAYLIST.has(entry[0]) and not seen.has(entry[0]):
			entries.append([str(entry[0]), clampi(int(entry[1]), 0, Defs.PLAYLIST_MAX_REPS)])
			seen[entry[0]] = true
	for mode: String in Defs.PLAYLIST:
		if not seen.has(mode):
			entries.append([mode, Defs.PLAYLIST_REPS if daily and source.is_empty() else 0])
	return entries


## Saves a playlist's rounds and order, given like playlist_entries() returns them.
func set_playlist_entries(id: String, entries: Array) -> void:
	if id == Defs.DAILY_PLAYLIST:
		update("playlist", entries)
		return
	var own := playlists.duplicate(true)
	for p: Variant in own:
		if p is Dictionary and p.get("id") == id:
			p["entries"] = entries
	update("playlists", own)


## The daily playlist's id first, then your own in the order you made them.
func playlist_ids() -> Array[String]:
	var ids: Array[String] = [Defs.DAILY_PLAYLIST]
	for p: Variant in playlists:
		if p is Dictionary and p.has("id"):
			ids.append(str(p["id"]))
	return ids


func playlist_name(id: String) -> String:
	if id == Defs.DAILY_PLAYLIST:
		return "Dagens pass"
	var title := str(_own_playlist(id).get("name", "")).strip_edges()
	return title if title != "" else "Eget pass"


## The playlist picked in the menu, or the daily one when that one is gone.
func selected_playlist() -> String:
	return playlist_selected if playlist_ids().has(playlist_selected) else Defs.DAILY_PLAYLIST


## Makes a new playlist of your own, with no rounds yet, and picks it. Returns its id, or "" when
## there's no room for another.
func add_playlist() -> String:
	if playlists.size() >= Defs.MAX_OWN_PLAYLISTS:
		return ""
	# Ids are never reused, so a new playlist never takes over a removed one's history.
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	while playlist_ids().has("own%d" % stamp):
		stamp += 1
	var id := "own%d" % stamp
	var names := playlist_ids().map(func(other: String) -> String: return playlist_name(other))
	var title := "Eget pass"
	var n := 1
	while names.has(title):
		n += 1
		title = "Eget pass %d" % n
	var own := playlists.duplicate(true)
	own.append({"id": id, "name": title, "entries": []})
	playlists = own
	update("playlist_selected", id)
	return id


## Stores the name as typed; playlist_name() trims it and stands in for an empty one.
func rename_playlist(id: String, title: String) -> void:
	var own := playlists.duplicate(true)
	for p: Variant in own:
		if p is Dictionary and p.get("id") == id:
			p["name"] = title.left(Defs.PLAYLIST_NAME_MAX)
	update("playlists", own)


## Removes one of your own playlists; its finished runs stay in the statistics.
func remove_playlist(id: String) -> void:
	playlists = playlists.filter(func(p: Variant) -> bool: return not (p is Dictionary and p.get("id") == id))
	update("playlist_selected", selected_playlist())


func _own_playlist(id: String) -> Dictionary:
	for p: Variant in playlists:
		if p is Dictionary and p.get("id") == id:
			return p
	return {}


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
