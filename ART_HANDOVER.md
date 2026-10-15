# 美术交接文档

> 配套正式仓库的 `ART_SPEC.md` 阅读。
> 本文档说明**美术侧交付了什么、放在哪、怎么接、有哪些和原规格不同**。
>
> 交付日期：2026-10-15 ｜ 面向：程序侧 / 策划

---

## 一、交付清单

> ⚙️ **本表由 `tools/_dump_delivery_table.gd` 从工程实际资源读出后自动生成，不要手改。**
> 手写版曾经严重落后（主角还写着已被替换掉的 8 帧两段攻击）。资源变了就重跑一次、重新粘进来。

| 文件 | 用途 | 画布/帧 | 帧数 | 帧率 | 循环 | 显示 |
|---|---|---|---|---|---|---|
| `enemies/melee_brute_idle.png` | idle | 32×32 | 1 | 5.0 fps | ✅ | ×4 |
| `enemies/melee_brute_run.png` | run | 64×32 | 7 | 8.0 fps | ✅ | ×4 |
| `enemies/melee_brute_attack.png` | attack | 64×32 | 13 | 10.0 fps | ❌ | ×4 |
| `enemies/melee_brute_hurt.png` | hurt | 32×32 | 2 | 12.0 fps | ❌ | ×4 |
| `enemies/melee_grunt_idle.png` | idle | 32×32 | 1 | 5.0 fps | ✅ | ×4 |
| `enemies/melee_grunt_run.png` | run | 32×32 | 5 | 10.0 fps | ✅ | ×4 |
| `enemies/melee_grunt_attack.png` | attack | 32×32 | 5 | 12.0 fps | ❌ | ×4 |
| `enemies/melee_grunt_hurt.png` | hurt | 32×32 | 2 | 12.0 fps | ❌ | ×4 |
| `hero/ninja_idle.png` | idle | 128×128 | 4 | 8.0 fps | ✅ | ×1 |
| `hero/ninja_run.png` | run | 128×128 | 8 | 11.11 fps | ✅ | ×1 |
| `hero/ninja_attack_1.png` | attack_1 | 384×256 | 4 | 12.0 fps | ❌ | ×1 |
| `hero/ninja_attack_2.png` | attack_2 | 384×256 | 4 | 12.0 fps | ❌ | ×1 |
| `hero/ninja_attack_3.png` | attack_3 | 384×256 | 5 | 12.0 fps | ❌ | ×1 |
| `hero/ninja_hurt.png` | hurt | 128×128 | 2 | 12.0 fps | ❌ | ×1 |
| `enemies/ranged_archer_idle.png` | idle | 32×32 | 1 | 5.0 fps | ✅ | ×4 |
| `enemies/ranged_archer_run.png` | run | 32×32 | 16 | 20.0 fps | ✅ | ×4 |
| `enemies/ranged_archer_attack.png` | attack | 32×32 | 7 | 12.0 fps | ❌ | ×4 |
| `enemies/ranged_archer_reload.png` | reload | 32×32 | 7 | 10.0 fps | ❌ | ×4 |
| `enemies/ranged_archer_hurt.png` | hurt | 32×32 | 2 | 12.0 fps | ❌ | ×4 |
| `towers/tower_archer_idle.png` | idle | 64×64 | 1 | 5.0 fps | ✅ | ×2 |
| `towers/tower_healer_idle.png` | idle | 64×64 | 1 | 5.0 fps | ✅ | ×2 |
| `effects/fx_slash_red.png` | 特效 | 32×32 | 3 | 16.0 fps | ❌ | ×4 |
| `props/base.png` | 场景 / 道具 | 256×256 | — | — | — | 底边=地面线 |
| `tilesets/tile_concrete_01.png` | 地形 | 64×64 | — | — | — | ×4 |
| `tilesets/tile_concrete_04.png` | 地形 | 64×64 | — | — | — | ×4 |
| `tilesets/tile_grass_01.png` | 地形 | 64×64 | — | — | — | ×4 |
| `tilesets/tile_grass_02.png` | 地形 | 64×64 | — | — | — | ×4 |
| `tilesets/tile_grass_03.png` | 地形 | 64×64 | — | — | — | ×4 |
| `tilesets/tile_grate_01.png` | 地形 | 64×64 | — | — | — | ×4 |
| `tilesets/tile_path_01.png` | 地形 | 64×64 | — | — | — | ×4 |
| `ui/marker_tower_a_blocked.png` | UI | 128×128 | — | — | — | ×2 |
| `ui/marker_tower_a_bracket.png` | UI | 128×128 | — | — | — | ×2 |

