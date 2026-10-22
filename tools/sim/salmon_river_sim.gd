extends SceneTree
# 鮭魚洄流的河岸模式（Phase 2h）單場模擬。第 2 步：沒有灰熊，驗證 T1——飽食度 60 吃到 120（扣掉這段時間每回合照常消耗 1.5）
# 要幾個時段：照強度（初期、高峰、衰退）× 站的淺灘（好 3、普通 2、差 1），狼走到最近的那種淺灘一直撲。
# 目標（SPEC Phase 2h）：高峰、好位置約 1 個時段；普通約 2 個時段；初期、衰退再慢一倍。
# 第 4 步：有熊（照資料），三種打法（RiverInstinct）：camp 死守最好的淺灘、far 躲最遠、adaptive 照局勢換位；
# 印 吃飽要幾個時段（60 → 120、扣掉消耗）、一天內沒吃飽的比例、每場被威嚇、被趕開的次數、吃剩的魚佔的比例。目標 T4：adaptive 明顯比另外兩種好。
# 用法：bash tools/run_sim.sh salmon_river_sim；RUNS=200；ONLY_BEARS=1 只跑有熊的
func _initialize() -> void:
	_run.call_deferred()

func _nearest(rf, q: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	for y in rf.height:
		for x in rf.width:
			var c := Vector2i(x, y)
			if rf.fish_at(c) == q and (best.x < 0 or (c - rf.wolf_pos).length() < (best - rf.wolf_pos).length()):
				best = c
	return best

func _walk_to(rf, goal: Vector2i) -> void:
	var guard := 0
	while rf.wolf_pos != goal and not rf.done and guard < 40:
		guard += 1
		var r: Dictionary = rf.reachable()
		var pick: Vector2i = rf.wolf_pos
		for c in r.keys():
			if (c - goal).length() < (pick - goal).length():
				pick = c
		if pick == rf.wolf_pos:
			break
		rf.move_to(pick)

func _run() -> void:
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 200
	var cfg: Dictionary = (root.get_node("GameData").balance["salmon"]["river"] as Dictionary).duplicate(true)
	# 第 2 步的基準：沒有熊（第 3 步之後熊照資料；有熊的打法比較在第 4 步）
	cfg["bears"]["start"] = {"early": [0, 0], "peak": [0, 0], "decline": [0, 0]}
	cfg["bears"]["arrive"] = {"early": 0.0, "peak": 0.0, "decline": 0.0}
	var RF = load("res://scripts/core/RiverFishing.gd")
	if OS.get_environment("ONLY_BEARS") != "":
		_bears(runs)
		return

	print("== 河岸（沒有熊）：飽食度 60 → 120 要幾個時段（含走過去；每格 %d 場）" % runs)
	for st in ["early", "peak", "decline"]:
		var line := "  %-8s" % st
		for q in [3, 2, 1]:
			var periods := 0.0
			var walk := 0.0
			var fails := 0
			for i in runs:
				var rf = RF.new()
				rf.setup({"stage": st, "seed": i * 7919 + q, "hunger": 60.0, "cfg": cfg})
				_walk_to(rf, _nearest(rf, q))
				walk += rf.rounds
				# 一直撲，直到吃下的扣掉這段時間的消耗 ≥ 60
				while not rf.done and rf.eaten - 1.5 * float(rf.rounds) / float(cfg["rounds_per_turn"]) < 60.0:
					if not rf.can_fish():
						break
					rf.fish_once()
				if rf.eaten - 1.5 * float(rf.rounds) / float(cfg["rounds_per_turn"]) < 60.0:
					fails += 1
				periods += float(rf.rounds) / float(cfg["rounds_per_turn"]) / 4.0
			line += "   淺灘%d %.2f 時段（走路 %.1f 回合%s）" % [q, periods / runs, walk / runs, "，%d 場沒吃飽" % fails if fails > 0 else ""]
		print(line)
	_bears(runs)
	quit()

func _bears(runs: int) -> void:
	var RF = load("res://scripts/core/RiverFishing.gd")
	var bcfg: Dictionary = (root.get_node("GameData").balance["salmon"]["river"] as Dictionary).duplicate(true)
	print("== 有熊、三種打法：吃飽（60 → 120）要幾個時段（一天內沒吃飽算到一天）／沒吃飽的比例／每場威嚇、趕開／吃剩的魚佔")
	for clue in ["", "bears"]:
		for st in ["early", "peak", "decline"]:
			if clue == "bears" and st != "peak":
				continue
			var line := "  %-8s%-6s" % [st, "多熊" if clue == "bears" else ""]
			for pol in ["camp", "far", "adaptive"]:
				var periods := 0.0
				var hungry := 0
				var warns := 0
				var pushes := 0
				var scrap_food := 0.0
				var food := 0.0
				for i in runs:
					var rf = RF.new()
					rf.setup({"stage": st, "clue": clue, "seed": i * 6151 + 3, "hunger": 60.0, "cfg": bcfg})
					var guard := 0
					while not rf.done and guard < 400:
						guard += 1
						if rf.eaten - 1.5 * float(rf.rounds) / float(bcfg["rounds_per_turn"]) >= 60.0:
							rf.leave()
							break
						RiverInstinct.step(rf, pol)
					if rf.eaten - 1.5 * float(rf.rounds) / float(bcfg["rounds_per_turn"]) < 60.0:
						hungry += 1
						periods += float(bcfg["max_rounds"]) / float(bcfg["rounds_per_turn"]) / 4.0
					else:
						periods += float(rf.rounds) / float(bcfg["rounds_per_turn"]) / 4.0
					warns += rf.warns
					pushes += rf.pushes
					scrap_food += rf.scraps * float(bcfg["bears"]["leftover_value"])
					food += rf.eaten
				line += "   %s %.2f 時段／沒吃飽 %d%%／威嚇 %.1f 趕開 %.1f／剩魚 %d%%" % [pol, periods / runs, roundi(100.0 * hungry / runs), float(warns) / runs, float(pushes) / runs, roundi(100.0 * scrap_food / max(1.0, food))]
			print(line)
	quit()
