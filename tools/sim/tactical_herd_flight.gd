extends SceneTree
# Phase 2d 第 1 步「鹿群一起逃」的檢查：情境 G（小群 5 隻、開闊地）、H（3 隻、倒木旁）與 7 隻的大群（G 的地圖多放兩隻），
# 普通的狼，兩種打法：耐力追（跟在後面）、猛追（一直衝）。統計：
#   - 方向一致度：每回合逃跑中的鹿移動方向的平均向量長度（1 = 全部同一方向；每隻在小群方向左右 45° 內隨機挑時約 0.8）；只算還沒被衝散（同一群）的回合。
#   - 背道而馳：同一群裡有兩隻移動方向相差 90° 以上的回合比例。
#   - 掉隊：逃了 4 回合時，最慢的那一隻（幼鹿或體況最差的）在同一群裡離狼的排名（0 = 最近、在最後面）。
#   - 衝散：分成幾群、多久合回來。
# 用法：bash tools/run_sim.sh tactical_herd_flight 0 100
const TH := preload("res://scripts/core/TacticalHunt.gd")
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 100
	print("== 鹿群一起逃（每格 %d 場，普通的狼）" % runs)
	for sc in ["G", "H", "G7"]:
		for pol in ["pace", "chase"]:
			var align_sum := 0.0
			var align_n := 0
			var lag_ok := 0
			var lag_n := 0
			var lag_rank := 0.0
			var div_n := 0
			var splits := 0
			var split_sizes := {}
			var regroups := 0
			var caught := 0
			for i in runs:
				var h = TH.new()
				h.setup("G" if sc == "G7" else sc, "normal", i * 7919 + 11)
				if sc == "G7":
					for extra in [Vector2i(1, 1), Vector2i(-1, 1)]:
						var d: Dictionary = (h.herd[0] as Dictionary).duplicate(true)
						d["pos"] = h.herd[0]["pos"] + extra * 2
						d["kind"] = "adult"
						d["mother"] = -1
						d["condition"] = "healthy"
						h.herd.append(d)
				var slow := _slowest(h)
				var guard := 0
				var ev0 := 0
				while not h.done and guard < 60:
					guard += 1
					var before := {}
					for k in h.active_deer():
						before[k] = h.herd[k]["pos"]
					var groups_before: int = _groups(h)
					TacticalInstinct.step(h, pol)
					# 方向一致度：這一步前後都還是同一群、正在逃的鹿（這一步被衝散的不算）
					if groups_before <= 1 and _groups(h) <= 1:
						var sum := Vector2.ZERO
						var n := 0
						var dirs: Array = []
						for k in before.keys():
							if bool(h.herd[k]["gone"]) or str(h.herd[k]["state"]) != "flee" or bool(h.herd[k]["held"]):
								continue
							var mv := Vector2(h.herd[k]["pos"] - before[k])
							if mv.length() > 0.5:
								sum += mv.normalized()
								n += 1
								dirs.append(mv.normalized())
						if n >= 2:
							align_sum += sum.length() / n
							align_n += 1
							var diverge := false
							for a in dirs:
								for b in dirs:
									if (a as Vector2).dot(b) < -0.01:
										diverge = true
							if diverge:
								div_n += 1
					# 掉隊：最慢的那一隻逃了 3 回合時離狼最近嗎
					if slow >= 0 and not bool(h.herd[slow]["gone"]) and int(h.herd[slow]["flee_round"]) == 4 and str(h.herd[slow]["state"]) == "flee":
						lag_n += 1
						var closer := 0
						var mates := 0
						for k in h.active_deer():
							if k == slow or str(h.herd[k]["state"]) != "flee" or int(h.herd[k].get("group", 0)) != int(h.herd[slow].get("group", 0)):
								continue
							mates += 1
							if h.dist(h.herd[k]["pos"], h.wolf_pos) < h.dist(h.herd[slow]["pos"], h.wolf_pos):
								closer += 1
						if closer == 0:
							lag_ok += 1
						lag_rank += float(closer) / max(1, mates)
						slow = -1
					for e in h.events.slice(ev0):
						if str(e).contains("分成幾群"):
							splits += 1
							var g: int = _groups(h)
							split_sizes[g] = int(split_sizes.get(g, 0)) + 1
						if str(e).contains("又聚到了一起"):
							regroups += 1
					ev0 = h.events.size()
				if h.result == "caught":
					caught += 1
			print("  %-3s %-5s 方向一致度 %.2f、背道而馳 %d%%（%d 回合）；最慢的那隻在最後 %d%%、平均排名 %.2f（0 最後、1 最前；%d 場）；衝散 %d 次 %s、合回來 %d 次；獵到 %d%%" % [sc, pol,
				align_sum / max(1, align_n), roundi(100.0 * div_n / max(1, align_n)), align_n, roundi(100.0 * lag_ok / max(1, lag_n)), lag_rank / max(1, lag_n), lag_n, splits, split_sizes, regroups, roundi(100.0 * caught / runs)])
	return true

# 最慢的那一隻：幼鹿優先，其次體況最差的
func _slowest(h) -> int:
	var rank := {"weak": 0, "average": 1, "healthy": 2}
	var best := -1
	var bs := 99
	for i in h.herd.size():
		var s: int = -1 if h.is_fawn(i) else int(rank.get(str(h.herd[i]["condition"]), 2))
		if s < bs:
			bs = s
			best = i
	# 全部一樣（都健康）就不算
	var same := true
	for i in h.herd.size():
		if (-1 if h.is_fawn(i) else int(rank.get(str(h.herd[i]["condition"]), 2))) != bs:
			same = false
	return -1 if same else best

func _groups(h) -> int:
	var gs := {}
	for k in h.active_deer():
		gs[int(h.herd[k].get("group", 0))] = true
	return gs.size()
