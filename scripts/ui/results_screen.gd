extends Control
## Summary shown when a run ends. In the daily playlist it also offers the next exercise.

signal again_requested
signal next_requested
signal menu_requested

const UI = preload("res://scripts/ui/ui_kit.gd")

var _title: Label
var _headline: Label
var _unit: Label
var _badge: Label
var _rows: GridContainer
var _note: Label
var _menu_button: Button
var _again_primary: Button
var _again_plain: Button
var _next_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop(0.72))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	var col := UI.vbox(10)
	panel.add_child(col)

	_title = UI.label("", 15, UI.ACCENT, true)
	col.add_child(_title)
	var head := UI.hbox(12)
	_headline = UI.label("", 64, UI.TEXT, true)
	_unit = UI.label("", 20, UI.DIM)
	_unit.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_headline)
	head.add_child(_unit)
	col.add_child(head)
	_badge = UI.label("", 16, UI.GOOD, true)
	col.add_child(_badge)
	col.add_child(UI.separator())

	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 24)
	_rows.add_theme_constant_override("v_separation", 8)
	col.add_child(_rows)
	_note = UI.label("", 15, UI.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(530, 0)
	col.add_child(_note)

	var buttons := UI.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_menu_button = UI.button("Meny  (Esc)", func() -> void: menu_requested.emit())
	_again_plain = UI.button("Kör igen  (R)", func() -> void: again_requested.emit())
	_again_primary = UI.button("Kör igen  (R)", func() -> void: again_requested.emit(), true)
	_next_button = UI.button("", func() -> void: next_requested.emit(), true)
	for b: Button in [_menu_button, _again_plain, _again_primary, _next_button]:
		buttons.add_child(b)
	col.add_child(buttons)


## `next_label` set means we're in the daily playlist: the main button goes on to the next exercise.
func show_result(title: String, variant: String, summary: Dictionary, badge: String, badge_color: Color, next_label: String = "") -> void:
	var in_playlist := next_label != ""
	_menu_button.text = "Avsluta passet  (Esc)" if in_playlist else "Meny  (Esc)"
	_again_plain.visible = in_playlist
	_again_primary.visible = not in_playlist
	_next_button.visible = in_playlist
	_next_button.text = next_label
	_title.text = ("%s  ·  %s" % [title, variant]).to_upper()
	_headline.text = summary["headline"]
	_unit.text = summary["unit"]
	_badge.text = badge
	_badge.add_theme_color_override("font_color", badge_color)
	_badge.visible = badge != ""
	UI.clear(_rows)
	for row: Array in summary["rows"]:
		var name_label := UI.label(row[0], 17, UI.DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(name_label)
		var value_label := UI.label(row[1], 17, UI.TEXT, true)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rows.add_child(value_label)
	_note.text = summary["note"]
	_note.visible = summary["note"] != ""
