extends SceneTree
# 戰術戰鬥原型的模擬（規格第十一節、第一節的通過標準，2026-11-04）。
# 每個情境 × 固定打法 × 知識 × 結算方式，各 RUNS 場（預設 200），印出：拿到 1 段以上並撤出的比例、平均段數、
# 擊退率、受傷（血量少一成以上）、被打倒、回合數、被假動作騙到（照預告閃開卻是假衝）、伴侶受傷。
# 用法：RUNS=200 SC=<情境，逗號分隔，可省略> MODES=sync,alternate WOLF=average bash tools/run_sim.sh tactical_combat_sim
var RUNS := 200

func _initialize() -> void:
	_run.call_deferred()

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

const STRATS := ["front", "rear", "grab_run", "dodge", "guard", "follow_tell", "auto"]

func _run() -> void:
	RUNS = int(_env("RUNS", "200"))
	var scs: Array = Array(_env("SC", "grizzly_on_carcass,grizzly_guard_facing,grizzly_arrives,grizzly_open,cougar_cache,cougar_ambush,grizzly_on_carcass_mate,grizzly_arrives_mate").split(","))
	var modes: Array = Array(_env("MODES", "sync,alternate").split(","))
	var wolf: String = _env("WOLF", "average")
	var knows: Array = Array(_env("KNOW", "novice,veteran").split(","))
	var strats: Array = Array(_env("STRATS", ",".join(STRATS)).split(","))
	for sc in scs:
		print("== %s（%s 的狼）" % [sc, wolf])
		for m in modes:
			for k in knows:
				for st in strats:
					var r := _batch(sc, st, wolf, k, m)
					print("  %-9s %-8s %-11s 叼到並撤出 %3.0f%%  段數 %.2f  擊退 %3.0f%%  受傷 %3.0f%%  打倒 %3.0f%%  回合 %4.1f  被騙 %3.0f%%  伴侶受傷 %3.0f%%  %s" % [
						m, k, st, r["got"] * 100.0, r["meat"], r["drove"] * 100.0, r["hurt"] * 100.0, r["knocked"] * 100.0, r["rounds"], r["fooled"] * 100.0, r["mate_hurt"] * 100.0, r["outs"]])
	quit()

func _batch(sc: String, st: String, wolf: String, know: String, m: String) -> Dictionary:
	var acc := {"got": 0.0, "meat": 0.0, "drove": 0.0, "hurt": 0.0, "knocked": 0.0, "rounds": 0.0, "fooled": 0.0, "feints": 0.0, "mate_hurt": 0.0, "outs": {}}
	for s in RUNS:
		var tc := TacticalCombat.new()
		tc.setup(sc, {"seed": 1000 + s, "wolf_profile": wolf, "knowledge": know, "mode": m})
		var hp0: float = tc.units[0]["hp"]
		var fooled := 0
		var feints := 0
		var g := 0
		while not tc.done and g < 40:
			g += 1
			tc.begin_round()
			var p := _policy(tc, st)
			tc.plan(0, p)
			var e: int = tc.enemy_index()
			var dodged: bool = str(p.get("action", "")) == "dodge" or bool(p.get("fled_tell", false))
			var it: Dictionary = tc.intents.get(e, {})
			var evs: Array = tc.resolve()
			if not it.is_empty() and str(it.get("looks", "")) == "charge" and int(it.get("seen", {}).get("level", 0)) >= 2:
				if str(it["action"]) == "bluff_charge":
					feints += 1
					if dodged:
						fooled += 1
		var u: Dictionary = tc.units[0]
		var meat := tc.meat_taken()
		if meat > 0:
			acc["got"] += 1.0
		acc["meat"] += meat
		if tc.outcome == "enemy_left" and str(tc.units[tc.enemy_index()]["out_reason"]) in ["hurt", "patience"]:
			acc["drove"] += 1.0
		if float(u["hp"]) < hp0 * 0.9:
			acc["hurt"] += 1.0
		if str(u["out_reason"]) == "knocked":
			acc["knocked"] += 1.0
		acc["rounds"] += tc.rounds
		acc["fooled"] += fooled
		acc["feints"] += feints
		var mi := tc.index_of("mate")
		if mi >= 0 and float(tc.units[mi]["hp"]) < float(tc.units[mi]["hp_max"]) * 0.9:
			acc["mate_hurt"] += 1.0
		acc["outs"][tc.outcome] = int(acc["outs"].get(tc.outcome, 0)) + 1
	var n := float(RUNS)
	return {"got": acc["got"] / n, "meat": acc["meat"] / n, "drove": acc["drove"] / n, "hurt": acc["hurt"] / n, "knocked": acc["knocked"] / n,
		"rounds": acc["rounds"] / n, "fooled": acc["fooled"] / max(1.0, acc["feints"]), "mate_hurt": acc["mate_hurt"] / n, "outs": JSON.stringify(acc["outs"])}

# --- 固定打法 ---

