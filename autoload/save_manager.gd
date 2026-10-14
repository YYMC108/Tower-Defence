extends Node
## 存档读写（autoload 单例）。
##
## 存到 user://save.json（Windows 上是 %APPDATA%\Godot\app_userdata\Tower Defence\）。
## 带 version 字段，方便将来迁移存档格式。

const SAVE_PATH: String = "user://save.json"

## 是否禁用存档写入。自动化测试会通过 --no-save 命令行参数打开，避免污染真实存档。
var writes_enabled: bool = true


func _ready() -> void:
	# 自动化测试友好：带 --no-save 运行时完全不写盘
	if OS.get_cmdline_args().has("--no-save") or OS.get_cmdline_user_args().has("--no-save"):
		writes_enabled = false


func save_game() -> void:
	if not writes_enabled:
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("存档写入失败: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(GameState.to_dict(), "\t"))
	file.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("存档读取失败: %s" % FileAccess.get_open_error())
		return
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		push_warning("存档损坏，已忽略: %s" % SAVE_PATH)
		return
	GameState.from_dict(parsed as Dictionary)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
