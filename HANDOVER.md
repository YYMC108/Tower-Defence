# 接手须知（给下一个 AI / 新协作者）

> 本文档讲**怎么快速接手**，不是设计规格。
> **设计规格的唯一来源是 [DESIGN.md](DESIGN.md)**，两者冲突时以 DESIGN.md 为准。
>
> 最后更新：`8ef2947`（main，已与远端一致，工作区干净）

---

## 0. 一句话说清这个项目

**2D 像素风、关卡制塔防。** 核心设计取向：

- **主角是主输出**，而且**是近战敌人通往大本营的唯一物理阻挡**
- **塔是辅助**（输出 / 治疗 / 控制），只被远程敌人伤害
- 近战敌人只打主角和大本营，**无视塔**；远程敌人打主角和塔，**不打大本营**
- → 玩家天然要先杀远程、要挡近战、要保塔

游戏引擎 **Godot 4.7.2**。仓库 `git@github.com:YYMC108/Tower-Defence.git`（**SSH**，见坑 12）。

---

## 1. 先读什么（按这个顺序，别跳）

| 顺序 | 内容 | 为什么 |
|---|---|---|
| 1 | 本文档全部 | 状态、命令、坑 |
| 2 | [DESIGN.md](DESIGN.md) 第 **1、3、5** 节 | 术语 / **伤害矩阵** / **阶段状态机** —— 最容易写错的三处 |
| 3 | [DESIGN.md](DESIGN.md) 第 **15.11、16.2** 节 | **世界尺度** —— 改任何尺寸前必读 |
| 4 | [DESIGN.md](DESIGN.md) 第 **18、20** 节 | 里程碑 / 下一步 |
| 5 | [README.md](README.md) | 怎么跑、怎么改配置 |

美术规格在 [ART_SPEC.md](ART_SPEC.md)（从 DESIGN.md §15 提取的，别直接改它）。

---

## 2. 当前状态（`8ef2947`）

**已完成**：M0 架构、M1 战斗闭环（远超原计划）、原 M3 复活机制（M1 期间提前做完）、
美术批次一+二**全部接入**。

**已有内容**：39 个 `.gd`、19 个 `.tres`、3 个 `.tscn`、41 张 PNG。

能玩到的：1536×960 地图 / 24×15 格 / 单位 128px / 1 塔位 / 1 波 4 只近战。
主角三段连招（连点鼠标）、攻击定身、受击三层表现（闪白+受击动画+命中火花）、
据点三态（蓝→橙红→全红）、布防等回车开战、按 R 重开。

**未实现**（输入已映射但代码 0 引用）：
`skill_1` / `skill_2` / `skill_3` / `dash` / `attack_secondary`

**美术侧还有欠账**：据点 idle 呼吸帧、UI/技能图标、塔 2★/3★ 外观。

---

## 3. 环境与命令（可直接复制）

**Godot 不在 PATH**，用绝对路径：

```powershell
$godot = "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
```

**改了 `.gd` / 新增素材后，先导入一次**（否则 `class_name` 全局类不认识、`--script` 模式会报错）：

```powershell
& $godot --headless --editor --path "D:\new" --quit
```

**三个测试套件**（全部通过才算完）：

```powershell
# 1) 精灵切片（36 项）—— --script 模式
& $godot --headless --path "D:\new" --script "res://tests/art_sprite_test.gd"

# 2) 工程配置回归 —— --script 模式
& $godot --headless --path "D:\new" --script "res://tests/check_project_config.gd"

# 3) 战斗冒烟（54 项）—— **必须跑场景模式**（--script 不注册 autoload）
& $godot --headless --path "D:\new" "res://tests/battle_smoke_test.tscn" -- --no-save
```

**只检查脚本能不能解析**（不执行，用来定位"测试静默挂起"）：

```powershell
& $godot --headless --path "D:\new" --check-only --script "res://tests/battle_smoke_test.gd"
```

**数据生成器**（⚠️ **一次性引导脚本，重跑会覆盖 `.tres` 里的手工调整**）：

```powershell
& $godot --headless --path "D:\new" --script "res://tools/gen_art_resources.gd"   # 角色/敌人/关卡配置
& $godot --headless --path "D:\new" --script "res://tools/paint_test_level.gd"    # TileSet + 地形
```

**截图**必须**非 headless**（dummy 光栅化器不产生像素），并用 `await RenderingServer.frame_post_draw` 后再取图。

---

## 4. 会让你浪费半天的坑（每条都真实发生过）

### 4.1 测试"卡死"其实是解析错误
症状：**一行输出都没有、进程也不退出**。
原因：脚本有解析错误 → `_ready()` 从不执行 → 场景空转 → 永不 quit。
定位：用上面的 `--check-only`。
**我自己在这上面栽了两次**（都是重复声明变量）。写测试时尤其注意变量名别与前面的步骤重复。

### 4.2 提交信息里有中文引号 → PowerShell 拆断参数
`git commit -m "…"` 里如果有中文引号 `"`，会被 PowerShell 当成字符串边界，
把正文当 pathspec 报 `pathspec 'xxx' did not match`。
**约定：提交信息一律写进文件，用 `git commit -F <file>`，提交后删掉文件。**

### 4.3 `--script` 模式不注册 autoload
任何引用 `GameState` / `SaveManager` 的脚本在 `--script` 模式下会
`Compile Error: Identifier not found`。**这类测试必须用场景模式跑**。

