extends Control
## Live speed bar. In counter-strafe it marks the accuracy threshold; for a tracking bot it just
## shows how fast the bot is moving.

const UI = preload("res://scripts/ui/ui_kit.gd")

var sim: RefCounted
var speed := 0.0
var title := "Fart"
var neutral := false


func _init() -> void:
	custom_minimum_size = Vector2(880, 40)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_style_box(UI.box(Color(0.04, 0.045, 0.06, 0.86), 8), Rect2(Vector2.ZERO, size))
	if sim == null:
		return
	var font := get_theme_default_font()
	var max_speed: float = sim.max_speed
	var thr: float = sim.threshold()
	var bar := Rect2(130.0, 12.0, size.x - (330.0 if neutral else 260.0), 16.0)
	draw_string(font, Vector2(16.0, 26.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UI.DIM)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var color := UI.ACCENT if neutral else (UI.GOOD if speed <= thr else UI.BAD)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(speed / max_speed, 0.0, 1.0), bar.size.y)), color)
	if not neutral:
		var tx := bar.position.x + bar.size.x * thr / max_speed
		draw_line(Vector2(tx, bar.position.y - 4.0), Vector2(tx, bar.end.y + 4.0), Color.WHITE, 2.0)
	var text := "%d u/s" % roundi(speed)
	if neutral:
		text += "  (max %d)" % roundi(max_speed)
	draw_string(font, Vector2(bar.end.x + 14.0, 26.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