**说明**

- `画布/帧` 是**单帧画布**尺寸，同一张 spritesheet 内所有帧等大（§15.4 铁律）
- `显示` 是该角色在游戏里的渲染倍率：**主角 ×1 / 塔 ×2 / 敌人 ×4** ——
  都是为了让单位渲染成 **128 游戏像素**（2×2 格）
- 主角三段的画布是 **384×256**（128 装不下挥剑弧线），显示仍是 **×1**，锚点见第四节
- 调色板 `assets/palette/td_art.gpl` 覆盖上表全部素材

## 二、⚠️ 与 `ART_SPEC.md` 的差异（**接入前务必先看这节**）

| 项 | `ART_SPEC.md` 原规格 | 我们实际 | 原因 |
|---|---|---|---|
| **基准分辨率** | 480×320 | **1920×1280** | 单位要有细节，世界整体 ×4 |
| **地形瓦片** | 16×16 | **64×64** | 同上，×4 |
| **单位画布** | 统一 32×32 | **128 / 64 / 32 混用** | 见第三节 |
| **像素密度** | 隐含统一 | **刻意不统一** | 精细主角 + 块状杂兵 |
| `run` 帧数 | 6 | 5 ~ 16 | 按素材质量择优，不是统一值 |
| `idle` 帧数 | 4 | 主角 4 ✅ / 其他 1 | 其他角色的呼吸帧还在补 |

---

## 三、尺寸与像素密度（最需要理解的一节）

**每个单位在游戏内都渲染成 128×128 = 2×2 格**，但它们的**源生画布不同**：

| 类别 | 源生画布 | 显示倍率 | 美术像素在屏幕上 |
|---|---|---|---|
| 主角 | 128 | ×1 | **1 游戏像素** |
| 塔 | 64 | ×2 | **2 游戏像素** |
| 敌人 | 32 | ×4 | **4 游戏像素** |

所以同屏会有**三种像素密度**。这是**刻意的风格选择**：

- 主角是玩家一直盯着的角色，要精细
- 塔是建筑，细节多一点自然
- 杂兵数量多，粗块反而更好辨识、也更省

> 如果程序侧觉得三种倍率麻烦，可以统一成"**所有单位都用 128×128 画布**"：
> 塔 ×2、敌人 ×4 预先放大好再交。这样精灵节点 `scale` 恒为 1，代价是文件体积变大
> （美术像素大小不变，观感完全一样）。**这个可以按你们方便来定。**

---

## 四、锚点约定

| 画布 | 脚底基准行 | 水平 |
|---|---|---|
| 128×128 | **第 122 行** | 画布中心 |
| 64×64 | **第 61 行** | 画布中心 |
| 32×32 | **第 30 行** | 画布中心 |

- 这三行是**等比的**（都距底边约 4.7%），所以三种密度下角色站在同一条地面线上。
- **帧内不允许有像素低于脚底基准行**（会穿地）。已全量校验，全部达标。
- 播放时把精灵的**锚点放在脚底基准行**，就能和瓦片网格对齐。

---

## 五、接入步骤（程序侧）

### 5.1 因为基准变成 ×4，数值要跟着放大

`resources/**/*.tres` 里的**距离与速度全部 ×4**。例如：

