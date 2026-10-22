extends SceneTree
## Loads the exported CS2 models the way the game does and prints what was found:
##   godot --headless --path . --script res://tests/test_agents.gd

const Agents = preload("res://scripts/agents.gd")


func _initialize() -> void:
	var agents := Agents.new()
	agents.load_all()
	agents.is_loaded = true
	print("Laddningstid: %d ms" % agents.load_ms)
	for team in [Agents.T, Agents.CT]:
		for agent: Dictionary in agents.agents[team]:
			var mesh: ArrayMesh = agent["head_mesh"]
			print("%s %s: huvud %d ytor, mitt %s, radie %.3f, halv längd %.3f, i head_0-rum %s" % [
				"T " if team == Agents.T else "CT", agent["name"], mesh.get_surface_count(), str(agent["head_centre"]),
				agent["head_radius"], agent["head_half"], str(agent["head_local"])])
	print("Vapen: ", ", ".join(PackedStringArray(agents.weapons.keys())))
	print("OK" if agents.available() else "Inga modeller")
	agents.unload()
	agents.free()
	quit()
