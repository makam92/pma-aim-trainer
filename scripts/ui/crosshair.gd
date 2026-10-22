extends Control
## CS-style crosshair drawn in whole physical pixels so it stays sharp at any window size.
## With `preview` set, it draws centred in its own rect on a dark background instead.

const UI = preload("res://scripts/ui/ui_kit.gd")

var preview := false


func _ready() -> void:
	if not preview:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Settings.changed.connect(queue_redraw)
	resized.connect(queue_redraw)


func _draw() -> void:
	# Canvas units → window pixels. With the canvas_items stretch mode this is the UI scale.
	var px_scale := get_viewport().get_final_transform().x.x
	if px_scale <= 0.0:
		px_scale = 1.0
	var centre: Vector2
	if preview:
		draw_style_box(UI.box(Color(0.16, 0.17, 0.2), 8), Rect2(Vector2.ZERO, size))
		centre = (size * px_scale / 2.0).floor()
	else:
		centre = (get_viewport().get_visible_rect().size * px_scale / 2.0).floor()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / px_scale)

	var length := float(Settings.crosshair_length)
	var gap := float(Settings.crosshair_gap)
	var thick := float(Settings.crosshair_thickness)
	var half := floorf(thick / 2.0)
	var rects: Array[Rect2] = [
		Rect2(centre.x - gap - length, centre.y - half, length, thick),
		Rect2(centre.x + gap, centre.y - half, length, thick),
		Rect2(centre.x - half, centre.y - gap - length, thick, length),
		Rect2(centre.x - half, centre.y + gap, thick, length),
	]
	if Settings.crosshair_dot:
		rects.append(Rect2(centre.x - half, centre.y - half, thick, thick))
	if Settings.crosshair_outline:
		for r in rects:
			draw_rect(r.grow(1.0), Color(0.0, 0.0, 0.0, 0.9))
	var color := Settings.crosshair_rgb()
	for r in rects:
		draw_rect(r, color)
