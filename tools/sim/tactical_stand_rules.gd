extends SceneTree
# Phase 2f 第 1 步「站定」的回歸測試（SPEC「Phase 2f：會站定的大型獵物」）：
#   1. 會站定的物種察覺你時照體況站定；沒有站定設定的（白尾鹿）照舊逃
#   2. 站定時每回合最多轉 45°
#   3. 你在正面 2 格內：會衝撞（受傷）
#   4. 你退到夠遠兩回合：牠走開，這一場結束（放棄）
#   5. 站定時撲咬、咬住後有「牠站定面對你」的減成；健康的比虛弱的減得多
#   6. 站定的獵物可能改成逃跑（虛弱的比較常）
# 用法：bash tools/run_sim.sh tactical_stand_rules
var f := 0
var fails := 0
const TH := preload("res://scripts/core/TacticalHunt.gd")
const WOLF := {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	# 1. 站定機率
	var stood := {"healthy": 0, "weak": 0}
	for cond in stood.keys():
		for i in 400:
			var h = _new("elk_bull", cond, i)
			h._start_flee("noise")
			if h.deer_state == "stand":
				stood[cond] += 1
	_check(stood["healthy"] > 160 and stood["healthy"] < 240 and stood["weak"] < 70, "公馬鹿站定：健康約五成、虛弱約一成（%s／400）" % stood)
	var wt = _new("deer", "healthy", 1)
	wt._start_flee("noise")
	_check(wt.deer_state == "flee", "白尾鹿照舊逃")
	var autumn := 0
	for i in 400:
		var h = _new("elk_bull", "healthy", i, "autumn")
		h._start_flee("noise")
		if h.deer_state == "stand":
			autumn += 1
	_check(autumn < stood["healthy"] * 0.75, "秋季繁殖期比較少站定（%d vs %d）" % [autumn, stood["healthy"]])
	# 2. 轉身最多 45°
	var h = _stand_at("healthy", 3)
	h.deer_facing = Vector2i(1, 0)
	h.wolf_pos = h.deer_pos + Vector2i(-4, 0) # 狼在正後方
	h._turn_toward_wolf()
	_check(h.deer_facing in [Vector2i(1, 1), Vector2i(1, -1)], "轉身一回合只轉 45°（%s）" % str(h.deer_facing))
	# 3. 衝撞
	var charged := 0
	for i in 200:
		h = _stand_at("healthy", i)
		h.wolf_pos = h.deer_pos + h.deer_facing * 2
		var hp0: float = float(h.wolf["health"])
		h.herd[h.di]["stand"] = true
		h.t["species"]["elk_bull"]["stand"]["break"]["healthy"] = 0.0
		h._deer_stand()
		if float(h.wolf["health"]) < hp0:
			charged += 1
	_check(charged > 20, "正面 2 格內會衝撞（%d／200）" % charged)
	# 4. 退到夠遠：牠走開
	h = _stand_at("healthy", 7)
	h.t["species"]["elk_bull"]["stand"]["break"]["healthy"] = 0.0
	h.wolf_pos = h.deer_pos + Vector2i(-9, 0)
	h.herd[h.di]["last_wolf_dist"] = 9.0
	h._deer_stand()
	h._deer_stand()
	_check(h.done and h.result == "gave_up", "退到夠遠兩回合：牠走開、這一場結束（%s）" % h.result)
	# 5. 站定的減成
	var hh = _stand_at("healthy", 11)
	var hw = _stand_at("weak", 11)
	for x in [hh, hw]:
		x.condition_known = true
		x.wolf_pos = x.deer_pos - x.deer_facing # 正後方
	var ph: Dictionary = hh.pounce_chance()
	var pw: Dictionary = hw.pounce_chance()
	_check(ph["factors"].any(func(fa): return str(fa[0]) == "牠站定面對你"), "撲咬因素有「牠站定面對你」")
	_check(float(ph["chance"]) + 0.2 < float(pw["chance"]), "健康的站定比虛弱的難撲很多（%.2f vs %.2f）" % [ph["chance"], pw["chance"]])
	# 6. 改成逃跑
	var bolt := {"healthy": 0, "weak": 0}
	for cond in bolt.keys():
		for i in 300:
			h = _stand_at(cond, i)
			h.wolf_pos = h.deer_pos + h.deer_facing * 5
			h.herd[h.di]["last_wolf_dist"] = 5.0
			h._deer_stand()
			if h.deer_state == "flee":
				bolt[cond] += 1
	_check(bolt["weak"] > bolt["healthy"] * 2, "虛弱的比較常改成逃跑（%s／300）" % bolt)
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _new(species: String, cond: String, seed: int, season: String = "spring"):
	var h = TH.new()
	h.setup_from_game({"family": "open", "seed": seed * 31 + 5, "condition": cond, "wolf": WOLF, "wind_relation": "headwind", "species": species, "season": season})
	h.t = h.t.duplicate(true)
	return h

# 一隻已經站定的公馬鹿
func _stand_at(cond: String, seed: int):
	var h = _new("elk_bull", cond, seed)
	h.deer_state = "stand"
	h.herd[h.di]["stand_rounds"] = 0
	h.herd[h.di]["far_rounds"] = 0
	return h

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
