# tests

> 校验脚本目录。这些脚本不参与游戏运行，只用来"证明配置和逻辑没问题"。

详见 [DESIGN.md](res://DESIGN.md)。

## 运行方式

所有脚本都用 Godot 的无头模式运行，**不需要打开编辑器**。在工程根目录执行：

```powershell
# tests/check_project_config.gd
godot --headless --path . --script res://tests/check_project_config.gd
```

Windows 下 `godot` 不在 PATH 的话用完整路径，例如：

```powershell
& "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" `
    --headless --path "D:\new" --script "res://tests/check_project_config.gd"
```

**退出码 0 = 通过**，非 0 = 失败项数量。可以直接接进 CI。

## 现有脚本

| 脚本 | 检查内容 | 什么时候要跑 |
|---|---|---|
| `check_project_config.gd` | 像素风渲染设置、视口、输入映射、2D 碰撞层命名、3D 物理 | **任何人改过 `project.godot` 之后**；换了新机器 clone 之后 |

## 为什么需要这个目录

`project.godot` 和场景文件都是文本，任何人都可能改坏，而 **Godot 对配置错误经常是"静默忽略整段"而不是报错**——比如输入映射被覆盖，你在编辑器里不会看到任何警告，只有运行起来才发现主角不能动。

一份能自动跑的检查，比三个人互相肉眼审查可靠得多。后续每加一个核心系统（伤害矩阵、波次状态机、伤害计算），都应该配一个这样的脚本。
