extends Control
## Settings in tabs: sensitivity and crosshair (also taken from CS2), graphics and sound, the weapon,
## drills and bots, and the CS2 files.

signal back_requested

const UI = preload("res://scripts/ui/ui_kit.gd")
const Crosshair = preload("res://scripts/ui/crosshair.gd")
const CrosshairImport = preload("res://scripts/crosshair_import.gd")
const CROSSHAIR_HELP := "Hämta ditt crosshair från din CS2-config, eller klistra in en crosshair-kod (CS…) från CS2 eller en kompis."
const TABS := [["aim", "Sens och crosshair"], ["graphics", "Grafik och ljud"], ["weapon", "Vapen"],
	["drills", "Övningar"], ["files", "CS2-filer"]]
## Every column has this width, so a page with one column doesn't stretch across the panel.
const COLUMN_WIDTH := 500.0
## The tallest page, so the panel keeps its size from tab to tab.
const PAGE_HEIGHT := 560.0

var _tab := "aim"
var _tab_buttons := {}
var _pages := {}
var _info: Label
var _models_info: Label
var _import_button: Button
var _import_bar: ProgressBar
var _import_status: Label
var _code: LineEdit
var _crosshair_status: Label
var _crosshair_info: Label
var _color: OptionButton
var _outline: OptionButton
var _sliders := {}      # setting → [slider, its value], so an imported crosshair shows in them
var _checks := {}       # setting → checkbox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := UI.vbox(18)
	panel.add_child(col)
	col.add_child(UI.label("INSTÄLLNINGAR", 28, UI.TEXT, true))
	var tabs := UI.hbox(8)
	for tab: Array in TABS:
		var id: String = tab[0]
		var b := UI.button(tab[1], func() -> void: show_tab(id))
		b.add_theme_font_size_override("font_size", 16)
		_tab_buttons[id] = b
		tabs.add_child(b)
	col.add_child(tabs)
	var pages := UI.vbox(0)
	pages.custom_minimum_size = Vector2(COLUMN_WIDTH * 2.0 + 40.0, PAGE_HEIGHT)
	col.add_child(pages)
	_pages = {"aim": _aim_page(), "graphics": _graphics_page(), "weapon": _weapon_page(),
		"drills": _drills_page(), "files": _files_page()}
	for id: String in _pages:
		pages.add_child(_pages[id])
	var buttons := UI.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(UI.button("Tillbaka", func() -> void: back_requested.emit(), true))
	col.add_child(buttons)
	show_tab(_tab)

	Settings.changed.connect(_refresh_info)
	_refresh_info()
	Settings.changed.connect(_refresh_crosshair)
	_refresh_crosshair()
	Importer.progress.connect(_on_import_progress)
	Importer.finished.connect(_on_import_finished)
	Agents.loaded.connect(_refresh_models)
	_refresh_models()


## Shows one tab's page; the screen opens on the one shown last.
func show_tab(id: String) -> void:
	_tab = id
	for tab_id: String in _pages:
		_pages[tab_id].visible = tab_id == id
		UI.style_tab(_tab_buttons[tab_id], tab_id == id)


