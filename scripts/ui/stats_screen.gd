extends Control
## Progress over time: a tab per exercise with a chart of every run, the trend over the last week
## and the latest runs, plus a tab for the playlists with a calendar of the days each was done.

signal back_requested

const UI = preload("res://scripts/ui/ui_kit.gd")
const Defs = preload("res://scripts/defs.gd")
const ProgressChart = preload("res://scripts/ui/progress_chart.gd")
const TABS := [
	["grid", "Gridshot"], ["flick", "Flicks"], ["micro", "Micro Adjustments"], ["track", "Tracking"], ["confirm", "Target Confirmation"],
	["tconfirm", "Tracking Confirmation"], ["punch", "Aim Punch"], ["timing", "Click Timing"], ["strafeaim", "Strafe Aim"],
	["strafe", "Counter-strafe"],
	["playlist", "Pass"],
]
const MONTHS := ["jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
const WEEKDAYS := ["Mån", "Tis", "Ons", "Tor", "Fre", "Lör", "Sön"]
const DAY := 86400

var _tab := "grid"
## The playlist shown on the playlist tab; it starts at the one picked in the menu.
var _pass := ""
var _all_variants := false
var _tab_buttons := {}
var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1680, 0)   # room for all the tabs in one row
	center.add_child(panel)
	var col := UI.vbox(16)
	panel.add_child(col)
	col.add_child(UI.label("STATISTIK", 28, UI.TEXT, true))
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	for tab: Array in TABS:
		var id: String = tab[0]
		var b := UI.button(tab[1], func() -> void: show_tab(id))
		b.add_theme_font_size_override("font_size", 16)
		_tab_buttons[id] = b
		tabs.add_child(b)
	col.add_child(tabs)
	_content = UI.vbox(14)
	col.add_child(_content)
	var buttons := UI.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(UI.button("Tillbaka", func() -> void: back_requested.emit(), true))
	col.add_child(buttons)


func _notification(what: int) -> void:
	# Each time the screen opens, the playlist tab starts at the playlist picked in the menu.
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_pass = ""


func refresh() -> void:
	for id: String in _tab_buttons:
		UI.style_tab(_tab_buttons[id], id == _tab)
	UI.clear(_content)
	if _tab == "playlist":
		_build_playlist()
	else:
		_build_mode(_tab)


func show_tab(id: String) -> void:
	_tab = id
	refresh()


func _build_mode(mode: String) -> void:
	var variant := Defs.variant(mode, Settings)
	# "All settings" mixes variants, but only runs in today's 60-second format compare at all.
	var runs: Array = Stats.history(mode).filter(func(r: Dictionary) -> bool: return str(r.get("variant", "")).contains("60 s")) \
		if _all_variants else Stats.history(mode, variant)

	var head := UI.hbox(16)
	var names := UI.vbox(2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UI.label(_title(mode), 26, UI.ACCENT, true))
	names.add_child(UI.label("Alla inställningar" if _all_variants else variant + "   (ändra i menyn)", 15, UI.DIM))
	head.add_child(names)
	var all := CheckBox.new()
	all.text = "Visa alla inställningar"
	all.button_pressed = _all_variants
	all.focus_mode = Control.FOCUS_NONE
	all.toggled.connect(func(on: bool) -> void:
		_all_variants = on
		refresh())
	head.add_child(all)
	_content.add_child(head)

	var chart := ProgressChart.new()
	chart.mode = mode
	chart.runs = runs
	_content.add_child(chart)

	var today := _today()
	var week: Array[float] = []
	var before: Array[float] = []
	var best := -INF
	for r: Dictionary in runs:
		var score := float(r.get("score", 0))
		best = maxf(best, score)
		var ago := today - _day_number(str(r.get("date", "")))
		if ago >= 0 and ago < 7:
			week.append(score)
		elif ago >= 7 and ago < 14:
			before.append(score)
	var facts := UI.hbox(48)
	facts.add_child(_fact("Personbästa", UI.short_value(mode, best) if not runs.is_empty() else "–", UI.GOOD))
	facts.add_child(_fact("Rundor", str(runs.size()), UI.TEXT))
	var week_avg := _mean(week)
	facts.add_child(_fact("Snitt senaste 7 dagarna", UI.short_value(mode, week_avg) + "  (%d rundor)" % week.size() if not week.is_empty() else "–", UI.TEXT))
	var trend_text := "–"
	var trend_color := UI.DIM
	if not week.is_empty() and not before.is_empty() and _mean(before) > 0.0:
		var pct := (week_avg / _mean(before) - 1.0) * 100.0
		trend_text = "%s%s %%" % ["+" if pct >= 0.0 else "-", UI.dec(absf(pct), 1)]
		trend_color = UI.GOOD if pct > 0.0 else (UI.BAD if pct < 0.0 else UI.DIM)
	facts.add_child(_fact("Mot veckan innan", trend_text, trend_color))
	var latest := "–"
	if not runs.is_empty():
		var last: Dictionary = runs[-1]
		latest = "%s  (%s)" % [UI.short_value(mode, last.get("score", 0)), _short_stamp(str(last.get("date", "")))]
	facts.add_child(_fact("Senaste runda", latest, UI.TEXT))
	_content.add_child(facts)


