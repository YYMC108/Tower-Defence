class_name BattleHUD
extends CanvasLayer
## 战斗 HUD。程序化生成控件，不依赖美术资源。
##
## 铁律（DESIGN.md 第 12 节）：**UI 只监听管理器信号，绝不反查实体字段。**
## 这里所有数据都来自 BattleState / RoundManager，不去读某个敌人的 hp。

const FONT_SIZE_BIG: int = 13
const FONT_SIZE_SMALL: int = 10

var _base_label: Label
var _wave_label: Label
var _phase_label: Label
var _enemy_label: Label
var _currency_label: Label
var _center_label: Label
var _hint_label: Label

var _state: BattleState
var _rounds: RoundManager


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	var root := MarginContainer.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 8)
	root.add_theme_constant_override("margin_top", 6)
	root.add_theme_constant_override("margin_right", 8)
	add_child(root)

	var column := VBoxContainer.new()
	column.name = "TopLeft"
	column.add_theme_constant_override("separation", 2)
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(column)

	_base_label = _make_label(column, Color(1.0, 0.45, 0.45), FONT_SIZE_BIG)
	_wave_label = _make_label(column, Color(1.0, 0.92, 0.55), FONT_SIZE_BIG)
	_enemy_label = _make_label(column, Color(0.85, 0.85, 0.90), FONT_SIZE_SMALL)
	_currency_label = _make_label(column, Color(0.60, 0.90, 1.0), FONT_SIZE_SMALL)
	_phase_label = _make_label(column, Color(0.70, 1.0, 0.75), FONT_SIZE_SMALL)

	# 屏幕中央的大字（复活倒计时 / 胜负）
	_center_label = Label.new()
	_center_label.name = "CenterLabel"
	_center_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.anchor_left = 0.0
	_center_label.anchor_right = 1.0
	_center_label.offset_top = 70
	_center_label.add_theme_font_size_override("font_size", 16)
	_center_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	add_child(_center_label)

	# 底部操作提示
	var bottom := MarginContainer.new()
	bottom.name = "BottomHint"
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.add_theme_constant_override("margin_left", 8)
	bottom.add_theme_constant_override("margin_bottom", 4)
	add_child(bottom)

	_hint_label = _make_label(bottom, Color(0.75, 0.75, 0.80), FONT_SIZE_SMALL)
	_hint_label.text = "WASD/方向键 移动   ·   按住鼠标左键 攻击   ·   回车 开始下一波   ·   Backspace 认输"


func _make_label(parent: Node, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func bind(state: BattleState, rounds: RoundManager) -> void:
	_state = state
	_rounds = rounds
	_rounds.phase_changed.connect(_on_phase_changed)
	_rounds.battle_won.connect(_on_battle_won)
	_rounds.battle_lost.connect(_on_battle_lost)
	_state.base_health_changed.connect(_on_base_health_changed)
	_state.battle_currency_changed.connect(_on_currency_changed)
	refresh()


func _process(_delta: float) -> void:
	if _rounds == null:
		return
	if _rounds.is_hero_dead():
		_center_label.text = "主角阵亡\n%.1f 秒后复活（第 %d 次）" % [
			_rounds.hero_respawn_remaining(), _state.hero_death_count,
		]
	elif _center_label.text.begins_with("主角阵亡"):
		_center_label.text = ""


# ─────────────────────────────────────────────
# 信号响应
# ─────────────────────────────────────────────

func _on_base_health_changed(_current: float, _maximum: float) -> void:
	refresh()


func _on_currency_changed(_current: int) -> void:
	refresh()


func _on_phase_changed(_phase: RoundManager.Phase, _wave_index: int) -> void:
	refresh()


func _on_battle_won() -> void:
	_center_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	_center_label.text = "关卡完成！\n大本营剩余 %.0f" % _state.base_health


func _on_battle_lost() -> void:
	_center_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_center_label.text = "大本营陷落\n按 Backspace 重开"


func refresh() -> void:
	if _state == null or _rounds == null:
		return
	_base_label.text = "大本营  %.0f / %.0f" % [_state.base_health, _state.base_max_health]
	_wave_label.text = "波次    %d / %d" % [
		mini(_state.current_wave_index + 1, _state.total_waves), _state.total_waves,
	]
	_enemy_label.text = "场上敌人  %d" % _count_enemies()
	_currency_label.text = "局内资源  %d" % _state.battle_currency
	_phase_label.text = "阶段     %s" % _phase_text()


func _count_enemies() -> int:
	var registry: UnitRegistry = get_tree().get_first_node_in_group(&"unit_registry") as UnitRegistry
	if registry == null:
		return 0
	return registry.enemy_count()


func _phase_text() -> String:
	match _rounds.phase:
		RoundManager.Phase.PREPARE:
			return "布防"
		RoundManager.Phase.COMBAT:
			return "战斗"
		RoundManager.Phase.SETTLE:
			return "结算"
		RoundManager.Phase.BATTLE_OVER:
			return "已结束"
	return "?"
