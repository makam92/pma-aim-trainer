extends Control
## CS-style crosshair drawn in whole screen pixels, so it stays sharp and even at any window size.
## At a lower resolution it's stretched like the rest of the game, as CS2's would be, then put on
## whole pixels the same way on both sides. With `preview` set, it draws centred in its own rect on
## a dark background instead.

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
	var area := get_viewport().get_visible_rect().size
	if preview:
		draw_style_box(UI.box(Color(0.16, 0.17, 0.2), 8), Rect2(Vector2.ZERO, size))
		area = size
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / px_scale)
	var pixels := (area * px_scale).floor()
	var stretch := Settings.view_stretch(Vector2(get_window().size))
	var length := float(Settings.crosshair_length)
	var gap := float(Settings.crosshair_gap)
	var thick := float(Settings.crosshair_thickness)
	# Along x: the vertical lines' width and the horizontal arms; along y the other way round.
	var x := _spans(pixels.x, thick * stretch.x, gap * stretch.x, length * stretch.x)
	var y := _spans(pixels.y, thick * stretch.y, gap * stretch.y, length * stretch.y)
	var rects: Array[Rect2] = [
		_rect(x["before"], y["line"]), _rect(x["after"], y["line"]),
		_rect(x["line"], y["before"]), _rect(x["line"], y["after"]),
	]
	if Settings.crosshair_dot:
		rects.append(_rect(x["line"], y["line"]))
	if Settings.crosshair_outline:
		for r in rects:
			draw_rect(r.grow(1.0), Color(0.0, 0.0, 0.0, 0.9))
	var color := Settings.crosshair_rgb()
	for r in rects:
		draw_rect(r, color)


## One axis of the crosshair in whole pixels, mirrored around the middle of `pixels`: the line
## across it, `thick` wide ("line"), and the arms `gap` from the middle and `length` long on each
## side ("before", "after"), each as Vector2(from, to). Odd widths centre on a pixel, even ones
## between two, so both sides always come out the same.
static func _spans(pixels: float, thick: float, gap: float, length: float) -> Dictionary:
	var t := maxi(roundi(thick), 1)
	var g := roundi(gap)
	var l := roundi(length)
	var odd := t % 2
	var mid := floorf(pixels / 2.0)
	var half := floorf(t / 2.0)
	return {
		"line": Vector2(mid - half, mid - half + t),
		"before": Vector2(mid - g - l, mid - g),
		"after": Vector2(mid + odd + g, mid + odd + g + l),
	}


static func _rect(along_x: Vector2, along_y: Vector2) -> Rect2:
	return Rect2(along_x.x, along_y.x, along_x.y - along_x.x, along_y.y - along_y.x)
