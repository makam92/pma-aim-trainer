extends Control
## Summary after the daily playlist: every exercise with its runs, the best one, and the change
## since the previous playlist, plus how many days in a row it has been done.

signal menu_requested

const UI = preload("res://scripts/ui/ui_kit.gd")

var _streak: Label
var _date: Label
var _rows: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop(0.72))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 0)
	center.add_child(panel)
	var col := UI.vbox(10)
	panel.add_child(col)
	col.add_child(UI.label("DAGENS PASS KLART", 15, UI.ACCENT, true))
	_streak = UI.label("", 48, UI.TEXT, true)
	col.add_child(_streak)
	_date = UI.label("", 15, UI.DIM)
	col.add_child(_date)
	col.add_child(UI.separator())
	_rows = GridContainer.new()
	_rows.columns = 5
	_rows.add_theme_constant_override("h_separation", 26)
	_rows.add_theme_constant_override("v_separation", 12)
	col.add_child(_rows)
	col.add_child(UI.separator())
	col.add_child(UI.label("Jämförelsen gäller ditt bästa mot förra passets bästa, om du körde med samma inställningar.", 14, UI.DIM))
	var buttons := UI.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(UI.button("Till menyn  (Esc)", func() -> void: menu_requested.emit(), true))
	col.add_child(buttons)


## `results` (and the previous playlist's) map mode → {"scores", "variant", "best"}, or null if skipped.
func show_summary(order: Array, titles: Dictionary, results: Dictionary, previous: Variant, streak: int) -> void:
	_streak.text = "%d %s i rad" % [streak, "dag" if streak == 1 else "dagar"]
	_date.text = Time.get_date_string_from_system()
	var before: Dictionary = previous.get("results", {}) if previous is Dictionary else {}
	UI.clear(_rows)
	for heading: String in ["Övning", "Inställning", "Rundor", "Bäst", "Mot förra passet"]:
		_rows.add_child(UI.label(heading, 13, UI.DIM, true))
	for mode: String in order:
		var r: Variant = results.get(mode)
		_rows.add_child(UI.label(titles[mode], 17, UI.TEXT, true))
		if r == null:
			_rows.add_child(UI.label("–", 15, UI.DIM))
			_rows.add_child(UI.label("Hoppade över", 16, UI.DIM))
			_rows.add_child(UI.label("", 15, UI.DIM))
			_rows.add_child(UI.label("", 15, UI.DIM))
			continue
		var scores: Array = r["scores"]
		_rows.add_child(UI.label(r["variant"], 14, UI.DIM))
		_rows.add_child(UI.label("  ·  ".join(PackedStringArray(scores.map(func(s: Variant) -> String: return UI.short_value(mode, s)))), 16, UI.TEXT))
		var top: float = scores.max()
		var best := UI.label(UI.main_value(mode, {"score": top}), 17, UI.TEXT, true)
		if r.get("best", false):
			best.text += "   PB!"
			best.add_theme_color_override("font_color", UI.GOOD)
		_rows.add_child(best)
		var old_top: Variant = _top_score(before.get(mode))
		if old_top != null and (before[mode] as Dictionary).get("variant", "") == r["variant"]:
			var diff := top - float(old_top)
			var color := UI.GOOD if diff > 0.0 else (UI.BAD if diff < 0.0 else UI.DIM)
			_rows.add_child(UI.label(UI.delta_text(mode, diff), 17, color, true))
		else:
			_rows.add_child(UI.label("–", 15, UI.DIM))


## The best score of a stored playlist entry for one mode, or null.
static func _top_score(entry: Variant) -> Variant:
	if not entry is Dictionary:
		return null
	var scores: Array = entry.get("scores", [])
	return scores.max() if not scores.is_empty() else null