## Sensitivity and the crosshair's settings on the left; a preview and taking a crosshair from CS2 on
## the right.
func _aim_page() -> Control:
	var page := UI.hbox(40)
	var left := _column(page)
	var right := _column(page)
	left.add_child(_section("Sikte"))
	var aim := _grid()
	left.add_child(aim)
	_row(aim, "Sensitivity i CS2", _spin(0.01, 20.0, 0.001, 0.05, Settings.sensitivity,
			func(v: float) -> void: Settings.update("sensitivity", v)))
	_row(aim, "Mus-DPI", _spin(100.0, 32000.0, 1.0, 50.0, Settings.dpi,
			func(v: float) -> void: Settings.update("dpi", int(v))))
	_info = _note("", 15)
	left.add_child(_info)

	left.add_child(_section("Crosshair"))
	var ch := _grid()
	left.add_child(ch)
	var colors := Settings.CROSSHAIR_COLORS.map(func(c: Dictionary) -> String: return c["name"]) + ["Egen"]
	_color = UI.options(colors, 0, _pick_color)
	_row(ch, "Färg", _color)
	_row(ch, "Längd", _slider(0, 30, Settings.crosshair_length, "crosshair_length"))
	_row(ch, "Mellanrum", _slider(-10, 30, Settings.crosshair_gap, "crosshair_gap"))
	_row(ch, "Tjocklek", _slider(1, 12, Settings.crosshair_thickness, "crosshair_thickness"))
	_outline = UI.options(["Av", "Hel", "Halv (uppe och vänster)"], Settings.crosshair_outline_mode,
		func(i: int) -> void: Settings.update("crosshair_outline_mode", i))
	_row(ch, "Kontur", _outline)
	_row(ch, "Prick i mitten", _check(Settings.crosshair_dot, "crosshair_dot"))
	_row(ch, "T-stil", _check(Settings.crosshair_t, "crosshair_t"))
	_crosshair_info = _note("")
	left.add_child(_crosshair_info)

	right.add_child(_section("Förhandsvisning"))
	var preview := Crosshair.new()
	preview.preview = true
	preview.custom_minimum_size = Vector2(0, 220)
	right.add_child(preview)
	right.add_child(_section("Crosshair från CS2"))
	var from_cs2 := UI.button("Hämta från CS2", func() -> void: _take_crosshair(CrosshairImport.from_cs2(), "Hämtat från CS2"))
	from_cs2.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(from_cs2)
	var paste := UI.hbox(10)
	_code = LineEdit.new()
	_code.placeholder_text = "Eller klistra in en crosshair-kod: CS…"
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_submitted.connect(func(text: String) -> void: _take_crosshair(CrosshairImport.from_code(text), "Koden är inläst"))
	paste.add_child(_code)
	paste.add_child(UI.button("Använd", func() -> void: _take_crosshair(CrosshairImport.from_code(_code.text), "Koden är inläst")))
	right.add_child(paste)
	_crosshair_status = _note(CROSSHAIR_HELP)
	right.add_child(_crosshair_status)
	return page


## The picture on the left; the room, the players and the sound on the right.
func _graphics_page() -> Control:
	var page := UI.hbox(40)
	var left := _column(page)
	var right := _column(page)
	left.add_child(_section("Bild"))
	var picture := _grid()
	left.add_child(picture)
	var resolutions := Settings.RESOLUTIONS.map(func(r: Vector2i) -> String: return "Skärmens" if r == Vector2i.ZERO else "%dx%d" % [r.x, r.y])
	_row(picture, "Upplösning", UI.options(resolutions, Settings.resolution, func(i: int) -> void: Settings.update("resolution", i)))
	_row(picture, "Skalning", UI.options(["Utsträckt", "Svarta kanter"], 0 if Settings.stretched else 1,
			func(i: int) -> void: Settings.update("stretched", i == 0)))
	_row(picture, "Helskärm", _check(Settings.fullscreen, "fullscreen"))
	_row(picture, "VSync", _check(Settings.vsync, "vsync"))
	var caps := Settings.FPS_CAPS.map(func(f: int) -> String: return "Obegränsat" if f == 0 else str(f))
	_row(picture, "FPS-tak", UI.options(caps, Settings.fps_cap, func(i: int) -> void: Settings.update("fps_cap", i)))
	right.add_child(_section("Miljö och ljud"))
	var room := _grid()
	right.add_child(room)
	_row(room, "Miljö", UI.options(["Dust (ljus)", "Mörk"], Settings.room_theme, func(i: int) -> void: Settings.update("room_theme", i)))
	_row(room, "Spelarmodeller", UI.options(["CS2-modeller", "Enkla"], 0 if Settings.use_cs2_models else 1,
			func(i: int) -> void: Settings.update("use_cs2_models", i == 0)))
	_row(room, "Volym", _slider(0, 100, roundi(Settings.volume * 100.0), "volume"))
	return page


