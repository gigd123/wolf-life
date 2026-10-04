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

# 換季（SPEC 1.6「季節轉換」）：天數到了不會自動換季，只記為到期；由 GameState 在下一次睡覺時呼叫 change_season()。
# 到期後 day 會繼續往上數（超過一季的天數），畫面顯示季末字樣。
func season_due() -> bool:
	return day > _season_day_count()

# 到期後過了幾天（到期那天算 1）；沒到期是 0。
func days_overdue() -> int:
	return max(0, day - _season_day_count())

# 再過 n 回合後是否已經到期（睡覺前用來判斷這一覺是不是換季睡眠）。
func season_due_after(n: int) -> bool:
	var turns_today: int = period_index * TURNS_PER_PERIOD + turn_in_period + n
	return day + turns_today / (TURNS_PER_PERIOD * PERIODS.size()) > _season_day_count()

func change_season() -> void:
	day = 1
	_advance_season()

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
