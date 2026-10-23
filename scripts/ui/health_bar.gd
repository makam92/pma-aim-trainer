extends Control
## Your health in an Aim Punch duel, like CS2's: a bar and a number that turn orange and then red
## as it runs out.

const UI = preload("res://scripts/ui/ui_kit.gd")

var hp := 100


func _init() -> void:
	custom_minimum_size = Vector2(420, 40)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_hp(value: int) -> void:
	hp = clampi(value, 0, 100)
	queue_redraw()


func _draw() -> void:
	draw_style_box(UI.box(Color(0.04, 0.045, 0.06, 0.86), 8), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var color := UI.GOOD if hp > 50 else (UI.ACCENT if hp > 25 else UI.BAD)
	draw_string(font, Vector2(16.0, 26.0), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.DIM)
	var bar := Rect2(56.0, 12.0, size.x - 130.0, 16.0)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp / 100.0, bar.size.y)), color)
	draw_string(font, Vector2(bar.end.x + 14.0, 27.0), str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
