extends Control
## Editing a playlist: how many rounds of each exercise (none skips it) and in which order, and the
## name of one of your own. Every change is saved straight away; the exercises use the settings on
## their menu cards.

signal back_requested

const UI = preload("res://scripts/ui/ui_kit.gd")
const Defs = preload("res://scripts/defs.gd")
const UP_ICON := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><path d="M4 11.5L9 6.5l5 5" fill="none" stroke="#ebedf2" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
const DOWN_ICON := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><path d="M4 6.5l5 5 5-5" fill="none" stroke="#ebedf2" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
const INTRO := "%s hur många rundor du vill köra av varje övning och i vilken ordning. Övningar utan rundor hoppas över. Inställningarna tas från korten i menyn."

## Mode id → title; set before the screen enters the tree.
var titles := {}

var _id := Defs.DAILY_PLAYLIST
var _heading: Label
var _name: LineEdit
var _intro: Label
var _list: VBoxContainer
var _rows := {}              # mode id → the row's controls
var _total: Label
var _reset: Button
var _remove: Button
var _confirm_remove := false


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
	_heading = UI.label("DAGENS PASS", 28, UI.TEXT, true)
	col.add_child(_heading)
	_name = LineEdit.new()
	_name.max_length = Defs.PLAYLIST_NAME_MAX
	_name.placeholder_text = "Namn på passet"
	_name.add_theme_font_size_override("font_size", 24)
	_name.add_theme_font_override("font", UI.bold())
	_name.custom_minimum_size = Vector2(460, 0)
	_name.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name.text_changed.connect(func(text: String) -> void:
		_confirm_remove = false
		Settings.rename_playlist(_id, text))
	_name.text_submitted.connect(func(_text: String) -> void: _name.release_focus())
	col.add_child(_name)
	_intro = UI.label("", 15, UI.DIM)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size = Vector2(952, 0)
	col.add_child(_intro)
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
	_reset = UI.button("Återställ", func() -> void: Settings.update("playlist", []))
	footer.add_child(_reset)
	_remove = UI.button("Ta bort passet", _on_remove)
	footer.add_child(_remove)
	footer.add_child(UI.button("Klar  (Esc)", func() -> void: back_requested.emit(), true))
	col.add_child(footer)
	Settings.changed.connect(refresh)


## Which playlist to edit. A new one has its name selected, ready to type over.
func edit(id: String, is_new: bool = false) -> void:
	_id = id
	_confirm_remove = false
	_name.text = Settings.playlist_name(id) if id != Defs.DAILY_PLAYLIST else ""
	if is_new:
		_name.grab_focus.call_deferred()
		_name.select_all.call_deferred()


func refresh() -> void:
	# The daily playlist has a fixed name and can be reset to the standard one; your own can be
	# renamed and removed.
	var own := _id != Defs.DAILY_PLAYLIST
	_heading.visible = not own
	_name.visible = own
	_intro.text = INTRO % ("Ge passet ett namn och välj" if own else "Välj")
	_reset.visible = not own
	_remove.visible = own
	_remove.text = "Ta bort? Klicka igen" if _confirm_remove else "Ta bort passet"
	for item: String in ["font_color", "font_hover_color"]:
		if _confirm_remove:
			_remove.add_theme_color_override(item, UI.BAD)
		else:
			_remove.remove_theme_color_override(item)
	var entries := Settings.playlist_entries(_id)
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
	_confirm_remove = false
	var entries := Settings.playlist_entries(_id)
	for entry: Array in entries:
		if entry[0] == id:
			entry[1] = clampi(entry[1] + delta, 0, Defs.PLAYLIST_MAX_REPS)
	Settings.set_playlist_entries(_id, entries)


## Swaps the exercise with its neighbour above (-1) or below (+1).
func _move(id: String, step: int) -> void:
	_confirm_remove = false
	var entries := Settings.playlist_entries(_id)
	var i := entries.find_custom(func(entry: Array) -> bool: return entry[0] == id)
	var j := i + step
	if i < 0 or j < 0 or j >= entries.size():
		return
	var moved: Array = entries[i]
	entries[i] = entries[j]
	entries[j] = moved
	Settings.set_playlist_entries(_id, entries)


## Two clicks: the first asks, the second removes the playlist and goes back to the menu. Its
## finished runs stay in the statistics.
func _on_remove() -> void:
	if not _confirm_remove:
		_confirm_remove = true
		refresh()
		return
	var gone := _id
	_id = Defs.DAILY_PLAYLIST
	_confirm_remove = false
	Settings.remove_playlist(gone)
	back_requested.emit()
