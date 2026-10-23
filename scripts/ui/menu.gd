extends Control
## Main menu: the daily playlist and one card per training mode, plus settings, stats and quit.

signal start_requested(mode_id: String)
signal playlist_requested
signal playlist_edit_requested
signal settings_requested
signal stats_requested
signal quit_requested

const UI = preload("res://scripts/ui/ui_kit.gd")
const Defs = preload("res://scripts/defs.gd")

const COLUMNS := 5
const CARD_WIDTH := 344.0
const CARD_PADDING := 20.0
## In the order of the standard playlist.
const CARDS := [
	{
		"id": "grid",
		"title": "Gridshot",
		"text": "Tre huvuden åt gången i ett rutnät. Varje träff tar fram ett nytt, och klockan startar på första träffen.",
	},
	{
		"id": "flick",
		"title": "Flicks",
		"text": "Håll siktet i ringen, flicka till huvudet som dyker upp och skjut. Visar om du flickar för långt eller för kort.",
	},
	{
		"id": "micro",
		"title": "Micro Adjustments",
		"text": "Ett huvud dyker upp en bit från siktet, var du än siktar. Korrigera det sista och skjut. Visar hur rakt du justerar.",
	},
	{
		"id": "track",
		"title": "Tracking",
		"text": "En gubbe strafear med exakt CS2-rörelse: acceleration, inbromsning, ADAD och maxfart. Håll siktet på honom.",
	},
	{
		"id": "confirm",
		"title": "Target Confirmation",
		"text": "Skjut huvuden nära och långt bort, ett i taget. En enda miss och du börjar om från noll.",
	},
	{
		"id": "tconfirm",
		"title": "Tracking Confirmation",
		"text": "Döda strafeande CS2-gubbar en i taget med riktig CS2-rörelse. En kill tar fram nästa, missar sänker träffsäkerheten.",
	},
	{
		"id": "punch",
		"title": "Aim Punch",
		"text": "Fienden skjuter först och varje träff rycker siktet som i CS2. Hitta tillbaka till huvudet och döda honom innan han dödar dig.",
	},
	{
		"id": "strafeaim",
		"title": "Strafe Aim",
		"text": "Strafea med A/D och träffa målen medan du rör dig. Skott när du står still eller vänder räknas inte.",
	},
	{
		"id": "strafe",
		"title": "Counter-strafe",
		"text": "Strafea med A/D, kontra och skjut. Du ser direkt om skottet var träffsäkert och hur många ms fel du låg.",
	},
]

var _pb_labels := {}
var _sens_label: Label
var _playlist_status: Label
var _playlist_text: Label
var _playlist_total: Label
var _playlist_start: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop(0.7))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.vbox(22)
	center.add_child(col)

	var head := UI.vbox(2)
	var title := UI.label("PMA AIM TRAINER", 56, UI.TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var sub := UI.label("Nio övningar på 60 sekunder med CS2:s sens, FOV, rörelse och modeller", 18, UI.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	col.add_child(head)

	var cards := GridContainer.new()
	cards.columns = COLUMNS
	cards.add_theme_constant_override("h_separation", 16)
	cards.add_theme_constant_override("v_separation", 16)
	cards.add_child(_playlist_card())
	for card: Dictionary in CARDS:
		cards.add_child(_card(card))
	col.add_child(cards)

	var footer := UI.hbox(12)
	_sens_label = UI.label("", 16, UI.DIM)
	_sens_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_sens_label)
	footer.add_child(UI.button("Inställningar", func() -> void: settings_requested.emit()))
	footer.add_child(UI.button("Statistik", func() -> void: stats_requested.emit()))
	footer.add_child(UI.button("Avsluta", func() -> void: quit_requested.emit()))
	col.add_child(footer)

	Settings.changed.connect(refresh)
	refresh()


func refresh() -> void:
	_sens_label.text = "Sens %s  ·  %d DPI  ·  eDPI %s  ·  %s cm/360" % [
		str(snappedf(Settings.sensitivity, 0.001)).replace(".", ","), Settings.dpi,
		UI.num(Settings.edpi()), UI.dec(Settings.cm_per_360(), 1)]
	for id: String in _pb_labels:
		var best: Variant = Stats.best(id, Defs.variant(id, Settings))
		_pb_labels[id].text = "Personbästa: " + (UI.main_value(id, best) if best != null else "–")
	var parts: Array[String] = []
	var rounds := 0
	for entry: Array in Settings.playlist_entries():
		if entry[1] > 0:
			parts.append("%s ×%d" % [_title(entry[0]), entry[1]])
			rounds += entry[1]
	_playlist_text.text = " · ".join(parts) if rounds > 0 else "Inga övningar valda. Välj rundor under Ändra."
	_playlist_total.text = "%s  ·  %s" % [UI.rounds_text(rounds), UI.playlist_time(rounds)] if rounds > 0 else ""
	_playlist_start.disabled = rounds == 0
	var streak := Stats.playlist_streak()
	var streak_text := "%d %s i rad" % [streak, "dag" if streak == 1 else "dagar"] if streak > 0 else "Ingen svit än"
	if Stats.played_playlist_today():
		_playlist_status.text = "Klart idag  ·  " + streak_text
		_playlist_status.add_theme_color_override("font_color", UI.GOOD)
	else:
		_playlist_status.text = "Inte kört idag  ·  " + streak_text
		_playlist_status.add_theme_color_override("font_color", UI.DIM)


## The daily playlist as the first card: what's in it, how long it takes and the streak.
func _playlist_card() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.09, 0.06, 0.96), 14, Color(UI.ACCENT, 0.45), CARD_PADDING, 18))
	var v := UI.vbox(10)
	panel.add_child(v)
	v.add_child(UI.label("Dagens pass", 24, UI.ACCENT, true))
	_playlist_status = UI.label("", 16, UI.DIM, true)
	v.add_child(_playlist_status)
	_playlist_text = UI.label("", 15, UI.DIM)
	_playlist_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_playlist_text.custom_minimum_size = Vector2(CARD_WIDTH - CARD_PADDING * 2.0, 0)
	v.add_child(_playlist_text)
	_playlist_total = UI.label("", 15, UI.TEXT, true)
	v.add_child(_playlist_total)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var bottom := UI.hbox(10)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(UI.button("Ändra", func() -> void: playlist_edit_requested.emit()))
	_playlist_start = UI.button("Starta passet", func() -> void: playlist_requested.emit(), true)
	bottom.add_child(_playlist_start)
	v.add_child(bottom)
	return panel


