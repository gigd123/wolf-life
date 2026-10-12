extends SceneTree
var done := false
func _process(_d) -> bool:
	if done:
		return true
	done = true
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	for den in ["mountain_foothills", "mountain_canyon", "grassland_riverwoods", "grassland_hills"]:
		var ages := []; var deaths := {}; var prey := {}
		for r in 5:
			var ap = AP.new("all", "average")
			ap.start(den)
			while not ap.done(): ap.step(5)
			ap.finish()
			ages.append(snapped(GS.wolf.age_years, 0.1))
			deaths[GS.wolf.death_cause] = int(deaths.get(GS.wolf.death_cause, 0)) + 1
			for a in GS.life_log.get("prey_count", {}).keys():
				prey[a] = int(prey.get(a, 0)) + int(GS.life_log["prey_count"][a])
		print(den, " ages ", ages, " deaths ", deaths, " prey ", prey)
	quit()
	return true
