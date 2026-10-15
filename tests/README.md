# tests

> 校验脚本目录。这些脚本不参与游戏运行，只用来"证明配置和逻辑没问题"。

详见 [DESIGN.md](res://DESIGN.md)。

## 运行方式

### 为什么有些测试必须用"场景"方式运行

**`--script` 模式不会注册 autoload**。所以任何引用了 `GameState` / `SaveManager`
的脚本，在 `--script` 模式下会直接编译失败（`Identifier not found: GameState`）。
这不是代码错误，是运行方式的问题。

规则很简单：

| 测试引用了 autoload | 运行方式 |
|---|---|
| 否（只用内置类） | `--script` 可以 |
| **是** | **必须用场景方式** |

### 命令

```powershell
# 场景方式的测试（推荐，通用），--no-save 让它绝不写真实存档
& "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" `
    --headless --path "D:\new" res://tests/battle_smoke_test.tscn -- --no-save

# 纯 --script 的测试
& "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" `
    --headless --path "D:\new" --script res://tests/check_project_config.gd
```

**退出码 0 = 通过**，非 0 = 失败项数量。可以直接接进 CI。

> ⚠️ **首次运行前必须先让 Godot 导入一次工程**，否则 `class_name` 全局类没注册，
> 所有脚本都会报 `Identifier "XXX" not declared`：
> ```powershell
> godot --headless --editor --path . --quit
> ```

## 现有脚本

| 脚本 | 运行方式 | 检查内容 | 什么时候要跑 |
|---|---|---|---|
| `check_project_config.gd` | `--script` | 像素风渲染设置、视口、输入映射、2D 碰撞层命名、3D 物理 | **任何人改过 `project.godot` 之后**；换新机器 clone 之后 |
| `art_sprite_test.gd` | `--script` | **每个动画的每一帧实际像素尺寸**（能抓住切片错误）、帧数、`animation_speed` 必须为 1.0、朝向翻转接口存在 | **任何人改过精灵配置或素材之后** |
| `battle_smoke_test.tscn` | **场景** | 真的把战斗跑起来：场景装配、波次生成、路径推进、**主角物理阻挡**、**死亡后近战穿行**、大本营掉血、递增复活与封顶、波次清空、胜负判定 | **任何人改过战斗逻辑之后** |

## ⚠️ 为什么需要 `art_sprite_test`（一次真实事故）

曾经因为假设「帧是正方形的，所以 **帧数 = 宽 ÷ 高**」，
把 `ninja_attack.png`（2048×128，**每帧 256×128**，共 8 帧）算成了 16 帧，
于是每帧被从中间切成两半 —— 表现为**角色只剩半个身体**，且只在攻击时出现。

**这个 bug 逻辑测试完全查不到**：切片在代码看来"成功了"，没有报错，
只是画面错了。所以这类问题**必须直接断言每帧的像素尺寸**。

教训：**帧不一定是正方形的**。挥刀、射击这类动作常把画幅做宽。
`SpriteSheetDef.frame_count` **必须显式填写**，留 0 会退化成正方形假设并发出警告。

## 冒烟测试的覆盖边界（重要）

`battle_smoke_test` 在 headless 下运行，**没有鼠标**，所以：

- ✅ 它验证**不依赖输入**的部分：寻路、物理阻挡、复活、大本营伤害、阶段流转
- ❌ 它**不验证**主角的鼠标瞄准与攻击手感 —— 那必须由人在编辑器里按 F5 试

**不要因为冒烟测试通过就认为"游戏没问题"。** 它能拦住的是逻辑回归，拦不住手感问题。

## 为什么需要这个目录

`project.godot` 和场景文件都是文本，任何人都可能改坏，而 **Godot 对配置错误经常是"静默忽略整段"而不是报错**——比如输入映射被覆盖，你在编辑器里不会看到任何警告，只有运行起来才发现主角不能动。

一份能自动跑的检查，比三个人互相肉眼审查可靠得多。后续每加一个核心系统（塔合成、局外成长），都应该配一个这样的脚本。
