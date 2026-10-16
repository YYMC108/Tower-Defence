class_name RoundManager
extends Node
## 阶段状态机与波次推进。战斗的"总指挥"。
##
##   PREPARE 布防 → COMBAT 战斗 → SETTLE 结算 → PREPARE ... → 胜负
##
## 详见 DESIGN.md 第 5 节。
##
## 最易写错的一处：COMBAT 的退出条件是**双重**的 ——
##   "不再生成新敌人" 且 "场上敌人全灭"
## 只判断前者会没打完就进下一波；只判断后者会在生成期间提前触发。

signal phase_changed(phase: Phase, wave_index: int)
signal wave_started(wave_index: int, data: WaveData)
signal wave_cleared(wave_index: int)
signal battle_won()
signal battle_lost()
signal hero_revive_scheduled(delay: float, death_count: int)
signal hero_revived()

enum Phase {
	PREPARE,     ## 布防：无敌人，等玩家按回车开战（时长见 LevelData.prepare_seconds）
	COMBAT,      ## 战斗：敌人在场
	SETTLE,      ## 结算：塔重生、惩罚衰减、波次推进
	BATTLE_OVER, ## 胜负已定
}

## 结算阶段停留时长（秒）。这是纯表现停顿，不是策划旋钮，所以留在代码里。
## 布防时长**不在这里** —— 它是每关的设计决定，配在 LevelData.prepare_seconds。
@export var settle_duration: float = 1.2

var state: BattleState = null
var level: LevelData = null
var registry: UnitRegistry = null

var phase: Phase = Phase.PREPARE
var _countdown: float = 0.0
var _respawn_timer: float = 0.0
var _hero_is_dead: bool = false
var _battle_finished: bool = false

## 生成队列是否已全部生成完。
## 初值 true 是有意的：刚进入 PREPARE 时还没有敌人在生成，
## 但此时处于 PREPARE 而非 COMBAT，所以不会被误判为"波次已清"。
## 进入 COMBAT 前会通过 notify_wave_started_spawning() 置为 false。
var _spawn_finished: bool = true

## 由 BattleRoot 注入的回调
var on_enter_prepare: Callable = Callable()
var on_enter_combat: Callable = Callable()
var on_enter_settle: Callable = Callable()
var on_hero_respawn: Callable = Callable()


func bind(p_state: BattleState, p_level: LevelData, p_registry: UnitRegistry) -> void:
	state = p_state
	level = p_level
	registry = p_registry


func begin() -> void:
	_battle_finished = false
	state.base_destroyed.connect(_on_base_destroyed)
	_enter_prepare()


func _process(delta: float) -> void:
	if _battle_finished:
		return

	_tick_hero_respawn(delta)

	match phase:
		Phase.PREPARE:
			# prepare_seconds <= 0 表示**等玩家按回车**（不会自己倒数完），
			# 开战只能由 request_start_wave() 触发。
			if _countdown > 0.0:
				_countdown -= delta
				if _countdown <= 0.0:
					_enter_combat()
		Phase.COMBAT:
			if _is_wave_cleared():
				_enter_settle()
		Phase.SETTLE:
			_countdown -= delta
			if _countdown <= 0.0:
				_advance_after_settle()
		Phase.BATTLE_OVER:
			pass


# ─────────────────────────────────────────────
# 阶段流转
# ─────────────────────────────────────────────

func _enter_prepare() -> void:
	if _battle_finished:
		return
	# 还有波次吗
	if state.current_wave_index >= state.total_waves:
		_finish_battle(true)
		return
	phase = Phase.PREPARE
	# 布防时长来自关卡配置（不是 RoundManager 自己的字段）：
	#   0 → 一直等玩家按回车；>0 → 最多等这么多秒后自动开战
	_countdown = level.prepare_seconds if level != null else 0.0
	phase_changed.emit(phase, state.current_wave_index)
	if on_enter_prepare.is_valid():
		on_enter_prepare.call(state.current_wave_index)