## One playlist at a time, picked with a tab when you have more than the daily one: its streak,
## a calendar of the days it was done and its latest runs.
func _build_playlist() -> void:
	var ids := Settings.playlist_ids()
	if not ids.has(_pass):
		_pass = Settings.selected_playlist()
	if ids.size() > 1:
		var picker := HFlowContainer.new()
		picker.add_theme_constant_override("h_separation", 8)
		picker.add_theme_constant_override("v_separation", 8)
		for id: String in ids:
			var b := UI.button(Settings.playlist_name(id), func() -> void:
				_pass = id
				refresh.call_deferred())
			b.add_theme_font_size_override("font_size", 15)
			UI.style_tab(b, id == _pass)
			picker.add_child(b)
		_content.add_child(picker)
	var title := Settings.playlist_name(_pass)
	var entries := Stats.playlist_history(_pass)
	var streak := Stats.playlist_streak(_pass)
	var head := UI.vbox(2)
	head.add_child(UI.label(title, 26, UI.ACCENT, true))
	head.add_child(UI.label("%d %s i rad  ·  %d pass totalt" % [streak, "dag" if streak == 1 else "dagar", entries.size()], 16, UI.TEXT, true))
	_content.add_child(head)

	var row := UI.hbox(40)
	row.add_child(_calendar(entries))
	var recent := UI.vbox(10)
	recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent.add_child(UI.label("Senaste passen (bästa runda per övning)", 14, UI.DIM, true))
	var latest := entries.slice(-8)
	latest.reverse()
	if latest.is_empty():
		recent.add_child(UI.label("Inga pass än. Starta %s från menyn." % title, 15, UI.DIM))
	else:
		recent.add_child(_playlist_table(latest))
	row.add_child(recent)
	_content.add_child(row)


## One row per playlist with the best round of each exercise in it; "–" where it was skipped or
## didn't exist yet. Exercises none of these runs had get no column.
func _playlist_table(entries: Array) -> Control:
	var modes := TABS.filter(func(tab: Array) -> bool:
		return tab[0] != "playlist" and entries.any(func(entry: Dictionary) -> bool:
			return (entry.get("results", {}) as Dictionary).has(tab[0])))
	var table := GridContainer.new()
	table.columns = modes.size() + 1
	table.add_theme_constant_override("h_separation", 14)
	table.add_theme_constant_override("v_separation", 8)
	table.add_child(Control.new())
	for tab: Array in modes:
		var header := UI.label(tab[1], 13, UI.DIM, true)
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.custom_minimum_size = Vector2(92, 0)
		header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		table.add_child(header)
	for entry: Dictionary in entries:
		var date := UI.label(_short_stamp(str(entry.get("date", ""))), 15, UI.DIM)
		date.custom_minimum_size = Vector2(100, 0)
		table.add_child(date)
		var results: Dictionary = entry.get("results", {})
		for tab: Array in modes:
			var r: Variant = results.get(tab[0])
			var scores: Array = r.get("scores", []) if r is Dictionary else []
			table.add_child(UI.label(UI.short_value(tab[0], scores.max()) if not scores.is_empty() else "–", 15, UI.TEXT))
	return table


## The last four weeks, Monday first, with the days you finished a playlist filled in.
func _calendar(entries: Array) -> Control:
	var done := {}
	for entry: Dictionary in entries:
		done[_day_number(str(entry.get("date", "")))] = true
	var today := _today()
	var weekday: int = Time.get_datetime_dict_from_system()["weekday"]   # 0 = Sunday
	var first := today - (weekday + 6) % 7 - 21
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for weekday_name: String in WEEKDAYS:
		var l := UI.label(weekday_name, 13, UI.DIM, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(l)
	for i in 28:
		var day := first + i
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(48, 38)
		var bg := Color(1, 1, 1, 0.05)
		var fg := UI.DIM
		if day > today:
			bg = Color(0, 0, 0, 0)
		elif done.has(day):
			bg = UI.ACCENT
			fg = Color(0.09, 0.07, 0.03)
		cell.add_theme_stylebox_override("panel", UI.box(bg, 6, UI.TEXT if day == today else UI.NONE, 4))
		var number := UI.label(Time.get_date_string_from_unix_time(day * DAY).substr(8, 2).lstrip("0"), 14, fg, done.has(day))
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(number)
		grid.add_child(cell)
	return grid


func _fact(title: String, value: String, color: Color) -> Control:
	var v := UI.vbox(2)
	v.add_child(UI.label(title, 13, UI.DIM, true))
	v.add_child(UI.label(value, 22, color, true))
	return v


func _title(mode: String) -> String:
	for tab: Array in TABS:
		if tab[0] == mode:
			return tab[1]
	return mode


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()


## Days since 1970 for a local "YYYY-MM-DD..." stamp (local time read as UTC, like _today()).
static func _day_number(stamp: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(stamp.substr(0, 10)) / DAY)


static func _today() -> int:
	return int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system()) / DAY)


## "2026-10-06 18:42:10" → "6 okt 18:42"
static func _short_stamp(stamp: String) -> String:
	if stamp.length() < 16:
		return stamp
	var month := stamp.substr(5, 2).to_int()
	return "%d %s %s" % [stamp.substr(8, 2).to_int(), MONTHS[clampi(month - 1, 0, 11)], stamp.substr(11, 5)]
