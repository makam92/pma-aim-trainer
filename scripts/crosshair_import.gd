extends RefCounted
## Your crosshair from CS2, in the format CS2 has used since its September 2026 update: read from your
## own CS2 config, or from a share code like CSvbPubOq37zTGqtsPTP5QTrp5CB4xFXiKRLfzJsm49ZRe. Both return
## {"crosshair": {...}} with the values Settings.set_crosshair() takes, or {"error": text}. The code
## layout follows akiver/csgo-sharecode (MIT):
## https://github.com/akiver/csgo-sharecode/blob/main/doc/code_layout.md

const CS2Import = preload("res://scripts/cs2_import.gd")
## The characters a code is written in, a big number in base 57 (no I, g, l, 0 or 1).
const DICTIONARY := "ABCDEFGHJKLMNOPQRSTUVWXYZabcdefhijkmnopqrstuvwxyz23456789"
const CODE_BYTES := 32
const CONFIG := "730/local/cfg/cs2_user_convars_0_slot0.vcfg"
## CS2's cl_crosshairstyle values. The trainer draws Dot Only, and every other style as the static cross.
const STYLES := ["Dynamic Cross", "Dynamic Circle", "Dynamic Cross (Legacy)", "Static Circle", "Static Cross",
	"Static Cross (Shot Feedback)", "Dot Only", "Dynamic Quad", "Static Square", "Static Quad"]
const DOT_ONLY := 6
const BAD_CODE := "Koden stämmer inte. Kopiera den igen från CS2."


## The crosshair in the CS2 config of whichever Steam account played CS2 last.
static func from_cs2() -> Dictionary:
	var userdata := CS2Import.find_steam().path_join("userdata")
	var dir := DirAccess.open(userdata)
	if dir == null:
		return {"error": "Hittar inte Steam."}
	var newest := ""
	var newest_time := 0
	for account in dir.get_directories():
		var path := userdata.path_join(account).path_join(CONFIG)
		if FileAccess.file_exists(path) and FileAccess.get_modified_time(path) > newest_time:
			newest = path
			newest_time = FileAccess.get_modified_time(path)
	if newest == "":
		return {"error": "Hittar ingen CS2-config. Starta CS2 en gång så sparar det dina inställningar."}
	return parse_config(FileAccess.get_file_as_string(newest))


## The crosshair ConVars of a CS2 config file; ones it leaves out have CS2's defaults.
static func parse_config(text: String) -> Dictionary:
	var values := {}
	var regex := RegEx.create_from_string("\"(cl_crosshair\\w*)\"\\s+\"([^\"]*)\"")
	for found in regex.search_all(text):
		values[found.get_string(1)] = found.get_string(2)
	if not values.has("cl_crosshair_length"):
		return {"error": "CS2-configen har det gamla crosshair-formatet från före september 2026. Starta CS2 så sparas det nya, eller klistra in din crosshair-kod."}
	return {"crosshair": {
		"length": _number(values, "cl_crosshair_length", 8),
		"gap": _number(values, "cl_crosshair_gap", 4),
		"thickness": _number(values, "cl_crosshair_thickness", 2),
		"screen_height": _number(values, "cl_crosshair_screen_height", 1080),
		"style": _number(values, "cl_crosshairstyle", 7),
		"dot": _number(values, "cl_crosshairdot", 0) != 0,
		"t": _number(values, "cl_crosshair_t", 0) != 0,
		"rgba": Color8(_number(values, "cl_crosshaircolor_r", 0), _number(values, "cl_crosshaircolor_g", 255),
			_number(values, "cl_crosshaircolor_b", 0), _number(values, "cl_crosshaircolor_a", 255)),
		"outline_mode": _number(values, "cl_crosshair_drawoutline", 1),
		"outline_rgba": Color8(_number(values, "cl_crosshairoutline_r", 0), _number(values, "cl_crosshairoutline_g", 0),
			_number(values, "cl_crosshairoutline_b", 0), _number(values, "cl_crosshairoutline_a", 255)),
	}}


## A share code from CS2 ("CS" and 44 characters). CS2 clamps what a code holds to the ConVars'
## ranges when it imports one, and so does this.
static func from_code(code: String) -> Dictionary:
	code = code.strip_edges()
	if code.begins_with("CSGO"):
		return {"error": "Det är en gammal kod (CSGO-…). CS2 bytte till nya koder i september 2026: kopiera koden igen från CS2."}
	if not code.begins_with("CS") or code.length() != 2 + 44:
		return {"error": "Det där ser inte ut som en crosshair-kod. Den börjar med CS och har 44 tecken till."}
	# The number is written least significant character first.
	var bytes := PackedByteArray()
	bytes.resize(CODE_BYTES)
	for i in range(code.length() - 1, 1, -1):
		var carry := DICTIONARY.find(code[i])
		if carry < 0:
			return {"error": BAD_CODE}
		for b in range(CODE_BYTES - 1, -1, -1):
			var value := bytes[b] * DICTIONARY.length() + carry
			bytes[b] = value & 0xFF
			carry = value >> 8
		if carry != 0:
			return {"error": BAD_CODE}
	var sum := 0
	for b in range(1, CODE_BYTES):
		sum += bytes[b]
	var height := bytes[2] | (bytes[3] << 8)
	if bytes[0] != sum % 256 or bytes[1] != 1 or height == 0:
		return {"error": BAD_CODE}
	var gap := bytes[14] | (bytes[15] << 8)
	if gap >= 0x8000:
		gap -= 0x10000
	return {"crosshair": {
		"length": bytes[16],
		"gap": clampi(gap, -3840, 3840),
		"thickness": mini(bytes[13] & 0x3F, 32),
		"screen_height": maxi(height, 240),
		"style": mini(bytes[4] & 0x1F, STYLES.size() - 1),
		"dot": (bytes[4] & 0x40) != 0,
		"t": (bytes[4] & 0x80) != 0,
		"rgba": Color8(bytes[5], bytes[6], bytes[7], bytes[8]),
		"outline_mode": mini(bytes[13] >> 6, 2),
		"outline_rgba": Color8(bytes[9], bytes[10], bytes[11], bytes[12]),
	}}


## A short line on what was read, for the settings screen.
static func describe(c: Dictionary) -> String:
	var text := "längd %d, mellanrum %d, tjocklek %d vid %d px skärmhöjd" % [c["length"], c["gap"], c["thickness"], c["screen_height"]]
	var style: int = c["style"]
	if style != 4 and style != DOT_ONLY:
		text += ". CS2-stilen %s ritas som Static Cross här" % STYLES[style]
	return text


## ConVar values come as "2", "1.000000", "true" or "false".
static func _number(values: Dictionary, key: String, default: int) -> int:
	var text: String = values.get(key, str(default))
	if text == "true":
		return 1
	if text == "false":
		return 0
	return roundi(text.to_float())
