class_name CombatAnimator
extends Node

# 戰鬥回合的演出（Phase 1.9 第 2 步）：照 Combat 產生的事件序列（見 Combat._ev），
# 用現有的單張姿勢做補間動畫：位移、繞圈、衝刺、震動、閃白、跳出傷害數字。不需要新素材。
# 速度設定存在 user://settings.cfg 的 [combat] anim："normal" 一般、"fast" 快、"off" 略過動畫。

signal finished

const SETTINGS_PATH := "user://settings.cfg"
const MODES := ["normal", "fast", "off"]

var wolf_icon: Control
var opp_icon: Control
var set_wolf_pose: Callable # func(pose: String)
var set_opp_action: Callable # func(action: String)
var playing: bool = false
var _skip: bool = false

static func mode() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return "normal"
	var m: String = str(cfg.get_value("combat", "anim", "normal"))
	return m if MODES.has(m) else "normal"

static func set_mode(m: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("combat", "anim", m)
	cfg.save(SETTINGS_PATH)

static func next_mode() -> String:
	var m: String = MODES[(MODES.find(mode()) + 1) % MODES.size()]
	set_mode(m)
	return m

func _speed() -> float:
	return 2.0 if mode() == "fast" else 1.0

# 播放一回合的事件；略過動畫或 headless 時直接結束。用法：await animator.play(events)
func play(events: Array) -> void:
	if mode() == "off" or DisplayServer.get_name() == "headless" or wolf_icon == null or opp_icon == null or events.is_empty():
		await get_tree().process_frame
		return
	playing = true
	_skip = false
	var wolf_home: Vector2 = wolf_icon.position
	var opp_home: Vector2 = opp_icon.position
	for e in events:
		if _skip:
			break
		await _play_event(e, wolf_home, opp_home)
	wolf_icon.position = wolf_home
	opp_icon.position = opp_home
	wolf_icon.modulate = Color(1, 1, 1, 1)
	opp_icon.modulate = Color(1, 1, 1, 1)
	playing = false
	finished.emit()

# 播放中按一下：剩下的事件不演，直接到結果
func skip() -> void:
	_skip = true

func _tween() -> Tween:
	var t := create_tween()
	t.set_speed_scale(_speed())
	return t

func _play_event(e: Dictionary, wolf_home: Vector2, opp_home: Vector2) -> void:
	var actor: String = str(e.get("actor", ""))
	var act: String = str(e.get("act", ""))
	var hit: bool = bool(e.get("hit", false))
	var dmg: float = float(e.get("damage", 0.0))
	match actor:
		"wolf":
			# 被對手搶先打中、攻擊被打斷（1.9 第 3 步）：才剛起步就被打回來
			if bool(e.get("interrupted", false)):
				_pose(true, "hurt")
				await _dash(wolf_icon, wolf_home, 1.0, 8.0, 0.1)
				await _return(wolf_icon, wolf_home)
				return
			match act:
				"bite", "lunge":
					_pose(true, "bite")
					await _dash(wolf_icon, wolf_home, 1.0, 34.0 if act == "bite" else 54.0, 0.14 if act == "bite" else 0.2)
					if hit:
						await _struck(opp_icon, opp_home, dmg, Color(1, 1, 1))
					else:
						await _sidestep(opp_icon, opp_home, 1.0)
					await _return(wolf_icon, wolf_home)
				"harass":
					_pose(true, "dodge")
					await _circle(wolf_icon, wolf_home)
					_pose(true, "bite")
					await _dash(wolf_icon, wolf_home, 1.0, 28.0, 0.1)
					if hit:
						await _struck(opp_icon, opp_home, dmg, Color(1, 1, 1))
					await _return(wolf_icon, wolf_home)
				"dodge":
					_pose(true, "dodge")
					var t := _tween()
					t.tween_property(wolf_icon, "position", wolf_home + Vector2(-22, -8), 0.12)
					await t.finished
				"threaten":
					_pose(true, "threaten")
					await _bob(wolf_icon, wolf_home, 1.0)
				"probe":
					_pose(true, "threaten")
					await _dash(wolf_icon, wolf_home, 1.0, 14.0, 0.12)
					await _return(wolf_icon, wolf_home)
				"retreat", "leave", "let_go":
					var t := _tween()
					t.tween_property(wolf_icon, "position", wolf_home + Vector2(-30, 0), 0.25)
					if hit or act != "retreat":
						t.parallel().tween_property(wolf_icon, "modulate:a", 0.4, 0.25)
					await t.finished
				"submit":
					_pose(true, "submit")
					await _wait(0.3)
		"opp", "partner":
			match act:
				"attack":
					_opp_action("attack")
					var reach: float = 40.0 if actor == "opp" else 24.0
					await _dash(opp_icon, opp_home, -1.0, reach, 0.14)
					if bool(e.get("dodged", false)) or not hit:
						await _sidestep(wolf_icon, wolf_home, -1.0)
					else:
						_pose(true, "hurt")
						await _struck(wolf_icon, wolf_home, dmg, Color(1.0, 0.45, 0.45), bool(e.get("heavy", false)))
					await _return(opp_icon, opp_home)
					_opp_action("idle")
				"give_up", "tired":
					var t := _tween()
					t.tween_property(opp_icon, "position", opp_home + Vector2(40, 0), 0.35)
					t.parallel().tween_property(opp_icon, "modulate:a", 0.3, 0.35)
					await t.finished
				"submit":
					_opp_action("submit")
					await _wait(0.3)
				"down":
					_opp_action("down")
					var t := _tween()
					t.tween_property(opp_icon, "modulate", Color(0.6, 0.6, 0.6, 0.8), 0.3)
					await t.finished
		"ally":
			# 苔原狼從側邊咬中：對手閃白、跳出數字（顏色不同）
			await _struck(opp_icon, opp_home, dmg, Color(0.75, 0.9, 1.0))

func _pose(is_wolf: bool, pose: String) -> void:
	if is_wolf and set_wolf_pose.is_valid():
		set_wolf_pose.call(pose)

func _opp_action(action: String) -> void:
	if set_opp_action.is_valid():
		set_opp_action.call(action)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec / _speed()).timeout

