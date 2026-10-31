extends Node
## Finished runs per mode, saved to user://stats.json.

const Defs = preload("res://scripts/defs.gd")
const PATH := "user://stats.json"
const MAX_PER_MODE := 500
## The headline number of each mode and whether higher is better.
const RANKING := {
	"grid": {"key": "score", "higher": true},
	"flick": {"key": "score", "higher": true},
	"micro": {"key": "score", "higher": true},
	"confirm": {"key": "score", "higher": true},
	"strafe": {"key": "score", "higher": true},
	"track": {"key": "score", "higher": true},
	"tconfirm": {"key": "score", "higher": true},
	"punch": {"key": "score", "higher": true},
	"timing": {"key": "score", "higher": true},
	"strafeaim": {"key": "score", "higher": true},
}

## Runs per mode, plus "playlist": finished playlists as {"date", "id", "name",
## "results": {mode: {"scores", "variant", "best"} or null when skipped}}; modes that weren't in
## that playlist are left out. Those from before there were several playlists have no id: they're
## the daily one.
var data := {"grid": [], "flick": [], "micro": [], "confirm": [], "strafe": [], "track": [], "tconfirm": [], "punch": [], "timing": [],
	"strafeaim": [], "playlist": []}
## Off during the screenshot tour so fake results never reach disk.
var persist := true


func _ready() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		for mode: String in data:
			if parsed.get(mode) is Array:
				data[mode] = parsed[mode]


## Stores a finished run. Returns true when it beats the previous best for the same variant.
func add(mode: String, result: Dictionary) -> bool:
	var previous: Variant = best(mode, result.get("variant", ""))
	result["date"] = Time.get_datetime_string_from_system(false, true)
	var list: Array = data[mode]
	list.append(result)
	if list.size() > MAX_PER_MODE:
		list.pop_front()
	_save()
	return previous == null or is_better(mode, result, previous)


func is_better(mode: String, a: Dictionary, b: Dictionary) -> bool:
	var rank: Dictionary = RANKING[mode]
	var av: float = a.get(rank["key"], 0.0)
	var bv: float = b.get(rank["key"], 0.0)
	return av > bv if rank["higher"] else av < bv


## The best run for a variant, or null if there is none.
func best(mode: String, variant: String) -> Variant:
	var top: Variant = null
	for r: Dictionary in history(mode, variant):
		if top == null or is_better(mode, r, top):
			top = r
	return top


## Runs oldest first, optionally only those with the given variant.
func history(mode: String, variant: String = "") -> Array:
	if variant == "":
		return data[mode]
	return data[mode].filter(func(r: Dictionary) -> bool: return r.get("variant", "") == variant)


func add_playlist(id: String, title: String, results: Dictionary) -> void:
	data["playlist"].append({"date": Time.get_datetime_string_from_system(false, true), "id": id, "name": title,
		"results": results})
	_save()


## One playlist's finished runs, oldest first.
func playlist_history(id: String) -> Array:
	return data["playlist"].filter(func(entry: Dictionary) -> bool:
		return str(entry.get("id", Defs.DAILY_PLAYLIST)) == id)


## The playlist's most recent finished run, or null.
func last_playlist(id: String) -> Variant:
	var list := playlist_history(id)
	return list[-1] if not list.is_empty() else null


func played_playlist_today(id: String) -> bool:
	return _playlist_days(id).has(_local_day(0))


## Days in a row the playlist was finished, counting back from today, or from yesterday when
## today's isn't done yet (so the streak doesn't look broken in the morning).
func playlist_streak(id: String) -> int:
	var days := _playlist_days(id)
	var back := 0 if days.has(_local_day(0)) else 1
	var streak := 0
	while days.has(_local_day(back + streak)):
		streak += 1
	return streak


func _playlist_days(id: String) -> Dictionary:
	var days := {}
	for entry: Dictionary in playlist_history(id):
		days[str(entry.get("date", "")).substr(0, 10)] = true
	return days


## Local date ("2026-10-22") `days_ago` days back. The local clock is read as if it were UTC, so
## the day arithmetic needs no time zone handling.
func _local_day(days_ago: int) -> String:
	var now_local := Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false))
	return Time.get_date_string_from_unix_time(now_local - days_ago * 86400)


func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
