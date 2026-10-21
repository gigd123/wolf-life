extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2f 第 2 步：獵幼鹿（母鹿護幼）的校準。物種（SPECIES，預設 moose）的母鹿＋幼鹿，目標是幼鹿；
# 狼（普通、快）× 母鹿體況，四種打法取最好的、交給本能；另外列：母鹿衝過來的場次、被母鹿踢中的場次與平均傷害。
# 目標：對齊選單式 hunt_levels 的 juvenile（駝鹿：一般成年約 80%）；母駝鹿踢中的傷比白尾鹿、馬鹿重。
# 用法：bash tools/run_sim.sh tactical_calf_sim 0 40；SPECIES=elk FAMILIES=open,edge
const WINDS := ["headwind", "crosswind", "tailwind"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var species: String = OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "moose"
	var fams: PackedStringArray = (OS.get_environment("FAMILIES") if OS.get_environment("FAMILIES") != "" else "dense,edge,stream,logs").split(",")
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}}
	print("== %s 的幼鹿（每格 %d 場 × %d 個地圖族）：最好的打法／交給本能｜母鹿衝過來、被母鹿踢中、平均傷害" % [species, runs, fams.size()])
	for wk in ["normal", "fast"]:
		var line := "%-6s" % wk
		for cond in ["healthy", "weak"]:
			var by_pol := {}
			var inst := 0
			var defended := 0
			var hit := 0
			var dmg := 0.0
			var n := 0
			for pol in ["chase", "pace", "stalk", "ambush", ""]:
				var ok := 0
				for fam in fams:
					for i in runs:
						h.setup_from_game({"family": fam, "seed": i * 7919 + 17, "condition": cond, "wolf": wolves[wk].duplicate(), "wind_relation": WINDS[i % 3], "species": species, "season": "summer", "fawn": true})
						for k in h.herd.size():
							if h.is_fawn(k):
								h.target = k
								h.di = k
						if pol == "":
							h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
							var ip: String = TacticalInstinct.pick_policy(h)
							var guard := 0
							while not h.done and guard < 60:
								guard += 1
								TacticalInstinct.step(h, ip)
							n += 1
							if h.defends > 0:
								defended += 1
							var md: float = float(h.damage_by.get("mother", 0.0))
							if md > 0.0:
								hit += 1
								dmg += md
						else:
							_play(h, pol)
						if h.result == "caught":
							ok += 1
				if pol == "":
					inst = ok
				else:
					by_pol[pol] = float(ok) / (runs * fams.size())
			var best_pol: String = by_pol.keys()[0]
			for k in by_pol.keys():
				if float(by_pol[k]) > float(by_pol[best_pol]):
					best_pol = k
			line += "  母鹿%s 最好 %d%%（%s）本能 %d%%｜衝過來 %d%%、踢中 %d%%、平均 %.0f" % [cond, roundi(100.0 * float(by_pol[best_pol])), best_pol,
				roundi(100.0 * inst / max(1, n)), roundi(100.0 * defended / max(1, n)), roundi(100.0 * hit / max(1, n)), dmg / max(1, hit)]
		print(line)
	return true
