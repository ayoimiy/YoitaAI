# 代码审查报告

> 日期：2026-06-27  
> 审查分支：`dongmuyu-dev`  
> 审查范围：全部 Lua 源文件

---

## 🔴 严重问题

### 1. `init.lua:128` — 调试守卫阻断了全部渲染逻辑

```lua
if true then return end    -- 第128行
end                        -- 第129行
```

`OnWorldPreUpdate()` 在显示模式切换处理后无条件 `return`，导致：

- 第 128 行之后的所有代码永久不执行
- `Display_pos_table` 函数（133-137 行）成为死代码
- 所有节点的可视化精灵不会在屏幕上渲染

**修复**：删除 `if true then return end` 这一调试残留。

---

### 2. `move.lua:57` — 距离比较单位不一致

```lua
local dist = (x - target.x)^2 + (y - 4 - target.y)^2   -- 计算的是平方距离
if dist < self.max_dist then                             -- max_dist = 75（线性阈值）
```

二次方距离与线性阈值 `75` 比较，实际到达判定半径仅 `√75 ≈ 8.6` 像素，而不是预期的 75 像素。

**修复**：将 `max_dist` 改为 `75 * 75 = 5625`，或对 `dist` 做 `math.sqrt` 后再比较。

---

## 🟡 重要问题

### 3. `kick.lua` — `Kick_book` 与 `kick_book360` 代码完全重复

`Kick_book`（8-55 行）与 `kick_book360`（58-105 行）逻辑 99% 相同，仅函数名不同。

**修复**：合并为单一函数，如需区分模式可通过参数控制。

---

### 4. `ai_movement_utilities.lua` — 未被使用的独立寻路实现

该文件实现了一套完整的 A* 寻路系统（`FindPath.find`，136 行），包含八方向邻居搜索、五射线碰撞检测、路径平滑等。但**没有任何模块引用它** — `init.lua` 实际使用的是 `files/scripts/memory/FindPath.lua`。

**修复**：确认是否需要保留。如不需要则删除以降低维护成本；如需保留则明确其用途注释。

---

### 5. `manager2.lua` — 空文件

文件仅 1 行，无任何有效代码。

**修复**：删除或用实际内容填充。

---

### 6. `FindPath.lua:411` — 同名函数多份实现

```lua
Move_no_path(player)  -- 调用 FindPath.lua 内部的 local 函数（第75行）
```

同时 `files/scripts/action/move.lua` 中存在另一个 `Move:Move_no_path`，功能相同、实现不同。两套"停止移动"逻辑并存。

**修复**：统一为一个公共模块，消除冗余。

---

### 7. `manager.lua:349` — BFS 使用 `table.remove(queue, 1)` 导致 O(n²) 开销

```lua
local node = table.remove(queue, 1)  -- 每次弹出需移动所有后续元素
```

当 BFS 处理数百个节点时，频繁的 `table.remove` 会造成大量内存拷贝。

**修复**：改用队列头索引指针：

```lua
local head = 1
local node = queue[head]
head = head + 1
```

---

### 8. `state_manager.lua:164` — 每帧执行全局实体查询

```lua
local player_entity = EntityGetWithTag("player_unit")[1]
```

`apply_controls()` 每帧调用都会执行昂贵的全局实体搜索。

**修复**：在初始化时缓存玩家实体引用，通过 `OnPlayerSpawned` 传入。

---

## 🔵 次要问题

### 9. `init.lua:28-32` — 变量名遮蔽（shadowing）

```lua
local cx, cy = GameGetCameraPos()
local cx = cx - cw / 2   -- cx 被重新声明，遮蔽了上一行的 cx
local cy = cy - ch / 2   -- 同上
```

虽计算结果碰巧正确，但这种写法极易引发理解和维护错误。

**修复**：使用不同变量名，如 `origin_x`、`origin_y`。

---

### 10. `SetTimeOut.lua:53` — 导出单例而非类

```lua
return STOut:new()  -- 返回实例，不是类
```

全局共享一个定时器实例。如果未来模块需要独立定时器，当前设计不支持。

**修复**：将 `init.lua` 中的引用方式改为 `STOut:new()` 创建独立实例，或同时导出类和单例。

---

### 11. 五射线检测逻辑在三处重复

同一逻辑在以下位置各实现了一遍：

| 位置 | 函数名 |
|------|--------|
| `manager.lua:307-322` | `raytrace5` |
| `FindPath.lua:279-293` | `Raytrace5check` |
| `ai_movement_utilities.lua:103-131` | 内联在 `get_cost` 中 |

**修复**：提取为公共工具函数，注册到 `files/utils/`。

---

### 12. `manager.lua:280` — `decode_edge_key` 无条件遍历全部四条边

即使调用时传入了目标方向（`dir` 参数），函数仍遍历上/下/左/右全部四条边的所有节点。

**修复**：当 `dir` 不为 nil 时仅解码对应方向的边。

---

## 📊 统计

| 级别 | 数量 | 影响 |
|------|------|------|
| 🔴 严重 | 2 | 功能阻断、逻辑错误 |
| 🟡 重要 | 6 | 冗余、性能、可维护性 |
| 🔵 次要 | 4 | 代码质量、风格 |

---

*审查基于 `dongmuyu-dev` 分支，commit `da2dbfa`。*
