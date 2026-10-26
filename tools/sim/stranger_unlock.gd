extends SceneTree
# 黑狼可以直接互動的條件（2026-10-26 使用者選 C）：
#   1. 沒觀察過、只被牠趕過：之後算見過牠（原本永遠是「被驅趕」，成年了也不會變成可以對峙）
#   2. 被趕過、這一局要等成年、現在還是次成年：還不能互動，被趕的訊息多一句「你還太年輕」
#   3. 成年後：可以互動（在牠的範圍待久了是「退讓或對峙」）
# 用法：bash tools/run_sim.sh stranger_unlock
var f := 0
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.life_log.erase("stranger_observed")
	gs.life_log["stranger_unlock"] = "adult"
	_check(not gs.stranger_can_interact(), "開局沒看過牠：不能直接互動")
	gs.current_region = gs.stranger_territory if gs.stranger_territory != "" else gs.current_region
	gs.apply_drive_off()
	_check(bool(gs.life_log.get("stranger_observed", false)), "被牠趕過：算見過牠")
	_check(not gs.stranger_can_interact() and TranslationServer.translate("event.driven_off.too_young").contains("太年輕"), "這一局要等成年、現在次成年：還不能互動（被趕的訊息多一句太年輕）")
	gs.wolf.age_years = 3.0
	_check(gs.stranger_can_interact(), "成年後：可以直接互動（退讓或對峙）")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
