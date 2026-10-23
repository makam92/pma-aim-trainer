extends RefCounted
## Colours, theme, number formatting and small factory helpers shared by all UI.

const TEXT := Color(0.92, 0.93, 0.95)
const DIM := Color(0.6, 0.64, 0.71)
const ACCENT := Color(1.0, 0.69, 0.16)
const GOOD := Color(0.27, 0.9, 0.56)
const BAD := Color(1.0, 0.33, 0.37)
const PANEL := Color(0.075, 0.083, 0.105, 0.96)
const FIELD := Color(0.055, 0.06, 0.08)
const LINE := Color(1.0, 1.0, 1.0, 0.08)
const NONE := Color(0.0, 0.0, 0.0, 0.0)
const TARGET := Color(1.0, 0.28, 0.34)
const START := Color(1.0, 0.75, 0.22)
const BUTTON_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]

static var _bold: FontVariation


static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.9
	return _bold


static func box(bg: Color, radius: int = 8, border: Color = NONE, pad_x: float = 12.0, pad_y: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_x if pad_y < 0.0 else pad_y
	s.content_margin_bottom = pad_x if pad_y < 0.0 else pad_y
	s.anti_aliasing = true
	return s


## How a normal button looks in one of BUTTON_STATES, with the given padding.
static func button_box(state: String, pad_x: float = 18.0, pad_y: float = 9.0) -> StyleBoxFlat:
	match state:
		"hover":
			return box(Color(0.18, 0.19, 0.245), 8, Color(1, 1, 1, 0.14), pad_x, pad_y)
		"pressed", "hover_pressed":
			return box(Color(0.1, 0.11, 0.14), 8, ACCENT, pad_x, pad_y)
		"disabled":
			return box(Color(0.1, 0.1, 0.12), 8, LINE, pad_x, pad_y)
	return box(Color(0.13, 0.14, 0.18), 8, LINE, pad_x, pad_y)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)

	for state: String in BUTTON_STATES:
		t.set_stylebox(state, "Button", button_box(state))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for item: String in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(item, "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)

	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	var checked := svg_icon('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="1" y="1" width="18" height="18" rx="4" fill="#ffb028"/><path d="M5 10.5l3.2 3.2L15 6.8" fill="none" stroke="#17120a" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>')
	var unchecked := svg_icon('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="1.5" y="1.5" width="17" height="17" rx="4" fill="#0e1015" stroke="#6a7080" stroke-width="1.5"/></svg>')
	for icon: String in ["checked", "checked_disabled"]:
		t.set_icon(icon, "CheckBox", checked)
	for icon: String in ["unchecked", "unchecked_disabled"]:
		t.set_icon(icon, "CheckBox", unchecked)

	t.set_stylebox("panel", "PanelContainer", box(PANEL, 14, LINE, 24))
	t.set_stylebox("normal", "LineEdit", box(FIELD, 6, Color(1, 1, 1, 0.1), 10, 6))
	t.set_stylebox("focus", "LineEdit", box(NONE, 6, ACCENT, 10, 6))
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), 3, NONE, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.15), 3, NONE, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 3, NONE, 0, 3))
	return t


static func svg_icon(svg: String) -> ImageTexture:
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 18, color: Color = TEXT, is_bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_bold:
		l.add_theme_font_override("font", bold())
	return l


static func button(text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		var ink := Color(0.09, 0.07, 0.03)
		b.add_theme_stylebox_override("normal", box(ACCENT, 8, NONE, 22, 10))
		b.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.15), 8, NONE, 22, 10))
		b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.15), 8, NONE, 22, 10))
		b.add_theme_stylebox_override("hover_pressed", box(ACCENT.darkened(0.15), 8, NONE, 22, 10))
		for item: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(item, ink)
		b.add_theme_font_override("font", bold())
	b.pressed.connect(on_press)
	return b


static func options(items: Array, selected: int, on_select: Callable) -> OptionButton:
	var o := OptionButton.new()
	for item: Variant in items:
		o.add_item(str(item))
	o.select(selected)
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(on_select)
	return o


static func vbox(separation: int = 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func hbox(separation: int = 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func separator() -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	return r


## A dark full-screen layer behind menus; the 3D room stays faintly visible.
static func backdrop(alpha: float = 0.78) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.025, 0.035, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r


static func place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Whole number with spaces between thousands, e.g. 12 480.
static func num(value: Variant) -> String:
	var n := roundi(float(value))
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = " " + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## Decimal number with a decimal comma.
static func dec(value: Variant, digits: int = 2) -> String:
	return (("%." + str(digits) + "f") % float(value)).replace(".", ",")


static func ms(value: Variant, signed: bool = false) -> String:
	if value == null:
		return "–"
	var n := roundi(float(value))
	return ("+" if signed and n > 0 else "") + "%d ms" % n


## Roughly how long a playlist of `rounds` rounds takes, with the start and results screen of each.
static func playlist_time(rounds: int) -> String:
	var minutes := maxi(1, roundi(rounds * 1.2))
	return "cirka %d %s" % [minutes, "minut" if minutes == 1 else "minuter"]


## "3 rundor", "1 runda".
static func rounds_text(rounds: int) -> String:
	return "%d %s" % [rounds, "runda" if rounds == 1 else "rundor"]


## The change in a mode's headline number between two scores, e.g. "+3", "-120 p" or "+2,1 %".
static func delta_text(mode: String, diff: float) -> String:
	var sign := "+" if diff > 0.0 else ("-" if diff < 0.0 else "±")
	var size := absf(diff)
	match mode:
		"track":
			return sign + dec(size / 100.0, 1) + " %"
		"strafe":
			return sign + num(size) + " p"
	return sign + num(size)


## A score without its unit, for compact lists and chart labels.
static func short_value(mode: String, score: Variant) -> String:
	match mode:
		"track":
			return dec(float(score) / 100.0, 1) + " %"
		"strafe":
			return num(score)
	return str(int(score))


## The headline number of a stored run, as shown in menus and lists.
static func main_value(mode: String, r: Dictionary) -> String:
	if mode in ["grid", "flick", "micro", "confirm", "strafeaim"]:
		return "%d träffar" % int(r.get("score", 0))
	if mode in ["tconfirm", "punch"]:
		return "%d kills" % int(r.get("score", 0))
	if mode == "track":
		return dec(float(r.get("score", 0)) / 100.0, 1) + " %"
	return num(r.get("score", 0)) + " p"
