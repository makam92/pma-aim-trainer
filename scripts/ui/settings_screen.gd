extends Control
## Sensitivity, crosshair, bots, CS2 files, graphics and sound, and the weapon.

signal back_requested

const UI = preload("res://scripts/ui/ui_kit.gd")
const Crosshair = preload("res://scripts/ui/crosshair.gd")

var _info: Label
var _models_info: Label
var _import_button: Button
var _import_bar: ProgressBar
var _import_status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 0)
	center.add_child(panel)
	var col := UI.vbox(18)
	panel.add_child(col)
	col.add_child(UI.label("INSTÄLLNINGAR", 28, UI.TEXT, true))

	var columns := UI.hbox(40)
	col.add_child(columns)
	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var right := UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	left.add_child(_section("Sikte"))
	var aim := _grid()
	left.add_child(aim)
	_row(aim, "Sensitivity i CS2", _spin(0.01, 20.0, 0.001, 0.05, Settings.sensitivity,
			func(v: float) -> void: Settings.update("sensitivity", v)))
	_row(aim, "Mus-DPI", _spin(100.0, 32000.0, 1.0, 50.0, Settings.dpi,
			func(v: float) -> void: Settings.update("dpi", int(v))))
	_info = UI.label("", 15, UI.DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(440, 0)
	left.add_child(_info)

	left.add_child(_section("Crosshair"))
	var ch := _grid()
	left.add_child(ch)
	var colors := Settings.CROSSHAIR_COLORS.map(func(c: Dictionary) -> String: return c["name"])
	_row(ch, "Färg", UI.options(colors, Settings.crosshair_color, func(i: int) -> void: Settings.update("crosshair_color", i)))
	_row(ch, "Längd", _slider(1, 20, Settings.crosshair_length, "crosshair_length"))
	_row(ch, "Mellanrum", _slider(0, 15, Settings.crosshair_gap, "crosshair_gap"))
	_row(ch, "Tjocklek", _slider(1, 6, Settings.crosshair_thickness, "crosshair_thickness"))
	_row(ch, "Kontur", _check(Settings.crosshair_outline, "crosshair_outline"))
	_row(ch, "Prick i mitten", _check(Settings.crosshair_dot, "crosshair_dot"))

	left.add_child(_section("Gubbar"))
	var bots := _grid()
	left.add_child(bots)
	_row(bots, "Crouch", UI.options(["Ibland, som i CS2", "Aldrig"], 0 if Settings.bot_crouch else 1,
			func(i: int) -> void: Settings.update("bot_crouch", i == 0)))
	var bots_info := UI.label("Gubbarna i Tracking och Tracking Confirmation croucher ofta när de stannar och ibland mitt i ADAD. Crouchade går de i 34 % av maxfarten och huvudet sjunker 17 units.", 14, UI.DIM)
	bots_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bots_info.custom_minimum_size = Vector2(440, 0)
	left.add_child(bots_info)

	left.add_child(_section("CS2-filer"))
	_models_info = UI.label("", 14, UI.DIM)
	_models_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_models_info.custom_minimum_size = Vector2(440, 0)
	left.add_child(_models_info)
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
	left.add_child(import_row)
	_import_status = UI.label("Läser in spelarmodeller, hitboxar, vapen, AK:n i första person och AK-ljud från din egen CS2-installation. Tar under en minut.", 14, UI.DIM)
	_import_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_import_status.custom_minimum_size = Vector2(440, 0)
	left.add_child(_import_status)
	Importer.progress.connect(_on_import_progress)
	Importer.finished.connect(_on_import_finished)

	right.add_child(_section("Förhandsvisning"))
	var preview := Crosshair.new()
	preview.preview = true
	preview.custom_minimum_size = Vector2(0, 150)
	right.add_child(preview)

	right.add_child(_section("Grafik och ljud"))
	var gfx := _grid()
	right.add_child(gfx)
	_row(gfx, "Miljö", UI.options(["Dust (ljus)", "Mörk"], Settings.room_theme, func(i: int) -> void: Settings.update("room_theme", i)))
	_row(gfx, "Spelarmodeller", UI.options(["CS2-modeller", "Enkla"], 0 if Settings.use_cs2_models else 1,
			func(i: int) -> void: Settings.update("use_cs2_models", i == 0)))
	var resolutions := Settings.RESOLUTIONS.map(func(r: Vector2i) -> String: return "Skärmens" if r == Vector2i.ZERO else "%dx%d" % [r.x, r.y])
	_row(gfx, "Upplösning", UI.options(resolutions, Settings.resolution, func(i: int) -> void: Settings.update("resolution", i)))
	_row(gfx, "Skalning", UI.options(["Utsträckt", "Svarta kanter"], 0 if Settings.stretched else 1,
			func(i: int) -> void: Settings.update("stretched", i == 0)))
	_row(gfx, "Helskärm", _check(Settings.fullscreen, "fullscreen"))
	_row(gfx, "VSync", _check(Settings.vsync, "vsync"))
	var caps := Settings.FPS_CAPS.map(func(f: int) -> String: return "Obegränsat" if f == 0 else str(f))
	_row(gfx, "FPS-tak", UI.options(caps, Settings.fps_cap, func(i: int) -> void: Settings.update("fps_cap", i)))
	_row(gfx, "Volym", _slider(0, 100, roundi(Settings.volume * 100.0), "volume"))

	right.add_child(_section("Vapen"))
	var weapon := _grid()
	right.add_child(weapon)
	_row(weapon, "Vapen i handen", UI.options(["AK-47, som i CS2", "Inget"], 0 if Settings.viewmodel else 1,
			func(i: int) -> void: Settings.update("viewmodel", i == 0)))
	_row(weapon, "Skottljud", UI.options(["AK-47 från CS2", "Enkelt"], 0 if Settings.ak_sound else 1,
			func(i: int) -> void: Settings.update("ak_sound", i == 0)))
	_row(weapon, "Viewmodel FOV", _slider(54, 68, Settings.viewmodel_fov, "viewmodel_fov"))
	_row(weapon, "Kulhål och spårljus", _check(Settings.impacts, "impacts"))
	_row(weapon, "Rekyl och spray", UI.options(["Av, perfekt sikte", "AK-47, som i CS2"], 1 if Settings.ak_recoil else 0,
			func(i: int) -> void: Settings.update("ak_recoil", i == 1)))

	var buttons := UI.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_child(UI.button("Tillbaka", func() -> void: back_requested.emit(), true))
	col.add_child(buttons)

	Settings.changed.connect(_refresh_info)
	_refresh_info()
	Agents.loaded.connect(_refresh_models)
	_refresh_models()


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


func _section(text: String) -> Label:
	var l := UI.label(text.to_upper(), 14, UI.ACCENT, true)
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
	return c
