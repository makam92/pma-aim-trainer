extends "res://scripts/modes/mode_base.gd"
## Aim Punch: duels where the enemy shoots first. A CS2 bot with an AK shows up and fires short bursts
## at you; every hit punches your aim like in CS2 (the view jumps up, your bullets go higher still,
## then it settles), and you have to find his head again and kill him before he kills you. With
## kevlar the punch is much smaller and you can take one hit more. Kills in 60 seconds.

const Dummy = preload("res://scripts/dummy.gd")
const HeadModel = preload("res://scripts/head_model.gd")
const HealthBar = preload("res://scripts/ui/health_bar.gd")

enum Phase { READY, RUN, DONE }

const FIELD_YAW := 25.0                    # enemies show up to this far to each side
const FIRST_SHOT := Vector2(0.06, 0.16)    # seconds from showing up to his first shot: he's always first
const BURST_PAUSE := Vector2(0.5, 0.8)     # seconds between his bursts
const NEXT_DUEL := Vector2(0.45, 0.8)      # seconds before the next enemy shows up
const SHOT_GAP := 0.1                      # his AK fires every 0.1 s
## His AK in your chest: 36 damage without kevlar, 27 through it (77.5 % armor penetration).
const DAMAGE := [36, 27]
## How far one hit punches your aim up, without and with kevlar (degrees; the view jumps about as
## far and bullets go twice as far). CS2 doesn't publish these, so they're estimates, much smaller
## with kevlar as in CS2.
const PUNCH := [2.0, 0.6]
const PUNCH_SIDEWAYS := 0.25               # up to this share of a punch goes left or right
## Your shots this soon after a hit count as fired under the punch.
const PUNCH_WINDOW := 0.3

var duration := 60.0
var armor := 0
var zone := "head"
var phase := Phase.READY
var kills := 0
var deaths := 0
var misses := 0
var body_hits := 0
var hits_taken := 0
var run_start := 0.0
## Per won duel: seconds from the enemy showing up to your kill, and from his first hit on you.
var kill_times: Array = []
var recover_times: Array = []
## Your shots soon after a hit (PUNCH_WINDOW), and how many of them killed.
var punched_shots := 0
var punched_kills := 0

var _dummy: Dummy = null
var _health: HealthBar
var _alive := false            # the duel with the current enemy is still on
var _hp := 100
var _distance := 0.0
var _shown_at := 0.0
var _first_hit := -1.0
var _last_hit := -INF
var _next_shot := INF
var _burst_left := 0
var _next_duel := INF
var _pb := -1


func begin() -> void:
	duration = Defs.RUN_SECONDS
	armor = Settings.punch_armor
	zone = Defs.TRACK_ZONES[Settings.punch_zone]["id"]
	var best: Variant = Stats.best("punch", Defs.variant("punch", Settings))
	if best != null:
		_pb = int(best.get("score", 0))
	_health = HealthBar.new()
	hud.add_widget(_health)
	hud.message("Fienden skjuter först: hitta tillbaka och döda honom.", UI.DIM)
	_update_hud()


## The first enemy shows up shortly after the run starts.
func go() -> void:
	phase = Phase.RUN
	run_start = now()
	_next_duel = run_start + NEXT_DUEL.x
	hud.message("")


func _process(_delta: float) -> void:
	if phase != Phase.RUN:
		return
	var t := now()
	if t - run_start >= duration:
		_complete()
		return
	if _alive:
		_dummy.face(player.eye_position())
		while _alive and t >= _next_shot:
			_enemy_shot(_next_shot)
	elif t >= _next_duel:
		_spawn_bot(t)
	_update_hud()


func shoot(origin: Vector3, dir: Vector3) -> void:
	Sfx.play("shot")
	if phase != Phase.RUN or _dummy == null:
		return
	var part: String = _dummy.hit_test(origin, dir)["part"]
	shot_hit = part != ""
	if not _alive:
		return    # he already got you; the next duel is on its way
	var t := now()
	var killed := part == "head" or (part == "body" and zone == "body")
	if t - _last_hit <= PUNCH_WINDOW:
		punched_shots += 1
		punched_kills += int(killed)
	if killed:
		_win(t, part)
	elif part == "body":
		body_hits += 1
		Sfx.play("hit")
		_dummy.flash("body")
	else:
		misses += 1
		Sfx.play("miss")
	_update_hud()


static func summary(r: Dictionary) -> Dictionary:
	var kills := int(r.get("score", 0))
	var duels := kills + int(r.get("deaths", 0))
	var shots := int(r.get("shots", 0))
	var punched := int(r.get("punched_shots", 0))
	var punched_kills := int(r.get("punched_kills", 0))
	var punched_rate := float(punched_kills) / punched if punched > 0 else 0.0
	var calm := shots - punched
	var calm_rate := float(kills - punched_kills) / calm if calm > 0 else 0.0
	var rows := [
		["Vunna dueller", "%d av %d" % [kills, duels]],
		["Tid till kill", UI.ms(r.get("kill_ms"))],
		["Efter hans första träff", UI.ms(r.get("recover_ms"))],
		["Träffsäkerhet", "%d %%" % roundi(float(r.get("accuracy", 0.0)) * 100.0)],
		["Direkt efter en träff", "%d %% dödade (%d skott)" % [roundi(punched_rate * 100.0), punched] if punched > 0 else "–"],
		["Missar", str(int(r.get("misses", 0)))],
	]
	if r.get("zone", "head") == "head":
		rows.append(["Kroppsträffar", str(int(r.get("body_hits", 0)))])
	var note := ""
	if punched >= 4 and calm >= 4 and punched_rate < calm_rate * 0.6:
		note = "Skotten direkt efter en träff missar oftare. Medan rycket släpper går kulorna högre än siktet: dra ner en aning eller vänta en tiondel innan du skjuter."
	elif duels > 0 and kills * 2 < duels:
		note = "Han hinner döda dig i mer än hälften av duellerna. Hitta huvudet först och skjut sedan, ett lugnt skott vinner oftare än tre stressade."
	elif duels > 0 and kills >= duels * 0.9:
		note = "Du vinner nästan alla dueller. " + ("Prova utan kevlar, då rycker det mer." if int(r.get("armor", 0)) == 1 \
			else "Prova längre avstånd så att huvudet blir mindre.")
	return {"headline": str(kills), "unit": "kills på 60 s", "rows": rows, "note": note}