### 4.4 Godot 会剥掉 `project.godot` 段落里的注释
只保留文件头自带的 7 行。写在 `[display]` 里的说明会在下次编辑器保存时**静默消失**。
→ **理由写进 DESIGN.md，`project.godot` 里只留数值。**（同理，`aspect="keep"` 等于默认值也会被删，不代表没生效。）

### 4.5 字段不在 `.tres` 里 ≠ 没设置
Godot 序列化时**省略等于类默认值的字段**。
例如 `hero_ninja.tres` 里看不到 `sprite_scale`，但它的真实值来自
`CharacterData` 的默认值 `1.0`。**别凭"文件里没这一行"判断取值**，用测试或 `ProjectSettings`/`load()` 验证。

### 4.6 UI：零尺寸 Control + 底部锚点 = 画到屏幕外
新建 `Control` 尺寸是 `(0,0)`，只写 `set_anchors_preset(PRESET_BOTTOM_WIDE)` 的话，
矩形会从 `y=视口高` **往下长**，整行画在屏幕外，**不报错、不留日志**。
正确写法：全屏 `MarginContainer` + 子 `VBoxContainer` 且 `size_flags_vertical = SIZE_SHRINK_END`。
已有测试守住（HUD 全部文字控件必须在视口内）。

### 4.7 非正方形帧必须显式配 `frame_count`
这是**唯一一次真实美术事故**的根因：曾假设"帧是正方形 → 帧数 = 宽 ÷ 高"，
把 2048×128（每帧 256×128，8 帧）算成 16 帧，每帧被劈成两半，角色"只剩半个身体"。
**永远显式写帧数**，别推断。

### 4.8 `animation_speed` 必须固定 1.0
若同时设 `animation_speed` 与逐帧 `duration`，速度会被**平方**（实测 123 fps 想显示 11）。
`SpriteAnimator.build_sprite_frames()` 已硬设 1.0，速度只由逐帧 duration 决定。

### 4.9 一次性动画（攻击/受击/换弹）不要各自加计时器
必须共用一套 `_oneshot_timer` + "播放期间不被移动动画覆盖"的锁。
否则两个计时器互相顶掉，动画刚播一帧就没了（这个 bug 真实存在过）。

### 4.10 `revive_full()` 会清掉 `invulnerable`
`HealthComponent.revive_full()` 结尾有 `invulnerable = false`。
所以"复活前先设无敌来保护观测窗口"是无效的 —— 想拿复活血量请用 `health_changed` 信号捕获。

### 4.11 改视口 = 改整个世界尺度
当前：视口 **1536×960**、瓦片 **64px**、单位显示 **128px**。
所有空间量（距离/速度/半径/碰撞体/地图坐标）都由
`tools/gen_art_resources.gd` 的常量 `S = 4.0` 统一乘出来（写 `92.0 * S` 而不是 `368.0`）。
**体力/伤害/时间不缩放**（抽象量，缩放会改平衡）。
改完必须重跑三个套件；精灵测试里有一条断言"所有单位显示尺寸必须都是 128px"守着。

### 4.12 网络：HTTPS 443 被墙
`git push` 走 HTTPS 会 `Failed to connect to github.com port 443`。
已改用 **SSH**（`git@github.com:...`），SSH 22 可用。
建议每次 push 前设：
```powershell
$env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"
```

### 4.13 Git LFS 已启用
`png/jpg/wav/ogg/mp3/ttf` 走 LFS。**不要用 PowerShell 管道写二进制**（会损坏），
取二进制请用 `git checkout <ref> -- <path>`。

### 4.14 别重复做已经做过的事
- **美术批次一、二已全部接入**（三段连招 / 重装敌人 / 受击 / 命中特效 / 据点三态 / ST 主角 / 塔呼吸帧）
- 分支 `feat/art-integration`、`origin/art/m1-batch2` **都已并入 main**
- ⚠️ `origin/art/m1-assets` 是**基于旧 main 的废弃平行分支**（领先 main 1 个提交但内容已被取代），
  **不要合并它**，建议删掉以免接错

---

## 5. 下一步要做什么

当前状态：M0 ✅、M1 ✅（含原 M3 复活）、美术 ✅。

**M2 剩余（最小、建议先做）**：塔可被摧毁 → 局内资源重建 + 远程敌人拆塔。
架构已就绪（`BattleState.destroyed_tower_slots`、`BattleEconomy`、伤害矩阵），
缺的是"塔血归零 → 塔位空置 → 下一波付费重建"这条链路。

之后按 DESIGN.md §18 推进（**里程碑表已重排，含两个计划外缺口**）：
- **主角技能**（Q/E/R + Space 冲刺）—— 输入已映射但完全没实现，原计划漏了它
- **控制塔 + Buff/Debuff 系统** —— 塔的三职能里"控制"是空的，§8 也没里程碑
- 关卡结构（多关卡/选人/布防界面）、局外系统、塔合成/星级、打磨

---

## 6. 协作偏好（用户明确表达过的）

- **先架构后代码**：先对齐设计再动手，不要一上来写实现
- **要实测证据，不要"应该可以"**：说"通过"必须附上跑出来的数字/输出
- **不要为了修一个窄问题而砍掉功能**：先定位真正的约束
- **占位不阻塞**：美术分批交付，缺素材时优雅回退（不要因为缺图停摆）
- **`main` 必须随时可运行**
- **提交按逻辑分批**，每次提交后本地与远端一致、工作区干净
- 改完必须自测并如实报告（包括自己犯的错）