| 字段 | 现值 | 应改为 |
|---|---|---|
| `move_speed` | 36.0 | 144.0 |
| `attack_range` | 26.0 | 104.0 |
| `hero_detect_radius` | 76.0 | 304.0 |
| `waypoint_reach_radius` | 4.0 | 16.0 |

> 这些数按仓库 480×320 / 16px 瓦片定的，现在是 1920×1280 / 64px 瓦片。
> 机械操作，但**漏一个就是静默的平衡 bug**，改完一定要跑冒烟测试。

### 5.2 地图 Marker 位置 ×4

`scenes/battle/map/test_level.tscn` 里 `map_hero_start` / `map_spawn` / `map_waypoint` /
`map_tower_slot` 这些 Marker2D 的 position 全部 ×4，否则会全挤在角落。
`test_level_map.gd` 的调试绘制如涉及硬编码坐标也要跟着改。

### 5.3 单位场景加 `AnimatedSprite2D`

目前 `scripts/battle/entities/hero_unit.gd` 的 `_draw()` 画的是 **14px 纯色方块**占位，
场景里**没有精灵节点**。需要加 `AnimatedSprite2D` 来挂 SpriteFrames。

### 5.4 `CharacterData` 加贴图字段

`scripts/data/character_data.gd` 目前**没有任何贴图字段**。
需要加一个（例如 `@export var frames: SpriteFrames`），才能把上面这些 spritesheet 挂到
`resources/characters/*.tres` 和 `resources/enemies/*.tres` 上。

### 5.5 跑冒烟测试

`tests/battle_smoke_test.tscn`（35 项）—— ×4 改完后这是唯一能兜住"漏改了哪里"的安全网。

---

## 六、素材来源

| 素材 | 状态 |
|---|---|
| 主角 **ninja**、备用 **ss_angel** | ✅ 原创赛博角色，AI 辅助生成 + 多轮手工调整后定稿 |
| 塔（两只猫）、敌人（机甲）、地形、UI | ✅ 原创 |

视觉语言（深蓝黑描边、青/品红/黄绿霓虹、冷灰金属、满明度范围）见 `STYLE.md`，
新角色继续沿用即可。

---

## 七、怎么验收

美术侧有一个**独立实验工程**，可以在**和正式工程一致的渲染基线**下逐张检查：

- 位置：`D:\nsgame\godotgame\demo`（Godot 4.7.2 打开，按 F5）
- 功能：按角色/动画切帧播放、缩放 ×1~×6、叠加参考线（画布边框 / 16px 与 64px 网格 /
  **脚底基准线** / 原点 / 仓库基准视口框）
- 右栏会**实时报告当前帧的色数**和**有多少颜色不在共享调色板里** ——
  绿色的 `all in palette` 才算通过

---

## 八、未完成 / 后续

| 优先级 | 项目 |
|---|---|
| 🟢 | `melee_brute`（近战重装敌人）的 `idle` + `run` （整个角色还没做） |
| 🟢 | UI 图标 / 技能图标 |
| ⚪ | 死亡消失特效 `fx_death_burst`（美术侧暂缓） |
| — | 其他角色的 idle 呼吸帧（现在多是 1 帧） |
| — | 塔的 `attack` / `heal` —— **已决定不做**，塔的行为用特效代替 |
| ✅ | ~~大本营~~ 已完成（`assets/props/base/`） |
| ✅ | ~~主角原创化~~ 已完成（见第六节） |

**待策划确认**：

- ninja 在 roster 里是什么定位？（仓库现有 `hero_knight`，和我们这两个对不上）
- 塔的正式 ID 就是 `tower_archer` / `tower_healer` 吗？
- 硬币（已归档，未进项目）要用在哪、显示多大？
- **`healerrobot`（医疗机器人）在 roster 里是什么定位？** 仓库现有 `tower_healer` 已经是治疗塔，所以它应该是别的位置