## A new enemy at a random direction and distance. He shoots first, and his first burst never kills
## you outright, so you always get to shoot back.
func _spawn_bot(t: float) -> void:
	_clear_bot()
	_distance = Defs.random_distance(Defs.TARGET_RANGES[Settings.punch_range])
	var flat := Defs.dir_from_angles(randf_range(-FIELD_YAW, FIELD_YAW), 0.0)
	_dummy = Dummy.new()
	_dummy.team = HeadModel.T   # a T with an AK, the gun you hear
	_dummy.weapon_kind = "rifle"
	_dummy.position = Vector3(flat.x, 0.0, flat.z) * _distance
	add_child(_dummy)
	_dummy.face(player.eye_position())
	_alive = true
	_hp = 100
	_health.set_hp(_hp)
	_shown_at = t
	_first_hit = -1.0
	_next_shot = t + randf_range(FIRST_SHOT.x, FIRST_SHOT.y)
	var hits_to_die := ceili(100.0 / float(DAMAGE[armor]))
	_burst_left = randi_range(1, mini(3, hits_to_die - 1))


## He fires at time t and hits you in the chest: damage, a punch to your aim and a red flash.
func _enemy_shot(t: float) -> void:
	Sfx.play("enemy")
	Sfx.play("hurt")
	_dummy.muzzle_flash()
	var up: float = PUNCH[armor]
	main.ak.take_hit(t, Vector2(up, up * PUNCH_SIDEWAYS * randf_range(-1.0, 1.0)))
	hud.tint(UI.BAD, 0.16)
	hits_taken += 1
	if _first_hit < 0.0:
		_first_hit = t
	_last_hit = t
	_hp -= int(DAMAGE[armor])
	_health.set_hp(_hp)
	if _hp <= 0:
		deaths += 1
		hud.flash("DU DOG", UI.BAD)
		hud.tint(UI.BAD, 0.35)
		Sfx.play("fail")
		_end_duel(t)    # he stays where he is until the next one shows up
		return
	_burst_left -= 1
	if _burst_left > 0:
		_next_shot = t + SHOT_GAP
	else:
		_burst_left = randi_range(1, 3)
		_next_shot = t + randf_range(BURST_PAUSE.x, BURST_PAUSE.y)


func _win(t: float, part: String) -> void:
	kills += 1
	kill_times.append(t - _shown_at)
	if _first_hit >= 0.0:
		recover_times.append(t - _first_hit)
	Sfx.play("head" if part == "head" else "hit", 1.0 + 0.5 * minf(kills / 30.0, 1.0))
	flash_time(t - _shown_at)
	_clear_bot()
	_end_duel(t)


func _end_duel(t: float) -> void:
	_alive = false
	_next_shot = INF
	_next_duel = t + randf_range(NEXT_DUEL.x, NEXT_DUEL.y)


func _clear_bot() -> void:
	if _dummy:
		_dummy.queue_free()
	_dummy = null


func _complete() -> void:
	phase = Phase.DONE
	_alive = false
	_clear_bot()
	Sfx.play("done")
	_update_hud()
	var shots := kills + misses + body_hits
	finished.emit({
		"variant": Defs.variant("punch", Settings),
		"score": kills,
		"deaths": deaths,
		"armor": armor,
		"zone": zone,
		"shots": shots,
		"misses": misses,
		"body_hits": body_hits,
		"accuracy": float(kills) / maxi(shots, 1),
		"kill_ms": to_ms(average(kill_times)),
		"recover_ms": to_ms(average(recover_times)),
		"hits_taken": hits_taken,
		"punched_shots": punched_shots,
		"punched_kills": punched_kills,
	})


func _update_hud() -> void:
	var left := duration
	if phase == Phase.RUN:
		left = maxf(run_start + duration - now(), 0.0)
	elif phase == Phase.DONE:
		left = 0.0
	var info := "%d kills" % kills
	if _alive:
		info += "  ·  %d u" % roundi(_distance / Defs.UNIT)
	var duels := kills + deaths
	var won := 100 if duels == 0 else roundi(100.0 * kills / duels)
	var pb := "PB %d" % _pb if _pb >= 0 else "inget PB än"
	hud.set_texts("AIM PUNCH · %s" % Defs.ARMOR[armor], info, "%s s kvar · %d %% vunna · %s" % [UI.dec(left, 1), won, pb])
	hud.set_progress(1.0 - left / duration)
