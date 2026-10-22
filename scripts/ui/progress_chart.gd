extends Control
## Results over time: every run as a dot in the order they were played, a moving average as the
## trend line, the best run ringed, and the dates along the bottom.

const UI = preload("res://scripts/ui/ui_kit.gd")
const MONTHS := ["jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
const MAX_RUNS := 80
const SMOOTHING := 5   # runs in the moving average

var mode := "flick"
## Stored results with "date" and "score", oldest first.
var runs: Array = []

var _plot := Rect2()
var _lo := 0.0
var _hi := 1.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 330)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_style_box(UI.box(Color(0.0, 0.0, 0.0, 0.28), 10), Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var shown := runs.slice(-MAX_RUNS)
	if shown.size() < 2:
		var text := "Spela minst två rundor med de här inställningarna för att se en kurva." if shown.size() == 1 else "Inga rundor med de här inställningarna än."
		draw_string(font, Vector2(24.0, size.y / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48.0, 16, UI.DIM)
		return
	var values: Array[float] = []
	for r: Dictionary in shown:
		values.append(float(r.get("score", 0)))
	_lo = values.min()
	_hi = values.max()
	var pad := maxf((_hi - _lo) * 0.12, 1.0)
	_lo = maxf(_lo - pad, 0.0)
	_hi += pad
	_plot = Rect2(84.0, 38.0, size.x - 104.0, size.y - 78.0)

	# Horizontal grid with value labels.
	for i in 5:
		var v := lerpf(_lo, _hi, i / 4.0)
		var y := _y(v)
		draw_line(Vector2(_plot.position.x, y), Vector2(_plot.end.x, y), Color(1, 1, 1, 0.06), 1.0)
		draw_string(font, Vector2(8.0, y + 5.0), UI.short_value(mode, v), HORIZONTAL_ALIGNMENT_RIGHT, 66.0, 13, UI.DIM)

	# Date labels where a new day starts, spaced out so they don't overlap.
	var last_label_x := -INF
	var last_day := ""
	for i in shown.size():
		var day := str(shown[i].get("date", "")).substr(0, 10)
		if day != last_day:
			last_day = day
			var x := _x(i, shown.size())
			draw_line(Vector2(x, _plot.position.y), Vector2(x, _plot.end.y), Color(1, 1, 1, 0.04), 1.0)
			if x - last_label_x > 70.0:
				draw_string(font, Vector2(x - 30.0, _plot.end.y + 24.0), _short_day(day), HORIZONTAL_ALIGNMENT_CENTER, 60.0, 13, UI.DIM)
				last_label_x = x

	# Every run, the moving average, and the best run.
	var best := values.find(values.max())
	var trend := PackedVector2Array()
	for i in values.size():
		var from := maxi(0, i - SMOOTHING + 1)
		var sum := 0.0
		for j in range(from, i + 1):
			sum += values[j]
		trend.append(Vector2(_x(i, values.size()), _y(sum / (i - from + 1))))
	for i in values.size():
		draw_circle(Vector2(_x(i, values.size()), _y(values[i])), 3.5, Color(UI.TEXT, 0.45))
	draw_polyline(trend, UI.ACCENT, 3.0, true)
	var best_point := Vector2(_x(best, values.size()), _y(values[best]))
	draw_circle(best_point, 7.0, UI.GOOD, false, 2.0, true)
	draw_string(font, best_point + Vector2(-60.0, -12.0), "PB " + UI.short_value(mode, values[best]), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13, UI.GOOD)

	# Legend, above the plot.
	var lx := _plot.end.x - 270.0
	draw_circle(Vector2(lx, 18.0), 3.5, Color(UI.TEXT, 0.45))
	draw_string(font, Vector2(lx + 10.0, 23.0), "runda", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.DIM)
	draw_line(Vector2(lx + 70.0, 18.0), Vector2(lx + 96.0, 18.0), UI.ACCENT, 3.0)
	draw_string(font, Vector2(lx + 104.0, 23.0), "snitt av %d senaste" % SMOOTHING, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.DIM)


func _x(i: int, count: int) -> float:
	return _plot.position.x + _plot.size.x * i / maxf(count - 1, 1)


func _y(v: float) -> float:
	return _plot.end.y - (v - _lo) / maxf(_hi - _lo, 0.0001) * _plot.size.y


## "2026-10-06" → "6 okt"
static func _short_day(day: String) -> String:
	if day.length() < 10:
		return day
	return "%d %s" % [day.substr(8, 2).to_int(), MONTHS[clampi(day.substr(5, 2).to_int() - 1, 0, 11)]]