func _weapon_page() -> Control:
	var page := UI.hbox(40)
	var column := _column(page)
	column.add_child(_section("Vapen"))
	var weapon := _grid()
	column.add_child(weapon)
	_row(weapon, "Vapen i handen", UI.options(["AK-47, som i CS2", "Inget"], 0 if Settings.viewmodel else 1,
			func(i: int) -> void: Settings.update("viewmodel", i == 0)))
	_row(weapon, "Skottljud", UI.options(["AK-47 från CS2", "Enkelt"], 0 if Settings.ak_sound else 1,
			func(i: int) -> void: Settings.update("ak_sound", i == 0)))
	_row(weapon, "Viewmodel FOV", _slider(54, 68, Settings.viewmodel_fov, "viewmodel_fov"))
	_row(weapon, "Kulhål och spårljus", _check(Settings.impacts, "impacts"))
	_row(weapon, "Rekyl och spray", UI.options(["Av, perfekt sikte", "AK-47, som i CS2"], 1 if Settings.ak_recoil else 0,
			func(i: int) -> void: Settings.update("ak_recoil", i == 1)))
	return page


func _drills_page() -> Control:
	var page := UI.hbox(40)
	var column := _column(page)
	column.add_child(_section("Övningar"))
	var drills := _grid()
	column.add_child(drills)
	_row(drills, "Nedräkning före start", _check(Settings.countdown, "countdown"))
	_row(drills, "Visa tid efter träff", _check(Settings.hit_times, "hit_times"))
	_row(drills, "Gubbar crouchar", UI.options(["Ibland, som i CS2", "Aldrig"], 0 if Settings.bot_crouch else 1,
			func(i: int) -> void: Settings.update("bot_crouch", i == 0)))
	column.add_child(_note("Med crouch på croucher gubbarna i Tracking och Tracking Confirmation ofta när de stannar och ibland mitt i ADAD, som i CS2. Crouchade går de i 34 % av maxfarten och huvudet sjunker 17 units."))
	return page


func _files_page() -> Control:
	var page := UI.hbox(40)
	var column := _column(page)
	column.add_child(_section("CS2-filer"))
	_models_info = _note("")
	column.add_child(_models_info)
	var import_row := UI.hbox(14)
	_import_button = UI.button("Importera från CS2", func() -> void: Importer.start())
	import_row.add_child(_import_button)
	_import_bar = ProgressBar.new()
	_import_bar.show_percentage = false
	_import_bar.custom_minimum_size = Vector2(0, 10)
	_import_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_import_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_import_bar.add_theme_stylebox_override("background", UI.box(UI.FIELD, 5, UI.LINE, 0, 0))
	_import_bar.add_theme_stylebox_override("fill", UI.box(UI.ACCENT, 5, UI.NONE, 0, 0))
	_import_bar.visible = false
	import_row.add_child(_import_bar)
	column.add_child(import_row)
	_import_status = _note("Läser in spelarmodeller, hitboxar, vapen, AK:n i första person och AK-ljud från din egen CS2-installation. Tar under en minut.")
	column.add_child(_import_status)
	return page


func _refresh_models() -> void:
	if not Agents.is_loaded:
		_models_info.text = "CS2-modellerna laddas…"
	elif Agents.available():
		var parts := ["%d agenter och %d vapen" % [Agents.agents[Agents.T].size() + Agents.agents[Agents.CT].size(), Agents.weapons.size()]]
		if Agents.has_viewmodel():
			parts.append("AK:n i första person")
		if Sfx.has_ak_sound():
			parts.append("AK-ljud")
		_models_info.text = "Inläst från din CS2-installation: %s." % ", ".join(PackedStringArray(parts))
	else:
		_models_info.text = "Inga CS2-filer än. Importera dem från din CS2-installation, så används CS2:s riktiga gubbar, hitboxar, AK och ljud."
	_import_button.text = "Uppdatera från CS2" if Agents.available() else "Importera från CS2"


func _on_import_progress(step: int, steps: int, text: String) -> void:
	_import_button.disabled = true
	_import_bar.visible = true
	_import_bar.max_value = steps
	_import_bar.value = step
	_import_status.text = "%s … (%d av %d)" % [text, step + 1, steps]


func _on_import_finished(ok: bool, message: String) -> void:
	_import_button.disabled = false
	_import_bar.visible = false
	_import_status.text = message
	_import_status.add_theme_color_override("font_color", UI.GOOD if ok else UI.BAD)