# 衝向對方：dir 1 往右（狼）、−1 往左（對手）
func _dash(icon: Control, home: Vector2, dir: float, dist: float, dur: float) -> void:
	var t := _tween()
	t.tween_property(icon, "position", home + Vector2(-dir * 6.0, 0), dur * 0.5) # 先蓄勢
	t.tween_property(icon, "position", home + Vector2(dir * dist, -4), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished

func _return(icon: Control, home: Vector2) -> void:
	var t := _tween()
	t.tween_property(icon, "position", home, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished

func _circle(icon: Control, home: Vector2) -> void:
	var t := _tween()
	for p in [Vector2(10, -10), Vector2(20, 0), Vector2(10, 8), Vector2(0, 0)]:
		t.tween_property(icon, "position", home + p, 0.07)
	await t.finished

func _bob(icon: Control, home: Vector2, dir: float) -> void:
	var t := _tween()
	t.tween_property(icon, "position", home + Vector2(dir * 10, -3), 0.12)
	t.tween_property(icon, "position", home, 0.12)
	t.tween_property(icon, "position", home + Vector2(dir * 10, -3), 0.12)
	t.tween_property(icon, "position", home, 0.12)
	await t.finished

func _sidestep(icon: Control, home: Vector2, dir: float) -> void:
	var t := _tween()
	t.tween_property(icon, "position", home + Vector2(dir * 10, -6), 0.08)
	t.tween_property(icon, "position", home, 0.1)
	await t.finished

# 被打中：閃色、震動、跳出傷害數字。heavy 時震得更大。
func _struck(icon: Control, home: Vector2, dmg: float, flash: Color, heavy: bool = false) -> void:
	_float_number(icon, dmg, flash)
	var amp: float = 7.0 if heavy else 4.0
	var t := _tween()
	t.tween_property(icon, "modulate", Color(flash.r * 2.5, flash.g * 2.5, flash.b * 2.5, 1.0), 0.04)
	for i in 4:
		t.tween_property(icon, "position", home + Vector2(amp if i % 2 == 0 else -amp, 0), 0.03)
	t.tween_property(icon, "position", home, 0.03)
	t.parallel().tween_property(icon, "modulate", Color(1, 1, 1, 1), 0.1)
	await t.finished

func _float_number(icon: Control, dmg: float, color: Color) -> void:
	if dmg <= 0.0:
		return
	var label := Label.new()
	label.text = "-%d" % int(round(dmg))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(icon.size.x * 0.5 - 10, -4)
	icon.add_child(label)
	var t := _tween()
	t.tween_property(label, "position", label.position + Vector2(0, -22), 0.5)
	t.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	t.tween_callback(label.queue_free)