func _carry_out(tc: TacticalCombat) -> Dictionary:
	var u: Dictionary = tc.units[0]
	if tc.map.on_edge(u["pos"]):
		return {"action": "retreat"}
	var mv: Vector2i = tc._ally_move(0, tc._nearest_edge_away(0), tc._shown_zone_for(0))
	var p := {"action": "dodge" if tc._shown_zone_for(0).has(mv) else "wait"}
	if mv != u["pos"]:
		p["move"] = mv
	if tc.map.on_edge(mv):
		p["action"] = "retreat"
	return p

func _to(tc: TacticalCombat, goal: Vector2i, avoid_zone := false) -> Vector2i:
	var z: Dictionary = tc._shown_zone_for(0) if avoid_zone else {}
	return tc._ally_move(0, goal, z)

func _policy(tc: TacticalCombat, st: String) -> Dictionary:
	var e: int = tc.enemy_index()
	var u: Dictionary = tc.units[0]
	if str(u["carrying"]) != "":
		return _carry_out(tc)
	if not tc.active(e):
		return {"action": "wait"}
	var ep: Vector2i = tc.units[e]["pos"]
	var ef: Vector2i = tc.units[e]["facing"]
	var p := {"action": "wait", "target": e}
	var has_food: bool = not tc.carcass.is_empty() and int(tc.carcass["segments"]) > 0
	match st:
		"front":
			var goal: Vector2i = ep + ef
			var mv := _to(tc, goal)
			if mv != u["pos"]: p["move"] = mv
			p["action"] = "bite"
		"rear":
			var goal2: Vector2i = ep - ef
			var mv2 := _to(tc, goal2, true)
			if mv2 != u["pos"]: p["move"] = mv2
			p["action"] = "bite" if tc.map.adjacent(mv2, ep) and TacticalGrid.side_of(ep, ef, mv2) != "front" else "wait"
		"grab_run":
			if not has_food:
				return _policy(tc, "dodge")
			if tc.take_kinds(0).has("piece") and (bool(tc.units[e]["eating"]) or TacticalGrid.side_of(ep, ef, u["pos"]) != "front"):
				return {"action": "take", "kind": "piece"}
			var cp: Vector2i = tc.carcass["pos"]
			var best: Vector2i = cp
			var bs := -INF
			for d in TacticalGrid.DIRS:
				var c: Vector2i = cp + d
				if tc.map.in_bounds(c) and not tc.blocks_for(0).has(c) and not tc._impassable(0).contains(tc.map.terrain(c)):
					var sd := TacticalGrid.side_of(ep, ef, c)
					var v: float = (2.0 if sd == "rear" else (1.0 if sd == "side" else -2.0)) - tc.map.dist(u["pos"], c) * 0.2
					if v > bs:
						bs = v
						best = c
			var mv3 := _to(tc, best, true)
			if mv3 != u["pos"]: p["move"] = mv3
			var save: Vector2i = u["pos"]
			u["pos"] = mv3
			var can: bool = tc.take_kinds(0).has("piece") and TacticalGrid.side_of(ep, ef, mv3) != "front"
			u["pos"] = save
			p["action"] = "take" if can else "wait"
			p["kind"] = "piece"
		"dodge":
			var away: Vector2i = u["pos"] + (u["pos"] - ep).sign() * 2
			var mv4 := _to(tc, Vector2i(clampi(away.x, 0, tc.map.width - 1), clampi(away.y, 0, tc.map.height - 1)), true)
			if mv4 != u["pos"]: p["move"] = mv4
			p["action"] = "dodge" if tc._shown_zone_for(0).has(mv4) else "observe"
			if tc.map.on_edge(mv4) and tc.rounds > 6: p["action"] = "retreat"
		"guard":
			if not has_food:
				return _policy(tc, "dodge")
			if tc.take_kinds(0).has("piece") and tc.units[e].get("attention", -1) != 0:
				return {"action": "take", "kind": "piece"}
			var mv5 := _to(tc, tc.carcass["pos"])
			if mv5 != u["pos"]: p["move"] = mv5
			p["action"] = "bite" if tc.map.adjacent(mv5, ep) else "wait"
		"follow_tell":
			# 看到預告就照預告閃（除非看出可能是虛張聲勢），否則找機會叼肉或從側後咬
			var it: Dictionary = tc.intents.get(e, {})
			var seen: Dictionary = it.get("seen", {})
			var zone: Dictionary = tc._shown_zone_for(0)
			var threatened: bool = zone.has(u["pos"]) or (str(seen.get("looks", "")) == "charge" and tc.map.dist(u["pos"], ep) <= 4.5)
			if threatened and not bool(seen.get("feint_hint", false)):
				var mv6 := _to(tc, u["pos"] + (u["pos"] - ep).sign() * 2, true)
				if mv6 != u["pos"]: p["move"] = mv6
				p["action"] = "dodge"
				p["fled_tell"] = true
				return p
			if has_food:
				return _policy(tc, "grab_run")
			return _policy(tc, "rear")
		"auto":
			return tc.auto_plan(0)
	return p
