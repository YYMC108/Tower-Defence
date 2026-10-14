@tool
extends SceneTree
## 架构配置校验脚本（临时，验证后删除）

var _fail := 0


func _check_int(key: String, want: int, label: String) -> void:
	var got := int(ProjectSettings.get_setting(key, -999))
	var tag := label if label != "" else "期望 %d" % want
	if got == want:
		print("  [通过] %s = %d" % [key, got])
	else:
		print("  [失败] %s 期望 %d，实际 %d" % [key, want, got])
		_fail += 1


func _check_str(key: String, want: String) -> void:
	var got := String(ProjectSettings.get_setting(key, "<未设置>"))
	if got == want:
		print("  [通过] %s = \"%s\"" % [key, got])
	else:
		print("  [失败] %s 期望 \"%s\"，实际 \"%s\"" % [key, want, got])
		_fail += 1


func _init() -> void:
	print("=== 1. 像素风渲染设置 ===")
	_check_int("rendering/textures/canvas_textures/default_texture_filter", 0, "Nearest(0)")
	_check_str("display/window/stretch/scale_mode", "integer")
	_check_str("display/window/stretch/mode", "canvas_items")

	print("=== 2. 视口 ===")
	_check_int("display/window/size/viewport_width", 480, "")
	_check_int("display/window/size/viewport_height", 320, "")

	print("=== 3. 输入映射（手写配置最易出错处）===")
	var expected := {
		"move_left": 2, "move_right": 2, "move_up": 2, "move_down": 2,
		"attack": 1, "attack_secondary": 1,
		"skill_1": 1, "skill_2": 1, "skill_3": 1, "dash": 1,
		"pause": 1, "start_wave": 2, "surrender": 1,
	}
	for act: String in expected.keys():
		if not InputMap.has_action(act):
			print("  [失败] 缺少动作: ", act)
			_fail += 1
			continue
		var evs := InputMap.action_get_events(act)
		var want: int = expected[act]
		if evs.size() == want:
			var desc := PackedStringArray()
			for e in evs:
				if e is InputEventKey:
					desc.append("Key:" + OS.get_keycode_string((e as InputEventKey).physical_keycode))
				elif e is InputEventMouseButton:
					desc.append("Mouse:%d" % (e as InputEventMouseButton).button_index)
			print("  [通过] %-18s %d 个绑定  ->  %s" % [act, evs.size(), ", ".join(desc)])
		else:
			print("  [失败] %-18s 期望 %d 个绑定，实际 %d" % [act, want, evs.size()])
			_fail += 1

	print("=== 4. 2D 碰撞层命名 ===")
	var layer_expect := {
		1: "terrain", 2: "enemy", 3: "tower", 4: "player",
		5: "projectile", 6: "decoration", 7: "ui",
	}
	for i: int in layer_expect.keys():
		var key := "layer_names/2d_physics/layer_%d" % i
		var val := String(ProjectSettings.get_setting(key, ""))
		if val == layer_expect[i]:
			print("  [通过] layer_%d = %s" % [i, val])
		else:
			print("  [失败] layer_%d 期望 %s，实际 '%s'" % [i, layer_expect[i], val])
			_fail += 1
	print("  layer_8 = '", String(ProjectSettings.get_setting("layer_names/2d_physics/layer_8", "")), "' （应为空）")

	print("=== 5. 3D 物理是否已回到引擎默认（不再使用 Jolt）===")
	# Godot 始终提供该设置项；删除 [physics] 段后它回落为 DEFAULT，即不再强制 Jolt。
	var engine_setting: Variant = ProjectSettings.get_setting("physics/3d/physics_engine", "<未设置>")
	var engine_str := str(engine_setting)
	print("  physics/3d/physics_engine = ", engine_str)
	if engine_str.contains("Jolt"):
		print("  [警告] Jolt 仍被启用")
	else:
		print("  [通过] 已不再使用 Jolt（值为引擎默认）")

	print("=== 6. 应用信息 ===")
	print("  config/name = ", str(ProjectSettings.get_setting("application/config/name")))
	print("  features    = ", str(ProjectSettings.get_setting("application/config/features")))

	print("")
	if _fail == 0:
		print(">>> 全部校验通过，配置可被 Godot 正常解析 <<<")
	else:
		print(">>> 有 ", _fail, " 项校验失败 <<<")
	quit(_fail)