## 布防阶段是否在**等玩家**（而不是在自动倒数）。
## HUD 用它决定要不要显示"按回车开始第 N 波"的提示。
func is_waiting_for_player() -> bool:
	return phase == Phase.PREPARE and not _battle_finished and _countdown <= 0.0


## 玩家主动开战（回车）。布防阶段随时可用 ——
## 即使这关配了自动开始，玩家按回车也能跳过剩余等待。
## 返回是否真的开战了（非布防阶段调用返回 false，是安全的空操作）。
func request_start_wave() -> bool:
	if _battle_finished or phase != Phase.PREPARE:
		return false
	_enter_combat()
	return true


func _enter_combat() -> void:
	if _battle_finished:
		return
	var wave: WaveData = _current_wave()
	if wave == null:
		# 波次配置缺失就当这一波已经打完，直接结算
		push_warning("第 %d 波配置为空，跳过" % (state.current_wave_index + 1))
		_enter_settle()
		return
	phase = Phase.COMBAT
	phase_changed.emit(phase, state.current_wave_index)
	wave_started.emit(state.current_wave_index, wave)
	if on_enter_combat.is_valid():
		on_enter_combat.call(state.current_wave_index, wave)


func _enter_settle() -> void:
	if _battle_finished:
		return
	phase = Phase.SETTLE
	_countdown = settle_duration
	wave_cleared.emit(state.current_wave_index)
	phase_changed.emit(phase, state.current_wave_index)
	if on_enter_settle.is_valid():
		on_enter_settle.call(state.current_wave_index)


func _advance_after_settle() -> void:
	state.advance_wave()
	if state.current_wave_index >= state.total_waves:
		_finish_battle(true)
	else:
		_enter_prepare()


## COMBAT 的双重退出条件
func _is_wave_cleared() -> bool:
	if _spawn_finished and registry.enemy_count() == 0:
		return true
	return false


## WaveSpawner 的生成队列空了会通知这里
func notify_spawn_queue_finished() -> void:
	_spawn_finished = true


func notify_wave_started_spawning() -> void:
	_spawn_finished = false


# ─────────────────────────────────────────────
# 主角复活（递增 + 封顶，DESIGN.md 第 6 节）
# ─────────────────────────────────────────────

## 主角死亡时由 BattleRoot 调用
func notify_hero_died() -> void:
	if _battle_finished:
		return
	# 布防阶段死亡也计数（防止利用安全期送死刷新状态）
	state.hero_death_count += 1
	_hero_is_dead = true
	var delay: float = level.revive_seconds_for_death(state.hero_death_count)
	_respawn_timer = delay
	hero_revive_scheduled.emit(delay, state.hero_death_count)


func _tick_hero_respawn(delta: float) -> void:
	if not _hero_is_dead or _battle_finished:
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_hero_is_dead = false
		_respawn_timer = 0.0
		hero_revived.emit()
		if on_hero_respawn.is_valid():
			on_hero_respawn.call()


func hero_respawn_remaining() -> float:
	return maxf(0.0, _respawn_timer)


func is_hero_dead() -> bool:
	return _hero_is_dead


# ─────────────────────────────────────────────
# 胜负
# ─────────────────────────────────────────────

func _on_base_destroyed() -> void:
	_finish_battle(false)


func _finish_battle(won: bool) -> void:
	if _battle_finished:
		return
	_battle_finished = true
	phase = Phase.BATTLE_OVER
	if won:
		battle_won.emit()
	else:
		battle_lost.emit()


func is_battle_over() -> bool:
	return _battle_finished


func did_win() -> bool:
	return _battle_finished and state != null and state.is_base_alive()


func current_wave_data() -> WaveData:
	return _current_wave()


func _current_wave() -> WaveData:
	if level == null:
		return null
	if state.current_wave_index < 0 or state.current_wave_index >= level.waves.size():
		return null
	var wave: Variant = level.waves[state.current_wave_index]
	if wave is WaveData:
		return wave as WaveData
	return null
