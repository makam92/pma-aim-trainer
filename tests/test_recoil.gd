extends SceneTree
## Prints the AK's spray when nobody pulls down: where each of 30 bullets lands, in degrees from
## where you aim (up, right), and checks the pattern's known shape: straight up for about ten
## bullets, then off to the left, then back to the right.
##   godot --headless --path . --script res://tests/test_recoil.gd

const AK = preload("res://scripts/weapon_ak.gd")


func _initialize() -> void:
	var ak = AK.new()
	ak.reset(0.0)
	var t := 0.0
	var points: Array[Vector2] = []
	for i in 30:
		var shot: Dictionary = ak.fire(t)
		var punch: Vector2 = shot["punch"]
		points.append(Vector2(-punch.y, punch.x))   # right, up
		t += AK.CYCLE
	var line := ""
	for i in points.size():
		line += "%d:(%.2f, %.2f) " % [i + 1, points[i].x, points[i].y]
	print(line)
	var table := AK.recoil_table()
	var angles := ""
	for i in 12:
		angles += "%.1f/%.1f " % [table[i][0], table[i][1]]
	print("tabell (vinkel/styrka): ", angles)
	var top := points[9]
	var leftmost: Vector2 = points.slice(9, 18).reduce(func(a: Vector2, b: Vector2) -> Vector2: return a if a.x < b.x else b)
	var rightmost: Vector2 = points.slice(18, 28).reduce(func(a: Vector2, b: Vector2) -> Vector2: return a if a.x > b.x else b)
	var straight := points.slice(0, 9).all(func(p: Vector2) -> bool: return absf(p.x) < 2.0)
	print("skott 10: %s, längst till vänster 10-18: %s, längst till höger 19-28: %s" % [str(top), str(leftmost), str(rightmost)])
	var ok := straight and top.y > 8.0 and top.y < 11.0 and leftmost.x < -3.0 and rightmost.x > 1.5
	print("OK" if ok else "FEL: mönstret har inte AK:ns form")
	quit(0 if ok else 1)
