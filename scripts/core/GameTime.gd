extends Node

# Time system: 4 seasons x N days x 5 periods x 4 turns. Age and life-stage
# math is done in seasons elapsed (see GameState._on_season_changed), so
# switching time_mode never changes where a wolf falls in its life cycle.

signal period_changed(period_index: int)
signal day_changed(day: int)
signal season_changed(season_index: int)

const SEASONS := ["spring", "summer", "autumn", "winter"]
const PERIODS := ["dawn", "day", "dusk", "night", "predawn"]
const TURNS_PER_PERIOD := 4

var time_mode: String = "normal" # "normal" or "test"
var season_index: int = 3
var day: int = 1
var period_index: int = 0
var turn_in_period: int = 0

func setup(start_season: String, mode: String) -> void:
	time_mode = mode
	season_index = SEASONS.find(start_season)
	if season_index < 0:
		season_index = 3
	day = 1
	period_index = 0
	turn_in_period = 0

func advance_turns(n: int) -> void:
	for i in range(n):
		_advance_one_turn()

func _advance_one_turn() -> void:
	turn_in_period += 1
	if turn_in_period >= TURNS_PER_PERIOD:
		turn_in_period = 0
		_advance_period()

func _advance_period() -> void:
	period_index += 1
	if period_index >= PERIODS.size():
		period_index = 0
		_advance_day()
	period_changed.emit(period_index)

func _advance_day() -> void:
	day += 1
	if day > _season_day_count():
		day = 1
		_advance_season()
	day_changed.emit(day)

func _advance_season() -> void:
	season_index = (season_index + 1) % SEASONS.size()
	season_changed.emit(season_index)

func _season_day_count() -> int:
	var counts: Dictionary = GameData.balance.get("season_day_count", {})
	return int(counts.get(time_mode, 10))

func current_season() -> String:
	return SEASONS[season_index]

func current_period() -> String:
	return PERIODS[period_index]
