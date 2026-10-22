extends Node
## Base for the training modes. main.gd calls the hooks; a mode emits `finished` when a run ends.

signal finished(result: Dictionary)

const Defs = preload("res://scripts/defs.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")

var main: Node
var player: Node3D
var hud: Control
## Set by shoot() when the shot hit a target, so no bullet hole goes on the wall behind it.
var shot_hit := false


func setup(host: Node) -> void:
	main = host
	player = host.player
	hud = host.hud


func begin() -> void:
	pass


func shoot(_origin: Vector3, _dir: Vector3) -> void:
	pass


func key_event(_key: String, _pressed: bool, _t: float) -> void:
	pass


func on_resume() -> void:
	pass


## Game time in seconds. It stands still while the game is paused.
func now() -> float:
	return main.game_time()


## Mean of a list of numbers, or of `key` in a list of dictionaries. Null for an empty list.
static func average(items: Array, key: String = "") -> Variant:
	if items.is_empty():
		return null
	var sum := 0.0
	for item: Variant in items:
		sum += float(item[key] if key != "" else item)
	return sum / items.size()
