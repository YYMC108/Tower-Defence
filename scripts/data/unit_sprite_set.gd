class_name UnitSpriteSet
extends Resource
## 一个单位（角色/敌人）的全部动画定义。
##
## 挂到 CharacterData.sprite_set / EnemyData.sprite_set 上。
## 没有配置 sprite_set 的单位会自动回退到"纯色方块占位"，
## 所以美术可以逐个交付，不会阻塞程序。

## 注意：显示缩放**不在这里**，而在 CharacterData.sprite_scale / EnemyData.sprite_scale。
## 刻意只保留一个来源，避免两处配置分叉导致"改了没生效"。

@export var sheets: Array = []


func get_sheet(animation_name: StringName) -> SpriteSheetDef:
	for sheet: SpriteSheetDef in sheets:
		if sheet != null and sheet.animation_name == animation_name:
			return sheet
	return null


func has(sheet_or_name: Variant) -> bool:
	if sheet_or_name is SpriteSheetDef:
		return (sheet_or_name as SpriteSheetDef).texture_path != ""
	return get_sheet(StringName(str(sheet_or_name))) != null


func animation_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for sheet: SpriteSheetDef in sheets:
		if sheet != null:
			names.append(sheet.animation_name)
	return names
