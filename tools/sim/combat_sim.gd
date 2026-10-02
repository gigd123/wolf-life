extends SceneTree
# 戰鬥模擬（SPEC 1.6「戰鬥模式」「勝算基準」）：不同能力的狼 × 對手 × 打法，各打 RUNS 場。
# 打法：fight＝一直撲咬、瀕危就撤退；lunge＝一直猛撲、瀕危就撤退；to_death＝瀕危也不退；threaten＝先威嚇再撲咬。
# 統計：趕走對手（勝）、撤退、戰死的比例，平均受傷，重傷率，回合數。
# 用法：bash tools/run_sim.sh combat_sim 0 400

const WOLVES := [["次成年 40", 40, 40, 40, 80], ["成年 60", 60, 60, 60, 100], ["巔峰 78", 78, 72, 70, 110]]
const OPPONENTS := [["灰熊（搶食）", "grizzly_bear", "adult", "carcass", false], ["灰熊（遭遇）", "grizzly_bear", "adult", "encounter", false],
	["母熊", "grizzly_bear", "adult", "encounter", true], ["幼熊", "grizzly_bear", "juvenile", "encounter", false],
	["狐狸（偷食）", "red_fox", "adult", "carcass", false]]
const POLICIES := ["fight", "lunge", "threaten", "to_death"]

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var CombatScript = load("res://scripts/core/Combat.gd")
	var FR = load("res://scripts/core/FightRules.gd")
	var runs := _env_int("RUNS", 300)
	print("== combat_sim：每格 %d 場" % runs)
	for wd in WOLVES:
		print("[%s：力量 %d 技巧 %d 速度 %d 血量 %d]" % wd)
		for od in OPPONENTS:
			var line := "   %-8s" % od[0]
			for pol in POLICIES:
				var wins := 0; var retreats := 0; var deaths := 0; var dmg := 0.0; var heavy := 0; var rounds := 0
				for r in runs:
					GS.new_game("forest_east")
					var w = GS.wolf
					w.strength = wd[1]; w.skill = wd[2]; w.speed = wd[3]; w.health_max = wd[4]; w.health = wd[4]
					var c = CombatScript.new(w, od[1], od[2], od[3], od[4])
					c.yields = ["yield"]
					var g := 0
					while c.phase != 2 and g < 40:
						g += 1
						var ids: Array = c.options().map(func(o): return o["id"])
						var pick: String = "bite"
						if c.phase == 0:
							pick = "threaten" if pol == "threaten" and g == 1 else "attack"
						elif FR.in_danger(w) and pol != "to_death":
							pick = "retreat"
						elif pol == "lunge":
							pick = "lunge"
						c.choose(pick)
					rounds += c.rounds
					dmg += w.health_max - w.health
					if w.injury == 2: heavy += 1
					match c.outcome:
						"drove_off": wins += 1
						"retreated": retreats += 1
						"died": deaths += 1
				line += "  %s 勝%3.0f%% 退%3.0f%% 死%3.0f%% 傷%3.0f 重%3.0f%% 回%.1f" % [pol, 100.0 * wins / runs, 100.0 * retreats / runs, 100.0 * deaths / runs, dmg / runs, 100.0 * heavy / runs, float(rounds) / runs]
				line += "\n           "
			print(line)
	quit()
	return true
