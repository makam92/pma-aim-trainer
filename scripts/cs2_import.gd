extends Node
## Reads what the game uses out of your own CS2 install into its data folder (%APPDATA%\CS2AimTrainer),
## for personal use only: the player models with CS2's hitboxes, the weapons, the AK in first person
## and its firing sounds. Nothing from CS2 is part of the game itself. It uses Source 2 Viewer's
## command line tool (open source, MIT), which comes with the installed game; running from the
## project it's taken from %LOCALAPPDATA%\Programs\Source2Viewer.
##   In the game: Settings → CS2-filer → Importera från CS2. Without a window:
##   godot --headless --path . -- --import-cs2

signal progress(step: int, steps: int, text: String)
signal finished(ok: bool, message: String)

const AGENTS := ["ctm_sas/ctm_sas", "tm_phoenix/tm_phoenix"]
const WEAPONS := [
	"ak47/weapon_rif_ak47",
	"m4a1_silencer/weapon_rif_m4a1_silencer",
	"knife/knife_default_ct/weapon_knife_default_ct",
	"knife/knife_default_t/weapon_knife_default_t",
]
## Standing still, running and walking sideways, and the same crouched, with a knife and a rifle.
const WORLD_CLIPS := ["idle", "run_e", "run_w", "walk_e", "walk_w", "idle_crouch", "crouch_e", "crouch_w"]
const VIEWMODEL_CLIPS := ["draw_ak", "idle_ak", "shoot1_ak"]
## Models only come with their skeleton when animations are asked for, even if none match.
const SKELETON_ONLY := "animation/anims/viewmodel/rifle/rifle_ak/idle_ak"
## CS2 ships textures up to 4096 px. Seen from 10-40 m away 1024 px is plenty and loads much faster;
## the first-person arms are close and keep a bit more.
const TEXTURE_MAX := {"models": 1024, "viewmodel": 2048}
const DEV_CLI := "Programs/Source2Viewer/Source2Viewer-CLI.exe"

var running := false

var _thread: Thread
var _cli := ""
var _vpk := ""
var _gameinfo := ""
var _data := ""


## Where Source 2 Viewer's command line tool is: next to the installed game, or where the project
## expects it. Empty if neither has it.
static func find_cli() -> String:
	var candidates := [
		OS.get_executable_path().get_base_dir().path_join("Source2Viewer/Source2Viewer-CLI.exe"),
		OS.get_environment("LOCALAPPDATA").path_join(DEV_CLI),
	]
	for path: String in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


## The csgo folder of CS2 in any Steam library, or "".
static func find_cs2() -> String:
	var output := []
	OS.execute("reg", ["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"], output)
	var steam := ""
	for line: String in "\n".join(output).split("\n"):
		if line.contains("SteamPath") and line.contains("REG_SZ"):
			steam = line.get_slice("REG_SZ", 1).strip_edges()
	if steam == "":
		steam = "C:/Program Files (x86)/Steam"
	var libraries: Array[String] = [steam]
	var vdf := FileAccess.get_file_as_string(steam.path_join("steamapps/libraryfolders.vdf"))
	var regex := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
	for found in regex.search_all(vdf):
		libraries.append(found.get_string(1).replace("\\\\", "/"))
	for library in libraries:
		var csgo := library.path_join("steamapps/common/Counter-Strike Global Offensive/game/csgo")
		if FileAccess.file_exists(csgo.path_join("pak01_dir.vpk")):
			return csgo
	return ""


## Starts importing in the background; `progress` and `finished` tell how it goes.
func start() -> void:
	if running:
		return
	_cli = find_cli()
	var csgo := find_cs2()
	if _cli == "":
		finished.emit(false, "Hittar inte Source 2 Viewer, som behövs för att läsa CS2:s filer.")
		return
	if csgo == "":
		finished.emit(false, "Hittar inte CS2 i Steam.")
		return
	_vpk = csgo.path_join("pak01_dir.vpk")
	_gameinfo = csgo.path_join("gameinfo.gi")
	_data = ProjectSettings.globalize_path("user://")
	running = true
	_thread = Thread.new()
	_thread.start(_run)


func _run() -> void:
	var steps: Array = []
	var world_clips: Array[String] = []
	for held: Array in [["knife", "_default_knife", "knife"], ["rifle", "_default_rifle", "rifle"]]:
		for clip: String in WORLD_CLIPS:
			world_clips.append("animation/anims/world/%s/%s/%s_%s" % [held[0], held[1], clip, held[2]])
	for agent: String in AGENTS:
		steps.append(["Spelarmodell " + agent.get_file(), "agents/models/%s.vmdl_c" % agent, "models", ",".join(world_clips)])
		steps.append(["Hitboxar " + agent.get_file(), "agents/models/%s.vmdl_c" % agent, "hitboxes", ""])
	for weapon: String in WEAPONS:
		steps.append(["Vapen " + weapon.get_file(), "weapons/models/%s.vmdl_c" % weapon, "models", SKELETON_ONLY])
	steps.append(["Armar i första person", "weapons/models/shared/arms/weapon_arms.vmdl_c", "viewmodel", SKELETON_ONLY])
	for clip: String in VIEWMODEL_CLIPS:
		steps.append(["AK-klipp " + clip, "animation/anims/viewmodel/rifle/rifle_ak/%s.vnmclip_c" % clip, "viewmodel", ""])
	for n in range(1, 5):
		steps.append(["AK-ljud %d" % n, "sounds/weapons/ak47/ak47_0%d.vsnd_c" % n, "sounds", ""])
	var failed: Array[String] = []
	for i in steps.size():
		var step: Array = steps[i]
		_report.call_deferred(i, steps.size() + 1, step[0])
		if not _export(step[1], step[2], step[3]):
			failed.append(step[0])
	_report.call_deferred(steps.size(), steps.size() + 1, "Krymper texturer")
	for folder: String in TEXTURE_MAX:
		_shrink_textures(_data.path_join(folder), TEXTURE_MAX[folder])
	var message := "Klart: spelarmodeller, hitboxar, vapen, AK:n i första person och AK-ljud är inlästa från din CS2-installation." \
		if failed.is_empty() else "Klart, men det här gick inte att läsa: %s." % ", ".join(failed)
	_done.call_deferred(failed.is_empty(), message)