func _card(card: Dictionary) -> Control:
	var id: String = card["id"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 14, UI.LINE, CARD_PADDING, 18))
	var v := UI.vbox(10)
	panel.add_child(v)
	v.add_child(UI.label(card["title"], 24, UI.ACCENT, true))
	var text := UI.label(card["text"], 15, UI.DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(CARD_WIDTH - CARD_PADDING * 2.0, 0)
	v.add_child(text)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	for option: Array in _options_for(id):
		var l := UI.label(option[0], 14, UI.DIM)
		l.custom_minimum_size = Vector2(78, 0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(l)
		var key: String = option[2]
		var choice := UI.options(option[1], Settings.get(key), func(i: int) -> void: Settings.update(key, i))
		choice.add_theme_font_size_override("font_size", 15)
		for state: String in UI.BUTTON_STATES:
			choice.add_theme_stylebox_override(state, UI.button_box(state, 12.0, 7.0))
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(choice)
	v.add_child(grid)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var bottom := UI.hbox(12)
	var pb := UI.label("", 15, UI.TEXT)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pb_labels[id] = pb
	bottom.add_child(pb)
	bottom.add_child(UI.button("Starta", func() -> void: start_requested.emit(id), true))
	v.add_child(bottom)
	return panel


static func _title(id: String) -> String:
	for card: Dictionary in CARDS:
		if card["id"] == id:
			return card["title"]
	return id


func _options_for(id: String) -> Array:
	var ranges := Defs.TARGET_RANGES.map(func(r: Dictionary) -> String: return "%s %d–%d u" % [r["name"], r["near"], r["far"]])
	var speeds := Defs.TRACK_SPEEDS.map(func(s: Dictionary) -> String: return "%s %d u/s" % [s["name"], s["speed"]])
	var zones := Defs.TRACK_ZONES.map(func(z: Dictionary) -> String: return z["name"])
	match id:
		"grid":
			return [
				["Måltyp", Defs.TARGET_TYPES, "grid_target"],
				["Avstånd", ranges, "grid_range"],
			]
		"flick":
			return [
				["Måltyp", Defs.TARGET_TYPES, "flick_target"],
				["Avstånd", ranges, "flick_range"],
			]
		"micro":
			return [
				["Måltyp", Defs.TARGET_TYPES, "micro_target"],
				["Avstånd", ranges, "micro_range"],
				["Från siktet", Defs.MICRO_OFFSETS.map(func(o: Dictionary) -> String: return "%s %s" % [o["name"], Defs.micro_offset_text(o)]), "micro_offset"],
			]
		"track":
			return [
				["Fart", speeds, "track_speed"],
				["Avstånd", Defs.TRACK_DISTS.map(func(d: float) -> String: return "%d u (%d m)" % [d, roundi(d * Defs.UNIT)]), "track_dist"],
				["Sikta på", zones, "track_zone"],
			]
		"confirm":
			var limits := Defs.CONFIRM_LIMITS.map(func(l: float) -> String: return "Av" if l <= 0.0 else str(l).replace(".", ",") + " s")
			return [
				["Måltyp", Defs.TARGET_TYPES, "confirm_target"],
				["Avstånd", ranges, "confirm_range"],
				["Tid per mål", limits, "confirm_limit"],
			]
		"tconfirm":
			return [
				["Fart", speeds, "tconf_speed"],
				["Avstånd", ranges, "tconf_range"],
				["Sikta på", zones, "tconf_zone"],
			]
		"punch":
			return [
				["Skydd", Defs.ARMOR, "punch_armor"],
				["Avstånd", ranges, "punch_range"],
				["Sikta på", zones, "punch_zone"],
			]
		"strafeaim":
			return [
				["Måltyp", Defs.TARGET_TYPES, "saim_target"],
				["Avstånd", ranges, "saim_range"],
				["Din fart", speeds, "saim_speed"],
			]
		"strafe":
			return [
				["Vapen", Defs.WEAPONS.map(func(w: Dictionary) -> String: return w["name"]), "strafe_weapon"],
			]
	return []
