extends SceneTree
# Phase 2m 第 1 步的規則檢查：目標在密林裡不見 → 停下來（track_pending）；追上（出現在密林外、看得到、帶傷與疲勞照舊）、
# 沒追上（照地形寫足跡斷在哪、結束）、放棄（不重寫「不見了」）、一場一次、花喘與遊戲回合、因素、本能的判斷、關掉時照舊。
# 用法：bash tools/run_sim.sh tactical_track_rules
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _hunt(seed: int, season: String = "summer"):
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var h = TH.new()
	h.setup_from_game({"family": "dense", "seed": seed, "condition": "average", "season": season,
		"wolf": {"speed": 66, "skill": 71, "strength": 77, "perception": 62, "stamina": 80, "health": 110, "health_max": 110}})
	return h

# 把目標放進看不到的密林、讓 _check_lost 觸發
func _lose(h) -> bool:
	for y in h.height:
		for x in h.width:
			var c := Vector2i(x, y)
			if h.terrain(c) != "f" or h._cheb(c, h.wolf_pos) < 4:
				continue
			h.deer_pos = c
			if not h.has_sight():
				h.deer_state = "flee"
				h.lost_turns = int(h.t["deer"]["lost_sight_turns"]) - 1
				h._check_lost()
				return h.track_pending
	return false

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var found := 0
	var lost := 0
	for s in 80:
		var h = _hunt(s * 13 + 1)
		if not _lose(h):
			continue
		_ok(not h.done, "停下來時還沒結束")
		_ok(h.events.size() == 1 and str(h.events[0]).contains("不見了"), "寫一次「不見了」")
		var tc: Dictionary = h.track_chance()
		_ok(float(tc["chance"]) >= 0.1 and float(tc["chance"]) <= 0.8, "機率夾在 10%～80%")
		h.wounds = 1
		_ok(float(h.track_chance()["chance"]) > float(tc["chance"]), "流血時機率比較高")
		var b0: float = h.breath
		var turns0: int = h.game_turns()
		h.events = []
		h.follow_track()
		_ok(not h.track_pending and h.tracked, "追過一次")
		_ok(h.breath < b0, "花喘")
		_ok(h.game_turns() >= turns0 + 1 or h.game_turns() == turns0 + 1, "遊戲回合 +1")
		if h.track_result == "found":
			found += 1
			_ok(not h.done and h.terrain(h.deer_pos) == "." and h.has_sight(), "追上：牠在密林外、看得到")
			_ok(h.wounds == 1, "追上：傷照舊")
			var d: int = h._cheb(h.deer_pos, h.wolf_pos)
			_ok(d >= 1 and d <= 5, "追上：距離 2～3 格左右（%d）" % d)
			# 第二次失去視線：真的逃掉
			_lose(h)
			_ok(not h.track_pending and h.done and h.result == "lost", "第二次不見就是逃掉")
		else:
			lost += 1
			_ok(h.done and h.result == "lost", "沒追上：結束")
			_ok(str(h.reason).contains("足跡"), "沒追上：寫足跡斷在哪（%s）" % h.reason)
	_ok(found > 0 and lost > 0, "追上與沒追上都有（%d／%d）" % [found, lost])
	# 放棄
	var g = _hunt(5)
	if _lose(g):
		g.events = []
		g.give_up_track()
		_ok(g.done and g.result == "lost" and g.events.is_empty() and g.track_result == "gave_up", "放棄：結束、不重寫")
	# 冬天的機率比較高
	var a = _hunt(7, "summer")
	var w = _hunt(7, "winter")
	if _lose(a) and _lose(w):
		_ok(float(w.track_chance()["chance"]) > float(a.track_chance()["chance"]), "冬天（雪地）的機率比較高")
	# 本能：喘不夠就放棄
	var k = _hunt(9)
	if _lose(k):
		k.breath = 1.0
		TacticalInstinct.step(k, "stalk")
		_ok(k.track_result == "gave_up", "本能：喘不夠就放棄")
	# 關掉時照舊直接逃掉
	var o = _hunt(11)
	o.t["track"]["enabled"] = false
	_ok(not _lose(o) and o.done, "關掉時照舊直接逃掉")
	print("循著足跡追的規則：追上 %d、沒追上 %d；%s" % [found, lost, "全部通過" if fails == 0 else "失敗 %d 個" % fails])
	return true