## One file out of CS2: a model or clip as glTF (with its skeleton when `animations` is given), a
## sound as it is, or a model's hitboxes written next to its glTF.
func _export(path: String, kind: String, animations: String) -> bool:
	var args := PackedStringArray(["-i", _win(_vpk), "--game", _win(_gameinfo), "-f", path])
	if kind == "hitboxes":
		args.append("-a")
		var dump := _run_cli(args)
		var hitboxes := _parse_hitboxes(dump[1])
		if hitboxes.is_empty():
			return false
		var target := _data.path_join("models").path_join(path.trim_suffix(".vmdl_c") + ".hitboxes.json")
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		file.store_string(JSON.stringify(hitboxes, "\t"))
		return true
	var folder := _data.path_join(kind)
	DirAccess.make_dir_recursive_absolute(folder)
	args.append_array(["-o", _win(folder), "-d"])
	if kind != "sounds":
		args.append_array(["--gltf_export_format", "glb", "--gltf_export_materials", "--gltf_textures_adapt"])
	if animations != "":
		args.append_array(["--gltf_export_animations", "--gltf_animation_list", animations])
	# It reports harmless warnings on stderr; a file written is what counts.
	return (_run_cli(args)[1] as String).contains("Dump written")


## Runs the command line tool from the data folder, so anything it writes beside itself (like a log
## of files it couldn't read) lands there. Returns [exit code, output].
func _run_cli(args: PackedStringArray) -> Array:
	var line := _quote(_win(_cli))
	for arg in args:
		line += " " + _quote(arg)
	var batch := _data.path_join("import_step.cmd")
	var file := FileAccess.open(batch, FileAccess.WRITE)
	file.store_string("@echo off\r\nchcp 65001 >nul\r\ncd /d %s\r\n%s\r\n" % [_quote(_win(_data)), line])
	file.close()
	var output := []
	var code := OS.execute("cmd.exe", ["/c", _win(batch)], output, true)
	DirAccess.remove_absolute(batch)
	return [code, "\n".join(output)]


static func _quote(text: String) -> String:
	return "\"%s\"" % text


## A file path with Windows' backslashes. Paths inside CS2's archive keep their forward slashes.
static func _win(path: String) -> String:
	return path.replace("/", "\\")


## CS2's "cstrike" hitbox set from a model dump: [{"bone", "min", "max" (capsule ends in the bone's
## space, units), "radius", "group"}].
static func _parse_hitboxes(dump: String) -> Array:
	var hitboxes: Array = []
	var in_set := false
	var current := {}
	for raw: String in dump.split("\n"):
		var line := raw.strip_edges()
		if line == "m_name = \"cstrike\"":
			in_set = true
		elif not in_set:
			continue
		elif line.begins_with("m_sBoneName = "):
			current["bone"] = line.get_slice("\"", 1)
		elif line.begins_with("m_vMinBounds = "):
			current["min"] = _numbers(line)
		elif line.begins_with("m_vMaxBounds = "):
			current["max"] = _numbers(line)
		elif line.begins_with("m_flShapeRadius = "):
			current["radius"] = line.get_slice("=", 1).strip_edges().to_float()
		elif line.begins_with("m_nGroupId = "):
			current["group"] = line.get_slice("=", 1).strip_edges().to_int()
		elif line.begins_with("m_nHitBoxIndex = "):
			hitboxes.append(current)
			current = {}
		elif line == "]" and not hitboxes.is_empty():
			break
	return hitboxes


static func _numbers(line: String) -> Array:
	var inside := line.get_slice("[", 1).get_slice("]", 0)
	return Array(inside.split(",")).map(func(n: String) -> float: return n.strip_edges().to_float())


static func _shrink_textures(folder: String, max_size: int) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".png"):
			continue
		var path := folder.path_join(file)
		var image := Image.load_from_file(path)
		if image == null or (image.get_width() <= max_size and image.get_height() <= max_size):
			continue
		var scale := float(max_size) / maxi(image.get_width(), image.get_height())
		image.resize(roundi(image.get_width() * scale), roundi(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
		image.save_png(path)
	for sub in dir.get_directories():
		_shrink_textures(folder.path_join(sub), max_size)


func _report(step: int, steps: int, text: String) -> void:
	progress.emit(step, steps, text)


func _done(ok: bool, message: String) -> void:
	_thread.wait_to_finish()
	running = false
	Agents.reload()
	Sfx.load_ak_sound()
	finished.emit(ok, message)
