extends Node

# Central place for the few real audio assets we have so far (see
# assets/audio/) — everything else is still silent until more are produced.
# One shared player for one-shot sfx (never more than one plays at once in
# Phase 1) plus a dedicated looping player for the ambient bgm.

var bite_stream: AudioStream = preload("res://assets/audio/sfx_bite.wav")
var howl_stream: AudioStream = preload("res://assets/audio/sfx_wolf_howl.wav")
var level_up_stream: AudioStream = preload("res://assets/audio/sfx_level_up.wav")
var bgm_stream: AudioStream = preload("res://assets/audio/bgm_meadow_loop.wav")

var sfx_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer

func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	bgm_player = AudioStreamPlayer.new()
	bgm_player.volume_db = -10.0
	bgm_player.finished.connect(func(): bgm_player.play())
	add_child(bgm_player)

func play_bite() -> void:
	sfx_player.stream = bite_stream
	sfx_player.play()

func play_howl() -> void:
	sfx_player.stream = howl_stream
	sfx_player.play()

func play_level_up() -> void:
	sfx_player.stream = level_up_stream
	sfx_player.play()

func play_bgm() -> void:
	if bgm_player.stream != bgm_stream:
		bgm_player.stream = bgm_stream
	if not bgm_player.playing:
		bgm_player.play()

func stop_bgm() -> void:
	bgm_player.stop()
