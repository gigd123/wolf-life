extends SceneTree
# 季節卡片的翻譯鍵（試玩回報 8）：卡片的字是組合出來的鍵（year.hint.<季節>.<徵兆>），check_keys.py 抓不到。
# 四張地圖 × 成年／老年 × 四季各產生一張卡片，檢查每一行的鍵都有翻譯。用法：bash tools/run_sim.sh season_card_keys
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var bad := 0
	for den in ["forest_east", "tundra_south", "mountain_canyon", "grassland_hills"]:
		for st in ["adult", "elder"]:
			gs.new_game(den)
			gs.debug_force_transition(st)
			for si in 4:
				gt.season_index = si
				gs.pending_events.clear()
				gs._queue_season_card()
				for e in gs.pending_events:
					for l in e.get("lines", []):
						var k := str(l["key"])
						if tr(k) == k:
							bad += 1
							print("RAW ", den, " ", st, " ", si, " ", k)
	print("季節卡片：原始鍵 %d 個" % bad)
	return true
