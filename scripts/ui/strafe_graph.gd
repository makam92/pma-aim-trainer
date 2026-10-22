extends Control
## Speed over time around the latest shot, with the accuracy threshold, key presses and the shot.
## Before the first shot it scrolls live.

const UI = preload("res://scripts/ui/ui_kit.gd")

const BEFORE := 0.55
const AFTER := 0.2
const LIVE := 0.8
const ROW_H := 20.0
const KEY_COLORS := {
	"a": Color(0.45, 0.7, 1.0),
	"d": Color(1.0, 0.66, 0.3),
	"w": Color(0.72, 0.6, 1.0),
	"s": Color(0.55, 0.9, 0.7),
}

var sim: RefCounted
var now_t := 0.0
var shot := {}

var _t0 := 0.0
var _t1 := 1.0
var _plot := Rect2()


func _init() -> void:
	custom_minimum_size = Vector2(880, 236)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_shot(info: Dictionary) -> void:
	shot = info
	queue_redraw()


## Title, detail text and colour for a shot classified by strafe_mode.gd.
static func describe(info: Dictionary) -> Dictionary:
	var speed := roundi(float(info.get("speed", 0.0)))
	var keys: Array = info.get("keys", ["d", "a"])
	var pair := "%s+%s" % [str(keys[0]).to_upper(), str(keys[1]).to_upper()]
	var title := ""
	var color := UI.TEXT
	var parts: Array[String] = []
	match info.get("verdict", ""):
		"standing":
			return {"title": "Stillastående skott", "detail": "Räknas inte. Strafea först och stanna sedan.", "color": UI.DIM}
		"wall":
			return {"title": "Stannade mot kanten", "detail": "Räknas inte. Håll dig mellan linjerna på golvet.", "color": UI.DIM}
		"accurate":
			var delay := roundi(float(info.get("delay", 0.0)) * 1000.0)
			if delay <= 60:
				title = "PERFEKT"
				color = UI.GOOD
			elif delay <= 150:
				title = "BRA"
				color = UI.GOOD
			else:
				title = "SENT"
				color = UI.ACCENT
			parts.append("+%d ms efter att du blev träffsäker" % delay)
		"early":
			title = "FÖR TIDIGT"
			color = UI.BAD
			parts.append("%d ms innan du var träffsäker" % roundi(float(info["early"]) * 1000.0))
		"overcounter":
			title = "FÖR LÅNG KONTRA"
			color = UI.BAD
			parts.append("du hann börja glida åt andra hållet")
		_:
			title = "I RÖRELSE"
			color = UI.BAD
			parts.append("släpp knappen och kontra innan du skjuter")
	parts.append("%d u/s" % speed)
	if float(info.get("overlap", 0.0)) > 0.015:
		parts.append("%s samtidigt i %d ms" % [pair, roundi(float(info["overlap"]) * 1000.0)])
	elif not info.get("counter", false) and info.get("verdict", "") != "moving":
		parts.append("ingen kontra, du släppte bara")
	if float(info.get("gap", 0.0)) > 0.05:
		parts.append("kontran kom %d ms efter släppet" % roundi(float(info["gap"]) * 1000.0))
	if info.has("stop"):
		parts.append("stopp %d ms" % roundi(float(info["stop"]) * 1000.0))
	return {"title": title, "detail": " · ".join(parts), "color": color}


