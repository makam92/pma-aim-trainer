extends Control
## Your own daily playlist: how many rounds of each exercise (none skips it) and in which order.
## Every change is saved straight away; the exercises use the settings on their menu cards.

signal back_requested

const UI = preload("res://scripts/ui/ui_kit.gd")
const Defs = preload("res://scripts/defs.gd")
const UP_ICON := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><path d="M4 11.5L9 6.5l5 5" fill="none" stroke="#ebedf2" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
const DOWN_ICON := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><path d="M4 6.5l5 5 5-5" fill="none" stroke="#ebedf2" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'

## Mode id → title; set before the screen enters the tree.
var titles := {}

var _list: VBoxContainer
var _rows := {}              # mode id → the row's controls
var _total: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 0)
	center.add_child(panel)
	var col := UI.vbox(14)
	panel.add_child(col)
	col.add_child(UI.label("DAGENS PASS", 28, UI.TEXT, true))
	var intro := UI.label("Välj hur många rundor du vill köra av varje övning och i vilken ordning. Övningar utan rundor hoppas över. Inställningarna tas från korten i menyn.", 15, UI.DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(952, 0)
	col.add_child(intro)
	_list = UI.vbox(8)
	col.add_child(_list)
	var up := UI.svg_icon(UP_ICON)
	var down := UI.svg_icon(DOWN_ICON)
	for id: String in Defs.PLAYLIST:
		_rows[id] = _make_row(id, up, down)
		_list.add_child(_rows[id]["row"])
	col.add_child(UI.separator())
	var footer := UI.hbox(12)
	_total = UI.label("", 18, UI.TEXT, true)
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_total)
	footer.add_child(UI.button("Återställ", func() -> void: Settings.update("playlist", [])))
	footer.add_child(UI.button("Klar  (Esc)", func() -> void: back_requested.emit(), true))
	col.add_child(footer)
	Settings.changed.connect(refresh)


func refresh() -> void:
	var entries := Settings.playlist_entries()
	var place := 0
	var rounds := 0
	for i in entries.size():
		var id: String = entries[i][0]
		var reps: int = entries[i][1]
		var row: Dictionary = _rows[id]
		_list.move_child(row["row"], i)
		if reps > 0:
			place += 1
			rounds += reps
		row["number"].text = str(place) if reps > 0 else "–"
		row["number"].add_theme_color_override("font_color", UI.ACCENT if reps > 0 else UI.DIM)
		row["name"].add_theme_color_override("font_color", UI.TEXT if reps > 0 else UI.DIM)
		row["variant"].text = Defs.variant(id, Settings)
		row["count"].text = UI.rounds_text(reps) if reps > 0 else "Hoppas över"
		row["count"].add_theme_color_override("font_color", UI.TEXT if reps > 0 else UI.DIM)
		row["minus"].disabled = reps == 0
		row["plus"].disabled = reps >= Defs.PLAYLIST_MAX_REPS
		row["up"].disabled = i == 0
		row["down"].disabled = i == entries.size() - 1
	_total.text = "%s  ·  %s" % [UI.rounds_text(rounds), UI.playlist_time(rounds)] if rounds > 0 \
		else "Inga rundor valda"


func _make_row(id: String, up_icon: Texture2D, down_icon: Texture2D) -> Dictionary:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UI.box(UI.FIELD, 10, UI.LINE, 16, 8))
	var h := UI.hbox(12)
	row.add_child(h)
	var number := UI.label("", 20, UI.ACCENT, true)
	number.custom_minimum_size = Vector2(28, 0)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(number)
	var names := UI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := UI.label(titles.get(id, id), 19, UI.TEXT, true)
	names.add_child(name_label)
	var variant := UI.label("", 13, UI.DIM)
	names.add_child(variant)
	h.add_child(names)
	var up := _small_button("", up_icon, func() -> void: _move(id, -1))
	var down := _small_button("", down_icon, func() -> void: _move(id, 1))
	h.add_child(up)
	h.add_child(down)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	h.add_child(gap)
	var minus := _small_button("-", null, func() -> void: _change(id, -1))
	h.add_child(minus)
	var count := UI.label("", 17, UI.TEXT, true)
	count.custom_minimum_size = Vector2(118, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(count)
	var plus := _small_button("+", null, func() -> void: _change(id, 1))
	h.add_child(plus)
	return {"row": row, "number": number, "name": name_label, "variant": variant, "count": count,
		"minus": minus, "plus": plus, "up": up, "down": down}


## A square button that looks like the others but with less padding.
func _small_button(text: String, icon: Texture2D, on_press: Callable) -> Button:
	var b := UI.button(text, on_press)
	b.icon = icon
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(44, 42)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state: String in UI.BUTTON_STATES:
		b.add_theme_stylebox_override(state, UI.button_box(state, 8.0, 6.0))
	return b


func _change(id: String, delta: int) -> void:
	var entries := Settings.playlist_entries()
	for entry: Array in entries:
		if entry[0] == id:
			entry[1] = clampi(entry[1] + delta, 0, Defs.PLAYLIST_MAX_REPS)
	Settings.update("playlist", entries)


## Swaps the exercise with its neighbour above (-1) or below (+1).
func _move(id: String, step: int) -> void:
	var entries := Settings.playlist_entries()
	var i := entries.find_custom(func(entry: Array) -> bool: return entry[0] == id)
	var j := i + step
	if i < 0 or j < 0 or j >= entries.size():
		return
	var moved: Array = entries[i]
	entries[i] = entries[j]
	entries[j] = moved
	Settings.update("playlist", entries)
