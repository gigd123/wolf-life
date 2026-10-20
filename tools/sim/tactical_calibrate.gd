extends "res://tools/sim/tactical_hunt_sim.gd"
# 戰術狩獵對齊 Phase 2b 的成功率目標（2026-10-20，使用者選「A 接進主遊戲 + B 先對齊成功率」）：
# 單隻白尾鹿、情境 A～D，普通的狼（≈ 主遊戲一般成年，能力 60）、快的狼（≈ 強狼），固定鹿的體況，
# 每種策略各 RUNS 場；列出各策略的成功率與「最好的策略」。
# 目標（SPEC Phase 2b，決定出手之後）：一般成年對健康成獸 25～35%、強狼 45～55%；對虛弱的 50～80%。
# 用法：bash tools/run_sim.sh tactical_calibrate 0 150

const CAL_POLICIES := ["chase", "pace", "stalk", "ambush"]
var tally := {}

# 分階段記錄：撲咬時鹿的狀態、撲中沒、咬住後的結果
func _step(h, pol: String) -> void:
	var was_held: bool = h.held
	var state: String = h.deer_state
	var e0: int = h.events.size()
	super._step(h, pol)
	if not was_held and h.held:
		tally["hit_" + state] = int(tally.get("hit_" + state, 0)) + 1
	elif not was_held and not h.held and h.events.slice(e0).any(func(e): return str(e).contains("撲空")):
		tally["miss_" + state] = int(tally.get("miss_" + state, 0)) + 1
	if was_held and h.done:
		tally["hold_" + str(h.result)] = int(tally.get("hold_" + str(h.result), 0)) + 1
	elif was_held and not h.held and not h.done:
		tally["hold_broke"] = int(tally.get("hold_broke", 0)) + 1

const TARGETS := {"normal.healthy": [0.25, 0.35], "fast.healthy": [0.45, 0.55], "normal.weak": [0.5, 0.8], "fast.weak": [0.5, 0.8]}

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 150
	var h = TH.new()
	print("== 戰術狩獵 × Phase 2b 成功率（每格 %d 場；策略：猛追／耐力追／潛近截角／伏擊）" % runs)
	for profile in ["normal", "fast"]:
		for cond in ["healthy", "average", "weak"]:
			var bests: Array = []
			var instinct: Array = []
			var line := "%-6s %-7s" % [profile, cond]
			for sc in ["A", "B", "C", "D"]:
				var rates: Array = []
				for pol in CAL_POLICIES:
					var ok := 0
					for i in runs:
						h.setup(sc, profile, i * 7919 + 13)
						h.herd[h.di]["condition"] = cond
						_play(h, pol)
						if h.result == "caught":
							ok += 1
					rates.append(float(ok) / runs)
				var best: float = rates.max()
				bests.append(best)
				# 交給本能（Phase 2c 第 3 步）：依局面挑一種打法
				var iok := 0
				for i in runs:
					h.setup(sc, profile, i * 7919 + 13)
					h.herd[h.di]["condition"] = cond
					TacticalInstinct.play(h)
					if h.result == "caught":
						iok += 1
				instinct.append(float(iok) / runs)
				line += "  %s %s（最好 %d%%）" % [sc, "/".join(rates.map(func(r): return "%d" % roundi(r * 100.0))), roundi(best * 100.0)]
			var avg_best: float = 0.0
			for b in bests:
				avg_best += b
			avg_best /= bests.size()
			var key := "%s.%s" % [profile, cond]
			var target: String = ""
			if TARGETS.has(key):
				target = "目標 %d～%d%%" % [roundi(TARGETS[key][0] * 100.0), roundi(TARGETS[key][1] * 100.0)]
			var avg_inst: float = 0.0
			for b in instinct:
				avg_inst += b
			avg_inst /= max(1, instinct.size())
			print(line + "  → 四情境最好策略平均 %d%% %s；交給本能 %d%%（%s）" % [roundi(avg_best * 100.0), target, roundi(avg_inst * 100.0), "/".join(instinct.map(func(r): return "%d" % roundi(r * 100.0)))])
			print("        分階段（所有情境與策略）：", tally)
			tally = {}
	return true
