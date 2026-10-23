class_name RanchEncounter
extends RefCounted

# 牧場的人類遭遇（Phase 4a 第 4 步，SPEC「人類遭遇」）：只有規則，畫面在 Game.gd、結算（扣血、重傷、注意、死亡）在 GameState。
# kind：
#   patrol 巡查（注意 40 以上）：騎馬的人。趴下躲（遮蔽＋感知）、往林子或岩地退（遮蔽＋速度）、往開闊地跑（速度，一定被看到）。
#          失敗：可能被開槍打傷（不會死）、被看到。
#   hunt   追獵（注意 70 以上、先有預警）：人與獵犬沿著氣味追。同上三種，但獵犬比較會找到你；失敗就被狗追上 →
#          簡化的搏鬥（咬退一隻／掙脫逃跑），每回合狗會咬、騎馬的人越來越近，到了就開槍；這一層可能被打死。
#   eating 在牧場吃到一半，巡查的人過來：趴低不動（遮蔽＋感知）／叼一段跑（一定成功，被看到）／丟下獵物離開。
# 危險不是一個門檻決定的：速度、遮蔽、體力、感知、力量、血量都影響（SPEC：沒有「到了 70 就死」的規則）。
# 數值在 data/ranch.json encounters。

var kind: String = ""
var cfg: Dictionary = {}
var rng := RandomNumberGenerator.new()
var stats: Dictionary = {} # speed, strength, perception, stamina, health, health_max（開始時的實際能力）
var cover: float = 0.3 # 這裡的遮蔽 0～1（地形）
var stage: String = "escape" # escape → dogs → done
var dogs: int = 0
var rider_in: int = 0 # 騎馬的人還要幾回合趕到（追獵）
var done: bool = false
var result: String = "" # hidden／escaped／shot／repelled／killed（只在 hunt）／continue／grabbed／dropped
var damage: float = 0.0 # 這一場累計的傷
var shots: Array = [] # 每一槍的傷
var bites: int = 0
var seen: bool = false # 被看到（注意 + seen）
var lethal: bool = false # 這一場可能致死（追獵）
var events: Array = [] # 這一回合發生的事（文字鍵與參數）：[{key, n}]
var rounds: int = 0

func setup(p_kind: String, p_cfg: Dictionary, p_stats: Dictionary, p_cover: float, seed: int) -> void:
	kind = p_kind
	cfg = p_cfg
	stats = p_stats.duplicate()
	cover = clamp(p_cover, 0.0, 1.0)
	rng.seed = seed
	lethal = kind == "hunt"
	if kind == "hunt":
		var h: Dictionary = cfg.get("hunt", {})
		var d: Array = h.get("dogs", [2, 4])
		dogs = rng.randi_range(int(d[0]), int(d[1]))
		rider_in = int(h.get("rider_rounds", 3))

func _c(key: String) -> Dictionary:
	return cfg.get(key, {})

func _stat(k: String) -> float:
	return float(stats.get(k, 50.0))

# 目前能選的：[{id, chance}]
func options() -> Array:
	if done:
		return []
	var out: Array = []
	match stage:
		"escape":
			for id in ["hide", "retreat", "run"]:
				if kind == "eating" and id != "hide":
					continue
				out.append({"id": id, "chance": escape_chance(id)})
			if kind == "eating":
				out.append({"id": "grab", "chance": 1.0})
				out.append({"id": "drop", "chance": 1.0})
		"dogs":
			out.append({"id": "fight_dog", "chance": dog_chance("fight_dog")})
			out.append({"id": "break_free", "chance": dog_chance("break_free")})
	return out

func escape_chance(id: String) -> float:
	var o: Dictionary = _c("escape").get(id, {})
	var v: float = float(o.get("base", 0.3)) + cover * float(o.get("cover", 0.0)) \
		+ (_stat("speed") - 50.0) * float(o.get("speed", 0.0)) + (_stat("perception") - 50.0) * float(o.get("perception", 0.0))
	if kind == "hunt":
		v -= float(_c("hunt").get("dog_penalty", {}).get(id, 0.0))
	return clamp(v, 0.05, 0.95)

