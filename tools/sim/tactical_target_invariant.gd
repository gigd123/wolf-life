extends SceneTree
# 戰術狩獵的不變條件（2026-11-19 試玩回報：盯上的那一隻已經離場，狩獵沒結束、地圖上還畫著、還能撲咬）：
# 五種鹿群 × 300 場本能，每一步之後檢查「沒結束時盯上的那一隻還在場上」。印出 {} 才是通過。
# 用法：bash tools/run_sim.sh tactical_target_invariant
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var wolf := {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}
	var bad := {}
	var shown := 0
	for sp in [["bighorn_sheep", "cliff"], ["deer", "edge"], ["elk", "edge"], ["mule_deer", "slope"], ["caribou", "tundra"]]:
		for i in 300:
			var h = TH.new()
			var ctx := {"family": sp[1], "seed": i * 977 + 3, "wolf": wolf, "wind_relation": ["headwind", "crosswind", "tailwind"][i % 3], "herd": {"conditions": ["average", "healthy", "weak"], "calves": 1}, "fawn": i % 2 == 0}
			if sp[0] != "deer":
				ctx["species"] = sp[0]
			h.setup_from_game(ctx)
			if i % 2 == 0:
				for k in h.herd.size():
					if h.is_fawn(k):
						h.set_target(k)
			var guard := 0
			while not h.done and guard < 80:
				guard += 1
				var p: String = ["stalk", "chase"][i % 2]
				var tg0: int = h.target
				var held0: bool = h.held
				var pend0: bool = h.track_pending
				var ev0: int = h.events.size()
				TacticalInstinct.step(h, p)
				if not h.done and bool(h.herd[h.target]["gone"]):
					var key: String = "%s target gone held0=%s pend0=%s tracked=%s tr=%s sameT=%s" % [sp[0], str(held0), str(pend0), str(h.tracked), h.track_result, str(tg0 == h.target)]
					bad[key] = int(bad.get(key, 0)) + 1
					if shown < 3:
						shown += 1
						print(key, " new events: ", h.events.slice(ev0))
	print(bad)
	return true
