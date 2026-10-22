extends Control
## In-game overlay: mode title, progress, live stats, feedback text and mode widgets.

const UI = preload("res://scripts/ui/ui_kit.gd")

var _title: Label
var _info: Label
var _stats: Label
var _bar: ColorRect
var _flash: Label
var _message: Label
var _note: Label
var _tint: ColorRect
var _widgets: VBoxContainer
var _flash_tween: Tween
var _tint_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tint = ColorRect.new()
	_tint.color = Color(UI.BAD, 0.0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_tint, Vector4(0, 0, 1, 1), Vector4.ZERO)
	add_child(_tint)

	var top := UI.hbox(0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(top, Vector4(0, 0, 1, 0), Vector4(32, 18, -32, 58))
	add_child(top)
	_title = UI.label("", 18, UI.ACCENT, true)
	_info = UI.label("", 24, UI.TEXT, true)
	_stats = UI.label("", 18, UI.TEXT)
	for l: Label in [_title, _info, _stats]:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(l)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(1, 1, 1, 0.08)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(bar_bg, Vector4(0, 0, 1, 0), Vector4(32, 64, -32, 67))
	add_child(bar_bg)
	_bar = ColorRect.new()
	_bar.color = UI.ACCENT
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_bar, Vector4(0, 0, 0, 1), Vector4.ZERO)
	bar_bg.add_child(_bar)

	_note = UI.label("", 14, UI.DIM, true)
	UI.place(_note, Vector4(0, 0, 0.5, 0), Vector4(32, 72, 0, 96))
	add_child(_note)

	_message = UI.label("", 22, UI.TEXT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(_message, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-600, -150, 600, -110))
	add_child(_message)

	_flash = UI.label("", 30, UI.TEXT, true)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.place(_flash, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-400, 46, 400, 92))
	add_child(_flash)

	# Outlines keep the text readable against both the light and the dark room.
	for l: Label in [_title, _info, _stats, _message, _flash, _note]:
		l.add_theme_constant_override("outline_size", 7)
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))

	_widgets = UI.vbox(10)
	_widgets.alignment = BoxContainer.ALIGNMENT_END
	_widgets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_widgets, Vector4(0.5, 1, 0.5, 1), Vector4(-440, -330, 440, -28))
	add_child(_widgets)


func reset() -> void:
	set_texts("", "", "")
	set_progress(0.0)
	message("")
	set_note("")
	_flash.text = ""
	UI.clear(_widgets)


## A small line under the title, like the daily playlist's progress.
func set_note(text: String) -> void:
	_note.text = text


func set_texts(title: String, info: String, stats: String) -> void:
	_title.text = title
	_info.text = info
	_stats.text = stats


func set_progress(fraction: float) -> void:
	_bar.anchor_right = clampf(fraction, 0.0, 1.0)


func add_widget(widget: Control) -> void:
	_widgets.add_child(widget)


## Short feedback under the crosshair that fades out.
func flash(text: String, color: Color = UI.TEXT) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash.modulate.a = 1.0
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.45)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.35)


## A message above the crosshair that stays until replaced.
func message(text: String, color: Color = UI.TEXT) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)


## Briefly tints the whole screen.
func tint(color: Color) -> void:
	_tint.color = Color(color, 0.22)
	if _tint_tween:
		_tint_tween.kill()
	_tint_tween = create_tween()
	_tint_tween.tween_property(_tint, "color:a", 0.0, 0.5)
