extends SceneTree
# Phase 2i 第 5～7 步（所有狩獵改成戰術場景）的回歸測試：
# 第 5 步：
#   1. 受傷的個體走戰術地圖（所有物種）；目標帶 injured，傷數照 injured_wounds_by（馴鹿 0、其他 1）
#   2. 受傷的獵物逃得比較慢：每回合的逃跑格數 × injured_speed_mult（叉角羚 0.75）
#   3. 受傷的旱獺、大角羊離避難處遠（injured_refuge_far）
#   4. 獵物靠近：走戰術地圖；你在目標 3～4 格、牠還沒察覺；幼鹿單獨
# 用法：bash tools/run_sim.sh all_tactical_rules
var f := 0
var gs
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	# 1. 受傷的個體
	var all_ok := true
	var wounds_ok := true
	for a in ["white_tailed_deer", "elk", "mule_deer", "caribou", "moose", "bison", "pronghorn", "bighorn_sheep", "beaver", "hare", "snowshoe_hare", "marmot"]:
		var h = gs.start_hunt(a, "adult", -1, false, "", true)
		if not gs.tactical_eligible(h):
			all_ok = false
			print("    不走戰術地圖：", a)
			continue
		var th = gs.start_tactical(h)
		if not bool(th.herd[th.target].get("injured", false)) or th.herd.size() != 1:
			all_ok = false
		var want: int = 0 if a == "caribou" else 1
		if int(th.herd[th.target]["wounds"]) != want:
			wounds_ok = false
			print("    傷數不對：%s %d" % [a, int(th.herd[th.target]["wounds"])])
	_check(all_ok, "受傷的個體：所有物種走戰術地圖、單隻、帶 injured")
	_check(wounds_ok, "受傷的個體：傷數照 injured_wounds_by（馴鹿 0、其他 1）")
	# 2. 逃得比較慢
	var hs = gs.start_hunt("pronghorn", "adult", -1, false, "prairie", false)
	var ths = gs.start_tactical(hs)
	var hi = gs.start_hunt("pronghorn", "adult", -1, false, "prairie", true)
	var thi = gs.start_tactical(hi)
	thi.herd[thi.target]["condition"] = ths.herd[ths.target]["condition"]
	thi.herd[thi.target]["wounds"] = 0
	var b0: float = ths._flee_budget(ths.target)
	var b1: float = thi._flee_budget(thi.target)
	_check(absf(b1 - maxf(1.0, b0 * 0.75)) < 0.01, "受傷的叉角羚每回合逃跑格數 × 0.75（%.2f → %.2f）" % [b0, b1])
	# 3. 離避難處遠
	var far_ok := true
	for i in 30:
		var hm = gs.start_hunt("marmot", "adult", -1, false, "scree", true)
		hm.refuge_near = true
		var thm = gs.start_tactical(hm)
		if thm.dist(thm.deer_pos, thm._open_hole(thm.deer_pos)) < 3.5:
			far_ok = false
	_check(far_ok, "受傷的旱獺離洞口遠（擲到近也一樣）")
	# 4. 獵物靠近
	var near_ok := true
	var dists: Array = []
	for ev in [{"animal_id": "snowshoe_hare", "life_stage": "adult"}, {"animal_id": "white_tailed_deer", "life_stage": "juvenile"}, {"animal_id": "caribou", "life_stage": "juvenile"}]:
		for i in 10:
			var hn = gs.hunt_nearby_prey({"animal_id": ev["animal_id"], "life_stage": ev["life_stage"], "terrain": ""})
			if not gs.tactical_eligible(hn):
				near_ok = false
				continue
			var thn = gs.start_tactical(hn)
			var d: float = thn.dist(thn.wolf_pos, thn.herd[thn.target]["pos"])
			dists.append(snappedf(d, 0.1))
			if d < 2.9 or d > 4.6 or str(thn.herd[thn.target]["state"]) != "unaware" or thn.herd.size() != 1:
				near_ok = false
	_check(near_ok, "獵物靠近：走戰術地圖、你在 3～4 格、牠還沒察覺、幼鹿單獨（距離 %s～%s）" % [dists.min(), dists.max()])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
