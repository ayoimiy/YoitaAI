# YoitaAI

Noita 游戏 AI 操控 Mod。通过空间记忆与双层 A* 寻路，让 AI 在随机生成的世界中自主导航和战斗。

## 功能

- **双层寻路** — 大寻路（跨区块 Block 级 A\*）+ 小寻路（区块内 8 方向网格 A\*），五射线检测保证路径可行
- **空间记忆** — BFS 连通分量分析 + 边缘指纹哈希，自动识别区块变化并增量更新
- **自主移动** — WASD + 飞行喷射自动控制，检测水中/飞行能量
- **踢击战斗** — 自动锁定最近敌对生物，踢飞 + 投掷石板连招
- **武器管理** — 法杖分类（攻击/传送/好/坏/空），自动切换
- **调试 HUD** — 实时显示坐标、区块、路径节点，可视化寻路过程
- **按键控制** — P 键切换 AI/手动，O 键开关寻路，J 键切换显示模式

## 架构

```
init.lua                     # 主入口：注册玩家、主循环、HUD、按键交互
files/
├── state_manager.lua        # 状态中枢：组件引用、WASD控制、武器分类、血量/法力查询
└── scripts/
    ├── action/
    │   ├── move.lua         # 底层移动：沿路径点逐一导航，到达容差自动推进
    │   └── kick.lua         # 踢击技能：自动瞄准+踢飞+投掷，帧序列编排
    ├── memory/
    │   ├── FindPath.lua     # 双层寻路：BigFind(Block级) + SmallFind(网格级)，卡住检测
    │   ├── manager.lua      # 空间引擎：Chunk扫描、BFS连通分量、边缘指纹、邻居匹配
    │   └── manager2.lua     # manager 实验性分支
    ├── movements/
    │   └── ai_movement_utilities.lua  # 辅助移动工具
    └── utils/
        ├── astar.lua        # 通用A*：配置驱动，最小堆排序，5000次迭代上限
        ├── Heap.lua         # 最小堆（优先队列）
        └── SetTimeOut.lua   # 帧级定时器：类似setTimeout，支持循环调度
```

## 运行

1. 将仓库放入 Noita `mods/` 目录
2. 在游戏中启用 `YoitaAI` Mod
3. 进入游戏后 AI 自动接管，按 **P** 可切回手动操作

## 许可

MIT License