func dog_chance(id: String) -> float:
	var o: Dictionary = _c("dogs").get(id, {})
	var v: float = float(o.get("base", 0.3)) + (_stat("strength") - 50.0) * float(o.get("strength", 0.0)) \
		+ (_stat("speed") - 50.0) * float(o.get("speed", 0.0)) + (_stat("stamina") / 100.0 - 0.5) * float(o.get("stamina", 0.0)) \
		+ (_stat("health") / maxf(1.0, _stat("health_max")) - 0.5) * float(o.get("health", 0.0)) - float(o.get("per_dog", 0.0)) * maxi(0, dogs - 1)
	return clamp(v, 0.05, 0.95)

func choose(id: String) -> void:
	if done:
		return
	events = []
	rounds += 1
	match stage:
		"escape":
			_choose_escape(id)
		"dogs":
			_choose_dogs(id)

func _choose_escape(id: String) -> void:
	if kind == "eating" and id == "grab":
		seen = true
		_end("grabbed")
		return
	if kind == "eating" and id == "drop":
		_end("dropped")
		return
	var ok: bool = rng.randf() < escape_chance(id)
	if id == "run":
		seen = true # 往開闊地跑：一定被看到
	if ok:
		events.append({"key": "%s.%s.ok" % [kind, id]})
		_end("continue" if kind == "eating" else ("hidden" if id == "hide" and not seen else "escaped"))
		return
	seen = true
	if kind == "hunt":
		# 獵犬追上了：簡化的搏鬥
		stage = "dogs"
		events.append({"key": "hunt.%s.caught" % id, "n": dogs})
		_rider_tick()
		if _dead():
			_end("killed")
		return
	# 巡查、吃到一半：可能被開槍打傷（不會死）
	events.append({"key": "%s.%s.fail" % [kind, id]})
	if rng.randf() < float(_c("patrol").get("shot_chance", {}).get(id, 0.6)):
		_shoot(_c("patrol").get("damage", [10, 30]), false)
		_end("shot")
	else:
		events.append({"key": "patrol.missed"})
		_end("escaped")

func _choose_dogs(id: String) -> void:
	var ok: bool = rng.randf() < dog_chance(id)
	if id == "fight_dog" and ok:
		dogs -= 1
		events.append({"key": "hunt.dog.repelled", "n": dogs})
		if dogs <= 0:
			events.append({"key": "hunt.dogs.gone"})
			_end("repelled")
			return
	elif id == "break_free" and ok:
		events.append({"key": "hunt.dog.broke_free"})
		_end("escaped")
		return
	else:
		events.append({"key": "hunt.dog.%s.fail" % id})
	# 還被狗纏著：每隻狗可能咬一口；騎馬的人越來越近
	var b: Dictionary = _c("dogs").get("bite", {})
	for i in dogs:
		if rng.randf() < float(b.get("chance", 0.35)):
			var r: Array = b.get("damage", [3, 8])
			var dmg: int = rng.randi_range(int(r[0]), int(r[1]))
			damage += dmg
			bites += 1
			events.append({"key": "hunt.dog.bite", "n": dmg})
	_rider_tick()
	if _dead():
		_end("killed")

func _rider_tick() -> void:
	rider_in -= 1
	if rider_in > 0:
		events.append({"key": "hunt.rider.near" if rider_in == 1 else "hunt.rider.coming"})
		return
	var h: Dictionary = _c("hunt")
	if rider_in == 0:
		events.append({"key": "hunt.rider.arrived"})
	if rng.randf() < float(h.get("shot_chance", 0.4)) * (1.0 - cover * float(h.get("cover_shot", 0.5))):
		_shoot(h.get("damage", [25, 45]), true)
	else:
		events.append({"key": "hunt.shot.miss"})

func _shoot(r: Array, can_kill: bool) -> void:
	var dmg: int = rng.randi_range(int(r[0]), int(r[1]))
	if not can_kill:
		dmg = mini(dmg, int(maxf(0.0, _stat("health") - damage - 1.0)))
	damage += dmg
	shots.append(dmg)
	events.append({"key": "shot.hit", "n": dmg})

func _dead() -> bool:
	return lethal and _stat("health") - damage <= 0.0

func _end(r: String) -> void:
	result = r
	done = true
	stage = "done"
