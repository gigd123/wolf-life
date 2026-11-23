extends SceneTree
# 誰蓋了你的記號（2026-11-23 試玩回報：岩壁峽谷的記號被山地的鄰群蓋過，卡片卻寫「是那隻黑狼」，循著氣味找到的是森林南部的黑狼，
# 趕走後又寫「森林南部原本是牠的地盤」）。overmarked 記下是誰：那隻黑狼、黑狼一家、鄰群；卡片的文字與「循著氣味去找」照實際的對象。
# 用法：bash tools/run_sim.sh overmark_who_rules
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.life_log["stranger_observed"] = true
	var np = null
	for p in gs.neighbor_packs:
		if not p.off_map and not p.regions.is_empty():
			np = p
			break
	_ok(np != null, "有一般鄰群")
	if np == null:
		print("誰蓋了記號的規則：失敗 %d 個" % fails)
		return true
	var r: String = str(np.regions[0])
	gs.current_region = r
	gs.life_log["marks"] = {r: int(gs.life_log.get("days_lived", 1))}
	# 鄰群蓋的
	gs.life_log["overmarked"] = {r: np.id}
	_ok(gs.is_overmarked(), "鄰群蓋過：算被蓋過")
	_ok(gs.overmarked_by() == np.id, "記下是哪一群（%s）" % gs.overmarked_by())
	var res: Dictionary = gs.seek_stranger_from_mark()
	_ok(res.has("event") and str(res["event"].get("type", "")) == "pack_meet" and str(res["event"].get("pack", "")) == np.id, "循著氣味找到的是那一群（%s）" % str(res))
	# 那隻黑狼蓋的
	gs.life_log["overmarked"] = {r: "stranger"}
	res = gs.seek_stranger_from_mark()
	_ok(res.has("combat") or res.has("discovery"), "黑狼蓋的：照舊是和牠對上或牠的足跡")
	# 舊存檔的 true 當成那隻黑狼
	gs.life_log["overmarked"] = {r: true}
	_ok(gs.overmarked_by() == "stranger", "舊存檔的 true 當成那隻黑狼")
	gs.life_log["overmarked"] = {}
	_ok(not gs.is_overmarked(), "沒被蓋過")
	# 每天的試探只寫自己的 id
	gs.life_log["overmarked"] = {}
	for i in 200:
		gs._probe_by(np)
	var v = gs.life_log.get("overmarked", {}).get(r, "")
	_ok(str(v) == np.id, "鄰群每天試探時記下自己的 id（%s）" % str(v))
	print("誰蓋了記號的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
