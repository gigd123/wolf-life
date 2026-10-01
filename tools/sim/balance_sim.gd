extends SceneTree
# 數值節奏模擬（SPEC「數值壓力調整」的快測）：三種狩獵策略的機器人在巢穴區跑 DAYS 天、各 RUNS 次，
# 統計每天結束時的飽食度、死亡數、各深度狩獵成功率、搶食次數與能力成長。
# 機器人規則：凌晨睡覺；飽食度 >110 或體力 <35 就短暫休息；其餘時間探索 → 追蹤／目擊 → 狩獵，
# 每個階段選成功率最高的選項；遇到灰熊與陌生灰狼線索就避開；灰熊搶食時叼走一部分、狐狸就驅趕。
# 用法：bash tools/run_sim.sh balance_sim [DAYS] [RUNS]
#
# 注意：這些腳本用 -s 單獨執行，不能直接引用 HuntSystem 等 class_name（autoload 還沒載入時會編譯失敗），
# 所以狩獵階段用數字：DONE = 5，結果 SUCCESS = 1。

const STAGE_DONE := 5
const RESULT_SUCCESS := 1
const POLICIES := ["small_only", "all_prey", "deer_focus"]

var GS
var GT
var scav := {}
var depth_stats := {}

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	GS = root.get_node("GameState"); GT = root.get_node("GameTime")
	var days := _env_int("DAYS", 5)
	var runs := _env_int("RUNS", 100)
	print("== balance_sim：%d 天 × %d 次" % [days, runs])
	for policy in POLICIES:
		var hunger_by_day := []
		hunger_by_day.resize(days + 1); hunger_by_day.fill(0.0)
		var alive_by_day := []
		alive_by_day.resize(days + 1); alive_by_day.fill(0)
		var kills := {}
		var deaths := 0; var hunts := 0; var idle_turns := 0; var hv_end := 0.0; var free_days := 0
		for r in runs:
			GS.new_game("forest_east")
			for d in range(days):
				if not GS.wolf.alive: break
				var res := _play_day(policy)
				hunts += res[0]; idle_turns += res[1]
				for k in res[2].keys(): kills[k] = kills.get(k, 0) + res[2][k]
				if GS.wolf.alive:
					hunger_by_day[d + 1] += GS.wolf.hunger
					alive_by_day[d + 1] += 1
					if GS.wolf.hunger >= 60: free_days += 1
			if not GS.wolf.alive: deaths += 1
			else: hv_end += GS.wolf.health_value
		var line := ""
		for d in range(1, days + 1):
			line += " D%d:%.0f" % [d, hunger_by_day[d] / max(1, alive_by_day[d])]
		print("[%s] runs=%d deaths=%d hunts/day=%.2f kills=%s free_days(hunger>=60)/run=%.1f end_hv=%.1f" % [policy, runs, deaths, float(hunts) / (runs * days), str(kills), float(free_days) / runs, hv_end / max(1, runs - deaths)])
		print("   avg hunger at end of day:" + line)
		var ds := ""
		for k in depth_stats.keys(): ds += " %s:%d/%d=%.0f%%" % [k, depth_stats[k][1], depth_stats[k][0], 100.0 * depth_stats[k][1] / max(1, depth_stats[k][0])]
		print("   success by depth:" + ds + "  scavengers " + str(scav))
		scav.clear()
		depth_stats.clear()
		print("   last wolf: spd %.1f str %.1f skill %.1f perc %.1f" % [GS.wolf.speed, GS.wolf.strength, GS.wolf.skill, GS.wolf.perception])
	quit()
	return true

# 回傳 [狩獵次數, 休息回合, 獵到的動物]
func _play_day(policy: String) -> Array:
	var start_day: int = GT.day
	var hunts := 0; var rest := 0; var got := {}
	var guard := 0
	while GS.wolf.alive and GT.day == start_day and guard < 60:
		guard += 1
		var p: String = GT.current_period()
		if p == "predawn":
			GS.action_sleep(); continue
		# 吃太撐或飽食度夠高就休息（模擬玩家把空閒拿去休息）
		if GS.wolf.hunger > 110 or GS.wolf.stamina < 35:
			GS.action_short_rest(); rest += 2; continue
		var d: Dictionary = GS.action_explore()
		if d.get("kind", "") != "clue": continue
		if d["source_kind"] == "threat":
			GS.action_avoid(); continue
		if d["source_kind"] == "gather":
			GS.action_gather_discovered(); continue
		var animal: String = d["source"]
		if policy == "small_only" and animal == "white_tailed_deer": GS.clear_discovery(); continue
		if policy == "deer_focus" and animal != "white_tailed_deer" and GS.wolf.hunger > 40: GS.clear_discovery(); continue
		var h = null
		if d["clue"] == "sight":
			h = GS.action_hunt_sighted()
		elif d["fresh"] or not d["fresh_known"]:
			var tr_res: Dictionary = GS.action_track()
			if not tr_res.get("success", false): continue
			h = tr_res["hunt"]
		else:
			GS.clear_discovery(); continue
		hunts += 1
		var guard2 := 0
		while h.stage != STAGE_DONE and GS.wolf.alive and guard2 < 20:
			guard2 += 1
			var best: Dictionary = {}
			for opt in h.options():
				if not opt.has("chance"): continue
				if best.is_empty() or float(opt["chance"]) > float(best["chance"]): best = opt
			var sr: Dictionary = h.choose(best["id"])
			GS.spend_hunt_turns(int(sr.get("turns", 0)))
			var depth_key: String = h.depth
			depth_stats[depth_key] = depth_stats.get(depth_key, [0, 0])
		if h.stage == STAGE_DONE:
			depth_stats[h.depth][0] += 1
			if h.result == RESULT_SUCCESS: depth_stats[h.depth][1] += 1
		if h.result == RESULT_SUCCESS:
			got[animal] = got.get(animal, 0) + 1
		GS.finish_hunt(h)
		while GS.is_feeding() and GS.wolf.alive:
			var fr: Dictionary = GS.feed_once()
			var fev: String = fr.get("event", "")
			if fev != "":
				scav[fev] = scav.get(fev, 0) + 1
				GS.resolve_scavenger(fev, "grab" if fev == "bear" else "drive")
		GS.wolf.clamp_stats()
	return [hunts, rest, got]
