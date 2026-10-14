# Tower Defence

2D 像素风闯关塔防游戏。

---

## ⚠️ 环境要求（必须一致）

| 项 | 要求 |
|---|---|
| **Godot** | **4.7.2 stable**（严格一致，不要用 4.6 / 4.8） |
| **Git + Git LFS** | 素材是二进制，必须装 `git-lfs` |
| 平台 | Windows（当前开发环境） |

> **为什么版本必须一致**：`.tscn` / `.import` 的文件格式在小版本间会有差异，
> 用不同版本打开会产生大量莫名其妙的冲突，而且很难排查。

Godot 下载：<https://godotengine.org/download/>

---

## 快速开始

```powershell
# 1. 克隆
git clone https://github.com/YYMC108/Tower-Defence.git
cd Tower-Defence

# 2. 启用 Git LFS（必须在拉取素材 / 提交素材之前）
git lfs install --local
git lfs pull

# 3. 确认 git-lfs 已装
git lfs version

# 4. 用 Godot 4.7.2 打开这个目录（不是打开单个场景文件）
```

首次打开时 Godot 会自动导入素材并生成 `.import` 文件与 `.godot/` 缓存，属正常现象。

### 验证工程配置是否完好

改过 `project.godot` 之后（或换了新机器之后）跑一次：

```powershell
godot --headless --path . --script res://tests/check_project_config.gd
```

**退出码 0 = 全部通过**。详见 [tests/README.md](tests/README.md)。

---

## 当前进度

**M0 · 架构已完成。** 见 [DESIGN.md](DESIGN.md) 第 17 节的里程碑表。

尚未开始 M1（战斗最小闭环），因此**现在还没有主场景**，直接按 F5 会提示
`no main scene defined`——这是预期状态，不是错误。

---

## 文档导航

| 文档 | 内容 |
|---|---|
| **[DESIGN.md](DESIGN.md)** | ⭐ **唯一设计口径**。术语表、伤害矩阵、系统职责、数据模型、协作规范、风险清单 |
| **[ART_SPEC.md](ART_SPEC.md)** | 🎨 **美术规格约定**（尺寸/锚点/动画/命名/交付格式/分工）。**单独发给美术协作者** |
| [tests/README.md](tests/README.md) | 校验脚本怎么跑 |
| 各目录下的 `README.md` | 该目录该放什么 |

> **约定**：代码与 [DESIGN.md](DESIGN.md) 冲突时，以 DESIGN.md 为准。
> 要改设计，请**先改文档再改代码**。

---

## 术语（不要用"回合"）

| 术语 | 含义 |
|---|---|
| **关卡** `Level` | 最大的挑战单位 |
| **波次** `Wave` | 关卡内的一次进攻。塔的摧毁与重生绑定在这个粒度 |
| **阶段** `Phase` | 波次内三态：布防 → 战斗 → 结算 |
| **塔位** `TowerSlot` | 地图上预设的固定防守位置 |
| **星级** `Star` | 塔的强化等级，由多个**副本**合成（本期未实现） |

完整定义见 [DESIGN.md](DESIGN.md) 第 1 节。

---

## 目录结构

```
autoload/     全局单例（局外状态、存档、场景切换、音频）
scenes/       场景装配（谁包含谁）
scripts/      逻辑（规则与算法），与场景文件解耦
resources/    数值配置（.tres）——调平衡改这里，不改代码
assets/       美术与音频源文件
tests/        校验脚本
addons/       第三方插件
```

**分层铁律**：`scenes/` 管装配、`scripts/` 管逻辑、`resources/` 管数值，三者**单向依赖**。
`scripts/data/` 里的东西**绝不能**反过来引用场景。

每个目录内都有 `README.md` 说明该放什么。

---

## 协作规范（要点）

完整版见 [DESIGN.md](DESIGN.md) 第 16 节。

- **动手前先 `git pull`**；改完开分支 + PR，不要直接往 `main` 推
- **每个 `.tscn` 有且只有一个负责人**。两人同时改同一个场景必然冲突
- **美术素材一律走 Git LFS**，不要用微信/网盘"绕过 git"传——那样会让仓库失去唯一性
- **不要在编辑器打开时改 `project.godot`**，Godot 可能会用内存里的版本覆盖
- **程序用占位方块先跑通逻辑，不要等美术**

---

## 已知待办

见 [DESIGN.md](DESIGN.md) 第 18 节的 TODO-1 ~ TODO-9，其中影响手感的关键项：

- **TODO-4**：主角复活惩罚跨波次是否衰减（不衰减可能导致后期死亡螺旋必输）
- **TODO-6**：渲染后端是否从 `forward_plus` + `d3d12` 改为 `gl_compatibility`

---

*本 README 面向"第一次打开这个仓库的人"。设计与规则细节请读 [DESIGN.md](DESIGN.md)。*
