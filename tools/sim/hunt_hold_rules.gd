extends SceneTree
# Phase 2o 第 2 步：咬住後的招式各有用途。
# 咬後腿成功：之後每回合少跑 hamstring.slow 格、咬住時比較甩不開、壓倒更容易；健康的大型獵物比較難直接壓倒；
# 咬喉在累的、受傷的獵物身上加成更大、健康的比較難；死咬拖住那一回合比較不會被踢、會回一點喘、牠掙扎得更多。
# 用法：bash tools/run_sim.sh hunt_hold_rules
var f := 0
var fails := 0
const WOLF := {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _held(TH, species: String, cond: String, seed: int = 3):
	var h = TH.new()
	var ctx := {"family": "edge", "seed": seed, "condition": cond, "wolf": WOLF, "wind_relation": "crosswind"}
	if species != "deer":
		ctx["species"] = species
	h.setup_from_game(ctx)
	h.held = true
	h.hold_side = "rear"
	h.deer_state = "flee"
	h.flee_round = 2
	return h

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var hc: Dictionary = TH.new().t["hold"]
	# 咬後腿：逃跑格數、掙脫、壓倒
	var h = _held(TH, "deer", "average")
	var flee0: float = h._flee_budget()
	var brk0: float = h.break_chance()
	var td0: float = float(h.hold_options()["takedown"]["chance"])
	h.herd[h.di]["hamstrung"] = 1
	h.wounds += int(hc["hamstring"]["slow"])
	_ok(h._flee_budget() <= flee0 - 2.0 or h._flee_budget() <= 1.0, "咬傷後腿：逃跑少 2 格（%.1f → %.1f）" % [flee0, h._flee_budget()])
	_ok(h.break_chance() < brk0 - 0.05, "咬傷後腿：比較甩不開（%.2f → %.2f）" % [brk0, h.break_chance()])
	_ok(float(h.hold_options()["takedown"]["chance"]) >= td0 + 0.3, "咬傷後腿：壓倒 +0.3 以上（%.2f → %.2f）" % [td0, float(h.hold_options()["takedown"]["chance"])])
	# 健康的大型獵物比較難直接壓倒
	var elk_h = _held(TH, "elk", "healthy")
	var elk_a = _held(TH, "elk", "average")
	_ok(elk_h._large_healthy() and not elk_a._large_healthy(), "健康的母馬鹿算健康的大型獵物、普通的不算")
	var deer_h = _held(TH, "deer", "healthy")
	_ok(not deer_h._large_healthy(), "健康的白尾鹿母鹿不算大型")
	var has_factor := false
	for fc in elk_h.hold_options()["takedown"]["factors"]:
		if str(fc[0]) == elk_h._tx("tactical.factor.large_healthy"):
			has_factor = true
	_ok(has_factor, "健康的大型獵物：壓倒的因素寫出「又大又壯」")
	# 咬喉：累的時候加成比壓倒多
	var hf = _held(TH, "deer", "average")
	hf.flee_round = 2
	var t0: float = float(hf.hold_options()["throat"]["chance"])
	var d0: float = float(hf.hold_options()["takedown"]["chance"])
	hf.flee_round = 12
	var t1: float = float(hf.hold_options()["throat"]["chance"])
	var d1: float = float(hf.hold_options()["takedown"]["chance"])
	_ok(t1 - t0 > (d1 - d0) * 1.5, "牠累了：咬喉的加成比壓倒大（咬喉 +%.2f、壓倒 +%.2f）" % [t1 - t0, d1 - d0])
	var th_h: float = float(_held(TH, "deer", "healthy").hold_options()["throat"]["chance"])
	var th_w: float = float(_held(TH, "deer", "weak").hold_options()["throat"]["chance"])
	_ok(th_w - th_h >= 0.15, "健康的比較難咬喉（健康 %.2f、虛弱 %.2f）" % [th_h, th_w])
	# 死咬拖住：回喘、比較不會被踢、牠掙扎更多
	var hb = _held(TH, "deer", "average")
	hb.breath = 10.0
	var s0: int = int(hb.herd[hb.di].get("struggle", 0))
	hb.hold_action("hang")
	_ok(hb.done or not hb.held or hb.breath > 10.0, "死咬拖住回一點喘（10 → %.1f）" % hb.breath)
	_ok(hb.done or int(hb.herd[hb.di].get("struggle", 0)) - s0 >= 2, "死咬拖住：牠掙扎得更多（+%d）" % (int(hb.herd[hb.di].get("struggle", 0)) - s0))
	var kick_hang := 0
	var kick_plain := 0
	for i in 400:
		var a = _held(TH, "deer", "average", 100 + i)
		a.herd[a.di]["struggle"] = 0
		var k0: int = a.kicks
		a._deer_struggle(false, true)
		kick_hang += a.kicks - k0
		var b = _held(TH, "deer", "average", 100 + i)
		var k1: int = b.kicks
		b._deer_struggle(false, false)
		kick_plain += b.kicks - k1
	_ok(kick_hang < kick_plain * 0.6, "死咬拖住那一回合比較不會被踢（400 次：拖住 %d、一般 %d）" % [kick_hang, kick_plain])
	# 本能：健康的大型獵物先咬後腿；喘不夠壓倒時不鬆口
	var ei = _held(TH, "elk", "healthy")
	ei.breath = ei.breath_max
	var hams0: int = int(ei.herd[ei.di].get("hamstrung", 0))
	var b0: int = int(ei.stats.get("released", 0))
	var r0: int = ei.rounds
	TacticalInstinct.step(ei, "stalk")
	_ok(ei.rounds > r0 and int(ei.stats.get("released", 0)) == b0, "本能對健康的母馬鹿出了一招、沒有鬆口")
	var lo = _held(TH, "deer", "average")
	lo.breath = 7.0
	var rel0: int = int(lo.stats.get("released", 0))
	TacticalInstinct.step(lo, "stalk")
	_ok(int(lo.stats.get("released", 0)) == rel0, "喘不夠壓倒：本能咬喉或拖住，不鬆口")
	print("咬住後招式的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
