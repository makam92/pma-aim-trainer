extends SceneTree
## Files the installer needs besides the game: icon.ico (the program's icon in Windows, made from
## icon.svg in every size Windows asks for) and Godot's license text, which goes with the game.
##   godot --headless --path . --script res://tools/installer_files.gd

const SIZES := [16, 20, 24, 32, 40, 48, 64, 128, 256]
const LICENSE_PATH := "res://build/export/GODOT-LICENSE.txt"


func _initialize() -> void:
	var svg := FileAccess.get_file_as_bytes("res://icon.svg")
	var pngs: Array[PackedByteArray] = []
	for size: int in SIZES:
		var image := Image.new()
		image.load_svg_from_buffer(svg, size / 128.0)
		pngs.append(image.save_png_to_buffer())
	# An .ico is a small directory of the images, each stored as a PNG.
	var ico := PackedByteArray()
	ico.resize(6 + 16 * SIZES.size())
	ico.encode_u16(2, 1)
	ico.encode_u16(4, SIZES.size())
	var offset := ico.size()
	for i in SIZES.size():
		var entry := 6 + 16 * i
		ico.encode_u8(entry, SIZES[i] % 256)        # 0 means 256
		ico.encode_u8(entry + 1, SIZES[i] % 256)
		ico.encode_u16(entry + 4, 1)
		ico.encode_u16(entry + 6, 32)
		ico.encode_u32(entry + 8, pngs[i].size())
		ico.encode_u32(entry + 12, offset)
		offset += pngs[i].size()
	for png in pngs:
		ico.append_array(png)
	FileAccess.open("res://icon.ico", FileAccess.WRITE).store_buffer(ico)

	DirAccess.make_dir_recursive_absolute(LICENSE_PATH.get_base_dir())
	var license := FileAccess.open(LICENSE_PATH, FileAccess.WRITE)
	license.store_string("PMA Aim Trainer är byggt med Godot Engine.\n\n" + Engine.get_license_text())
	license.close()
	print("icon.ico (%d storlekar) och GODOT-LICENSE.txt klara" % SIZES.size())
	quit()
