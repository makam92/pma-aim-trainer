extends Control
## CS2's crosshair drawn in whole screen pixels, so it stays sharp and even at any window size. Its
## sizes are CS2's: whole pixels at the screen height it was made for, scaled to the resolution the
## game is drawn at. At a lower resolution it's stretched like the rest of the game, as CS2's would be,
## then put on whole pixels the same way on both sides. With `preview` set, it draws centred in its
## own rect on a dark background instead.

const UI = preload("res://scripts/ui/ui_kit.gd")
const DOT_ONLY := 6

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
	var window := Vector2(get_window().size)
	var stretch := Settings.view_stretch(window)
	# Whole pixels where the game is drawn first, as CS2 rounds them, then stretched with the picture.
	var factor := Settings.crosshair_scale(window.y)
	var length := roundi(Settings.crosshair_length * factor)
	var gap := roundi(Settings.crosshair_gap * factor)
	var thick := roundi(Settings.crosshair_thickness * factor)
	if Settings.crosshair_thickness > 0:
		thick = maxi(thick, 1)
	if thick == 0:
		return
	var x := _spans(pixels.x, thick * stretch.x, gap * stretch.x, length * stretch.x)
	var y := _spans(pixels.y, thick * stretch.y, gap * stretch.y, length * stretch.y)
	var rects: Array[Rect2] = []
	if Settings.crosshair_style != DOT_ONLY and length > 0:
		rects.append(_rect(x["before"], y["line"]))
		rects.append(_rect(x["after"], y["line"]))
		if not Settings.crosshair_t:
			rects.append(_rect(x["line"], y["before"]))
		rects.append(_rect(x["line"], y["after"]))
	if Settings.crosshair_dot or Settings.crosshair_style == DOT_ONLY:
		rects.append(_rect(x["line"], y["line"]))
	# CS2's outline is a pixel wide, all round each bar or only along its top and left edges.
	if Settings.crosshair_outline_mode > 0:
		var edge := Vector2(maxf(roundf(stretch.x), 1.0), maxf(roundf(stretch.y), 1.0))
		var grow := edge * (2.0 if Settings.crosshair_outline_mode == 1 else 1.0)
		for r in rects:
			draw_rect(Rect2(r.position - edge, r.size + grow), Settings.crosshair_outline_rgba)
	for r in rects:
		draw_rect(r, Settings.crosshair_rgba)


## One axis of the crosshair in whole pixels around the middle of `pixels`, laid out like CS2's: the
## line across it, `thick` wide ("line"), and the arms `gap` from the middle and `length` long on each
## side ("before", "after"), each as Vector2(from, to). Even widths centre between two pixels and odd
## ones on the pixel just before the middle, as CS2 draws them (measured in its screenshots), so both
## sides always come out the same.
static func _spans(pixels: float, thick: float, gap: float, length: float) -> Dictionary:
	var t := maxi(roundi(thick), 1)
	var g := roundi(gap)
	var l := roundi(length)
	var odd := t % 2
	var mid := floorf(pixels / 2.0)
	var start := mid - ceili(t / 2.0)
	return {
		"line": Vector2(start, start + t),
		"before": Vector2(mid - odd - g - l, mid - odd - g),
		"after": Vector2(mid + g, mid + g + l),
	}


static func _rect(along_x: Vector2, along_y: Vector2) -> Rect2:
	return Rect2(along_x.x, along_y.x, along_x.y - along_x.x, along_y.y - along_y.x)