func _refresh_info() -> void:
	_info.text = "eDPI %s · %s cm per varv. Siktet vrids precis som i CS2: 0,022° gånger sensitivity per musrörelse, med raw input och samma FOV (90° i 4:3)." % [
		UI.num(Settings.edpi()), UI.dec(Settings.cm_per_360(), 1)]


## Shows the crosshair settings as they are, also after an import changed them all at once.
func _refresh_crosshair() -> void:
	for key: String in ["crosshair_length", "crosshair_gap", "crosshair_thickness"]:
		var value: int = Settings.get(key)
		(_sliders[key][0] as HSlider).set_value_no_signal(value)
		(_sliders[key][1] as Label).text = str(value)
	for key: String in ["crosshair_dot", "crosshair_t"]:
		(_checks[key] as CheckBox).set_pressed_no_signal(Settings.get(key))
	_outline.select(Settings.crosshair_outline_mode)
	var own := _color.item_count - 1
	_color.set_item_text(own, "Egen  #" + Settings.crosshair_rgba.to_html(false).to_upper())
	var preset := _preset_of(Settings.crosshair_rgba)
	_color.select(preset if preset >= 0 else own)
	var height := Settings.crosshair_screen_height
	_crosshair_info.text = ("Storlekarna är hela pixlar vid %d px skärmhöjd, som i CS2, och skalas till upplösningen du kör i." % height) \
		if height > 0 else "Storlekarna är hela pixlar i upplösningen du kör i, som i CS2."


## Uses what crosshair_import.gd read, or says what went wrong.
func _take_crosshair(result: Dictionary, done: String) -> void:
	if result.has("error"):
		_crosshair_status.text = result["error"]
		_crosshair_status.add_theme_color_override("font_color", UI.BAD)
		return
	Settings.set_crosshair(result["crosshair"])
	_code.text = ""
	_crosshair_status.text = "%s: %s." % [done, CrosshairImport.describe(result["crosshair"])]
	_crosshair_status.add_theme_color_override("font_color", UI.GOOD)


## A colour from the list keeps the crosshair's opacity; "Egen" (the last) is whatever was imported.
func _pick_color(index: int) -> void:
	if index >= Settings.CROSSHAIR_COLORS.size():
		return
	var color: Color = Settings.CROSSHAIR_COLORS[index]["color"]
	color.a = Settings.crosshair_rgba.a
	Settings.update("crosshair_rgba", color)


## Which colour in the list this is, ignoring opacity, or -1.
static func _preset_of(color: Color) -> int:
	for i in Settings.CROSSHAIR_COLORS.size():
		var c: Color = Settings.CROSSHAIR_COLORS[i]["color"]
		if Color(c, color.a).is_equal_approx(color):
			return i
	return -1


## A column of a page, COLUMN_WIDTH wide; two fill the panel side by side.
func _column(page: HBoxContainer) -> VBoxContainer:
	var column := UI.vbox(12)
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	page.add_child(column)
	return column


func _section(text: String) -> Label:
	var l := UI.label(text.to_upper(), 14, UI.ACCENT, true)
	return l


## A dim explanation that wraps within its column.
func _note(text: String, font_size: int = 14) -> Label:
	var l := UI.label(text, font_size, UI.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	return l


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 10)
	return g


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var l := UI.label(text, 16, UI.TEXT)
	l.custom_minimum_size = Vector2(170, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _spin(min_value: float, max_value: float, step: float, arrow_step: float, value: float, on_change: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.custom_arrow_step = arrow_step
	s.value = value
	s.select_all_on_focus = true
	s.value_changed.connect(on_change)
	return s


func _slider(min_value: int, max_value: int, value: int, key: String) -> Control:
	var row := UI.hbox(10)
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = 1
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UI.label(str(value), 16, UI.TEXT)
	l.custom_minimum_size = Vector2(36, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(_on_slider.bind(key, l))
	row.add_child(s)
	row.add_child(l)
	_sliders[key] = [s, l]
	return row


func _on_slider(value: float, key: String, l: Label) -> void:
	l.text = str(int(value))
	if key == "volume":
		Settings.update(key, value / 100.0)
	else:
		Settings.update(key, int(value))


func _check(value: bool, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void: Settings.update(key, on))
	_checks[key] = c
	return c