func _draw() -> void:
	draw_style_box(UI.box(Color(0.04, 0.045, 0.06, 0.86), 10), Rect2(Vector2.ZERO, size))
	if sim == null:
		return
	var font := get_theme_default_font()
	if shot.is_empty():
		_t1 = now_t
		_t0 = now_t - LIVE
	else:
		_t0 = float(shot["t"]) - BEFORE
		_t1 = float(shot["t"]) + AFTER
	var rows := _rows()
	_plot = Rect2(40.0, 46.0, size.x - 56.0, size.y - 46.0 - 26.0 - ROW_H * rows.size())
	var limit := minf(_t1, now_t)
	var top: float = sim.max_speed * 1.08
	var thr: float = sim.threshold()

	# Accurate zone, threshold and baseline.
	var y_thr := _y(thr, top)
	draw_rect(Rect2(_plot.position.x, y_thr, _plot.size.x, _plot.end.y - y_thr), Color(UI.GOOD, 0.07))
	draw_dashed_line(Vector2(_plot.position.x, y_thr), Vector2(_plot.end.x, y_thr), Color(UI.GOOD, 0.75), 1.5, 6.0)
	draw_string(font, Vector2(_plot.end.x - 260.0, y_thr - 6.0), "träffsäker under %d u/s" % roundi(thr), HORIZONTAL_ALIGNMENT_RIGHT, 260.0, 13, Color(UI.GOOD, 0.9))
	draw_line(Vector2(_plot.position.x, _plot.end.y), Vector2(_plot.end.x, _plot.end.y), Color(1, 1, 1, 0.15), 1.0)

	# Speed curve.
	var points := PackedVector2Array()
	for s: Vector3 in sim.samples:
		if s.x >= _t0 and s.x <= limit:
			points.append(Vector2(_x(s.x), _y(Vector2(s.y, s.z).length(), top)))
	if points.size() >= 2:
		draw_polyline(points, Color(0.93, 0.94, 0.97), 2.0, true)

	# Key rows, with any time both opposite keys were held marked in red.
	var row_y := _plot.end.y + 12.0
	var spans := {}
	for key: String in rows:
		spans[key] = _spans(key, limit)
		draw_string(font, Vector2(14.0, row_y + 14.0), key.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.DIM)
		for span: Vector2 in spans[key]:
			var x0 := _x(maxf(span.x, _t0))
			var x1 := _x(minf(span.y, limit))
			if x1 > x0:
				draw_rect(Rect2(x0, row_y + 3.0, x1 - x0, ROW_H - 6.0), KEY_COLORS[key])
		row_y += ROW_H
	for pair: Array in [["a", "d"], ["w", "s"]]:
		if spans.has(pair[0]) and spans.has(pair[1]):
			for a: Vector2 in spans[pair[0]]:
				for b: Vector2 in spans[pair[1]]:
					var x0 := _x(maxf(maxf(a.x, b.x), _t0))
					var x1 := _x(minf(minf(a.y, b.y), limit))
					if x1 > x0:
						draw_rect(Rect2(x0, _plot.end.y + 12.0, x1 - x0, ROW_H * rows.size()), Color(UI.BAD, 0.45))

	if shot.is_empty():
		draw_string(font, Vector2(16.0, 30.0), "Strafea och skjut. Här ser du farten och dina knapptryck.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.DIM)
		return

	# The shot, when you became accurate, and the gap between them.
	var text := describe(shot)
	var color: Color = text["color"]
	var sx := _x(float(shot["t"]))
	draw_line(Vector2(sx, _plot.position.y - 2.0), Vector2(sx, row_y), color, 2.0)
	draw_circle(Vector2(sx, _y(float(shot["speed"]), top)), 5.0, color)
	draw_string(font, Vector2(sx + 6.0, _plot.position.y + 10.0), "SKOTT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	if shot.has("t_acc"):
		var ax := _x(float(shot["t_acc"]))
		draw_circle(Vector2(ax, y_thr), 4.0, UI.GOOD)
		var by := y_thr + 16.0
		draw_line(Vector2(ax, by), Vector2(sx, by), color, 2.0)
		var ms_value := roundi((float(shot["t"]) - float(shot["t_acc"])) * 1000.0)
		var label := ("+%d ms" % ms_value) if ms_value >= 0 else ("%d ms" % ms_value)
		var mid := (ax + sx) / 2.0
		draw_rect(Rect2(mid - 34.0, by + 3.0, 68.0, 17.0), Color(0.04, 0.045, 0.06, 0.92))
		draw_string(font, Vector2(mid - 40.0, by + 16.0), label, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 13, color)
	draw_string(font, Vector2(16.0, 30.0), text["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
	var title_w := font.get_string_size(text["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(30.0 + title_w, 30.0), text["detail"], HORIZONTAL_ALIGNMENT_LEFT, size.x - 50.0 - title_w, 15, UI.DIM)


func _rows() -> Array[String]:
	var rows: Array[String] = ["a", "d"]
	for key: String in ["w", "s"]:
		if not _spans(key, now_t).filter(func(s: Vector2) -> bool: return s.y >= _t0).is_empty():
			rows.append(key)
	return rows


## Intervals [press, release] for a key, from the key log.
func _spans(key: String, until: float) -> Array:
	var out: Array = []
	var down := false
	var start := 0.0
	for e: Array in sim.key_log:
		if e[1] != key:
			continue
		if e[2] and not down:
			down = true
			start = e[0]
		elif not e[2] and down:
			down = false
			out.append(Vector2(start, e[0]))
	if down:
		out.append(Vector2(start, until))
	return out


func _x(t: float) -> float:
	return _plot.position.x + (t - _t0) / (_t1 - _t0) * _plot.size.x


func _y(speed: float, top: float) -> float:
	return _plot.end.y - clampf(speed / top, 0.0, 1.0) * _plot.size.y
