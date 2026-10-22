extends Control
## Pause overlay. Game time stands still while it's open. In the daily playlist a sheet along the
## right edge shows the whole playlist, and any round in it can be jumped to.

signal resume_requested
signal restart_requested
signal settings_requested
signal skip_requested
signal menu_requested
signal jump_requested(step: int)

const UI = preload("res://scripts/ui/ui_kit.gd")
const SHEET_WIDTH := 500.0

var _skip_button: Button
var _menu_button: Button
var _sheet: PanelContainer
var _sheet_progress: Label
var _sheet_rows: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop(0.6))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)
	var col := UI.vbox(12)
	panel.add_child(col)
	col.add_child(UI.label("PAUS", 30, UI.TEXT, true))
	col.add_child(UI.label("Tiden står still tills du fortsätter.", 15, UI.DIM))
	col.add_child(UI.separator())
	_skip_button = UI.button("Hoppa över övningen", func() -> void: skip_requested.emit())
	_menu_button = UI.button("Till menyn", func() -> void: menu_requested.emit())
	for b: Button in [
		UI.button("Fortsätt  (Esc)", func() -> void: resume_requested.emit(), true),
		UI.button("Starta om  (R)", func() -> void: restart_requested.emit()),
		UI.button("Inställningar", func() -> void: settings_requested.emit()),
		_skip_button,
		_menu_button,
	]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(b)
	_build_sheet()
	set_playlist(false)


## In the daily playlist an exercise can be skipped, and leaving ends the whole playlist.
func set_playlist(active: bool) -> void:
	_skip_button.visible = active
	_menu_button.text = "Avsluta passet" if active else "Till menyn"
	_sheet.visible = active


## Fills the sheet: each exercise in the playlist with a button per round, showing the result of
## rounds already played (`runs`: step → {"score", ...}) and marking the current one.
func show_playlist(steps: Array, current: int, runs: Dictionary, titles: Dictionary) -> void:
	_sheet_progress.text = "Runda %d av %d" % [current + 1, steps.size()]
	UI.clear(_sheet_rows)
	var chips: HBoxContainer = null
	var round_no := 0
	for step in steps.size():
		var id: String = steps[step]
		if step == 0 or steps[step - 1] != id:
			var block := UI.vbox(6)
			var here: bool = steps[current] == id
			block.add_child(UI.label(titles.get(id, id), 17, UI.ACCENT if here else UI.TEXT, true))
			chips = UI.hbox(8)
			block.add_child(chips)
			_sheet_rows.add_child(block)
			round_no = 0
		round_no += 1
		chips.add_child(_round_button(step, round_no, step == current, runs.get(step), id))


func _round_button(step: int, round_no: int, is_current: bool, run: Variant, mode: String) -> Button:
	var done := run is Dictionary and not is_current
	var text := UI.short_value(mode, run["score"]) if done else str(round_no)
	var b := UI.button(text, func() -> void: jump_requested.emit(step), is_current)
	b.custom_minimum_size = Vector2(72, 40)
	b.add_theme_font_size_override("font_size", 15)
	for state: String in UI.BUTTON_STATES:
		if is_current:
			b.add_theme_stylebox_override(state, UI.box(UI.ACCENT if state != "pressed" else UI.ACCENT.darkened(0.15), 8, UI.NONE, 8.0, 6.0))
		else:
			b.add_theme_stylebox_override(state, UI.button_box(state, 8.0, 6.0))
	if done:
		b.add_theme_color_override("font_color", UI.GOOD)
	return b


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.066, 0.085, 0.97), 0, UI.LINE, 28.0, 32.0))
	UI.place(_sheet, Vector4(1.0, 0.0, 1.0, 1.0), Vector4(-SHEET_WIDTH, 0.0, 0.0, 0.0))
	add_child(_sheet)
	var col := UI.vbox(10)
	_sheet.add_child(col)
	col.add_child(UI.label("DAGENS PASS", 22, UI.ACCENT, true))
	_sheet_progress = UI.label("", 16, UI.TEXT, true)
	col.add_child(_sheet_progress)
	var help := UI.label("Klicka på en runda för att hoppa dit, framåt eller bakåt. Gröna rundor är klara; kör du om en ersätts resultatet.", 14, UI.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(SHEET_WIDTH - 56.0, 0)
	col.add_child(help)
	col.add_child(UI.separator())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_sheet_rows = UI.vbox(16)
	_sheet_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sheet_rows)
