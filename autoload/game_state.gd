extends Node
## 局外状态（autoload 单例）。
##
## 严格职责边界：这里只放**跨关卡保留**的东西。
##   ✅ 已解锁角色、关卡进度、星星、金币、设置
##   ❌ 大本营血量、当前波次、局内资源 —— 那些属于 BattleState
##
## 详见 DESIGN.md 第 12 节的系统职责矩阵。

signal character_unlocked(character_id: StringName)
signal level_completed(level_id: StringName, stars: int)
signal gold_changed(new_amount: int)

const SAVE_VERSION: int = 1

## 已解锁的角色 id
var unlocked_characters: Array[StringName] = []
## level_id -> 已获得的最高星数（0 = 未通关）
var level_stars: Dictionary = {}
## 金币（局外资源，用于主角成长与解锁）
var gold: int = 0


func _ready() -> void:
	SaveManager.load_game()
	ensure_default_unlocks()


## 保证"默认解锁"的角色一定在列表里。
## M1 阶段没有选人界面，直接全解锁，方便测试。
func ensure_default_unlocks() -> void:
	for data: CharacterData in CharacterRegistry.all_characters():
		if data == null:
			continue
		# all_characters() 已保证元素是 CharacterData，这里做一次防御性检查
		if data.unlocked_by_default and not is_unlocked(data.id):
			unlocked_characters.append(data.id)


func is_unlocked(character_id: StringName) -> bool:
	return unlocked_characters.has(character_id)


func unlock_character(character_id: StringName) -> void:
	if is_unlocked(character_id):
		return
	unlocked_characters.append(character_id)
	character_unlocked.emit(character_id)
	SaveManager.save_game()


func get_level_stars(level_id: StringName) -> int:
	var stars: Variant = level_stars.get(level_id, 0)
	return int(stars)


func record_level_result(level_id: StringName, stars: int) -> void:
	var previous: int = get_level_stars(level_id)
	if stars > previous:
		level_stars[level_id] = stars
	level_completed.emit(level_id, stars)
	SaveManager.save_game()


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
	SaveManager.save_game()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"unlocked_characters": unlocked_characters.duplicate(),
		"level_stars": level_stars.duplicate(),
		"gold": gold,
	}


func from_dict(data: Dictionary) -> void:
	var unlocked: Variant = data.get("unlocked_characters", [])
	unlocked_characters.clear()
	if unlocked is Array:
		for id: Variant in (unlocked as Array):
			unlocked_characters.append(StringName(str(id)))

	var stars: Variant = data.get("level_stars", {})
	level_stars = stars if stars is Dictionary else {}
	gold = int(data.get("gold", 0))
