"""
Pathfinding algorithms — mod-accurate default + classic alternatives.

Default: SmallFind-style A* (cloned from YoitaAI FindPath.lua)
  - 8-directional, diagonal cost = sqrt(2) * NODE_SIZE
  - 5-ray collision penalty (0/1/2 hits → increasing cost, 3+ → blocked)
  - Octile heuristic

Alternatives: SimpleA*, BFS, GreedyBestFirst, JumpPointSearch
"""

import math
from collections import deque
from .heap import MinHeap
from .spatial import raytrace5
from config import RAYTRACE_BLOCK_THRESHOLD

# ═══════════════════════════════════════════════════════════════
#  Shared helpers (matching YoitaAI mod constants)
# ═══════════════════════════════════════════════════════════════

NODE_SIZE = 8  # matches YoitaAI node_size — spacing between sample points

# Ray penalty table (mod-accurate)
_RAY_LOSS = {
    0: 0,           # perfect
    1: NODE_SIZE / 0.5,   # 16 — acceptable but costly
    2: NODE_SIZE / 0.1,   # 80 — barely passable
    # 3+ → blocked (returned separately)
}

_BLOCKED_COST = NODE_SIZE / 0.00001  # effectively infinite


def _grid_neighbors_8(world, node):
    """8-directional neighbors, blocking diagonal corner-cutting."""
    x, y = node
    result = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nx, ny = x + dx, y + dy
            if world.is_walkable(nx, ny):
                if dx != 0 and dy != 0:
                    if not world.is_walkable(x + dx, y) and not world.is_walkable(x, y + dy):
                        continue
                result.append((nx, ny))
    return result


def _grid_neighbors_4(world, node):
    """4-directional neighbors only."""
    x, y = node
    result = []
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        nx, ny = x + dx, y + dy
        if world.is_walkable(nx, ny):
            result.append((nx, ny))
    return result


def _cost_mod(from_node, to_node, world, collect_rays):
    """
    Mod-accurate cost: NODE_SIZE base + ray penalty.
    Diagonal: sqrt(2)*NODE_SIZE instead of NODE_SIZE.
    """
    dx = abs(to_node[0] - from_node[0])
    dy = abs(to_node[1] - from_node[1])
    is_diag = (dx + dy == 2)
    base = NODE_SIZE * math.sqrt(2) if is_diag else NODE_SIZE

    count, rays = raytrace5(world, from_node, to_node)
    if collect_rays is not None:
        collect_rays.extend(rays)

    if count >= RAYTRACE_BLOCK_THRESHOLD:
        return _BLOCKED_COST

    return base + _RAY_LOSS.get(count, 0)


def _octile_heuristic(a, goal):
    """Octile distance — admissible for 8-direction grid."""
    dx = abs(a[0] - goal[0])
    dy = abs(a[1] - goal[1])
    return max(dx, dy) + (math.sqrt(2) - 1) * min(dx, dy)


def _manhattan(a, goal):
    return abs(a[0] - goal[0]) + abs(a[1] - goal[1])


# ═══════════════════════════════════════════════════════════════
#  Algorithm 1: Mod-Accurate A* (DEFAULT)
#  Cloned from YoitaAI FindPath.lua SmallFind
# ═══════════════════════════════════════════════════════════════

def pathfind_mod(world, start, goal, collect_rays=None):
    """
    Mod-accurate A*: matches YoitaAI SmallFind.
    - 8-directional, NODE_SIZE-weighted diagonal
    - 5-ray collision penalty
    - Octile heuristic
    """
    open_set = MinHeap()
    closed_set = set()
    g_score = {start: 0.0}
    parent = {}

    f_start = g_score[start] + _octile_heuristic(start, goal) * NODE_SIZE
    open_set.push(f_start, start)

    while not open_set.is_empty():
        curr = open_set.pop()
        if curr is None:
            break
        if curr in closed_set:
            continue

        if curr == goal:
            return _reconstruct(parent, curr)

        closed_set.add(curr)

        for nb in _grid_neighbors_8(world, curr):
            if nb in closed_set:
                continue
            cost = _cost_mod(curr, nb, world, collect_rays)
            if cost >= _BLOCKED_COST:
                continue

            g_new = g_score[curr] + cost
            if nb not in g_score or g_new < g_score[nb]:
                parent[nb] = curr
                g_score[nb] = g_new
                f = g_new + _octile_heuristic(nb, goal) * NODE_SIZE
                open_set.push(f, nb)

    return None  # no path


# ═══════════════════════════════════════════════════════════════
#  Algorithm 2: Simple A* (uniform cost, no ray collision)
# ═══════════════════════════════════════════════════════════════

def pathfind_astar(world, start, goal):
    """Classic A* — 8-directional, uniform edge cost, diagonal=√2."""
    open_set = MinHeap()
    closed_set = set()
    g_score = {start: 0.0}
    parent = {}

    f_start = g_score[start] + _octile_heuristic(start, goal)
    open_set.push(f_start, start)

    while not open_set.is_empty():
        curr = open_set.pop()
        if curr is None:
            break
        if curr in closed_set:
            continue

        if curr == goal:
            return _reconstruct(parent, curr)

        closed_set.add(curr)

        for nb in _grid_neighbors_8(world, curr):
            if nb in closed_set:
                continue
            dx = abs(nb[0] - curr[0])
            dy = abs(nb[1] - curr[1])
            step_cost = 1.414 if dx + dy == 2 else 1.0

            g_new = g_score[curr] + step_cost
            if nb not in g_score or g_new < g_score[nb]:
                parent[nb] = curr
                g_score[nb] = g_new
                f = g_new + _octile_heuristic(nb, goal)
                open_set.push(f, nb)

    return None


# ═══════════════════════════════════════════════════════════════
#  Algorithm 3: BFS (unweighted, 4-directional, guaranteed shortest)
# ═══════════════════════════════════════════════════════════════

def pathfind_bfs(world, start, goal):
    """
    Breadth-First Search — 4-directional only.
    Guarantees shortest path in number of steps (unweighted).
    """
    queue = deque([start])
    visited = {start}
    parent = {}

    while queue:
        curr = queue.popleft()

        if curr == goal:
            return _reconstruct(parent, curr)

        for nb in _grid_neighbors_4(world, curr):
            if nb not in visited:
                visited.add(nb)
                parent[nb] = curr
                queue.append(nb)

    return None


# ═══════════════════════════════════════════════════════════════
#  Algorithm 4: Greedy Best-First Search
# ═══════════════════════════════════════════════════════════════

def pathfind_greedy(world, start, goal):
    """
    Greedy Best-First — uses ONLY heuristic, ignores path cost.
    Very fast but NOT guaranteed optimal.
    """
    open_set = MinHeap()
    closed_set = set()
    parent = {}

    h = _octile_heuristic(start, goal)
    open_set.push(h, start)

    while not open_set.is_empty():
        curr = open_set.pop()
        if curr is None:
            break
        if curr in closed_set:
            continue

        if curr == goal:
            return _reconstruct(parent, curr)

        closed_set.add(curr)

        for nb in _grid_neighbors_8(world, curr):
            if nb in closed_set:
                continue
            if nb not in parent:  # first-come, no update
                parent[nb] = curr
                h = _octile_heuristic(nb, goal)
                open_set.push(h, nb)

    return None


# ═══════════════════════════════════════════════════════════════
#  Algorithm 5: Jump Point Search (JPS)
# ═══════════════════════════════════════════════════════════════

def pathfind_jps(world, start, goal):
    """
    Jump Point Search — prunes symmetric paths on uniform-cost grid.
    Only expands "jump points" — nodes where the optimal path changes
    direction.  10-30x fewer expansions than A* on open terrain.

    Uses diagonal-first pruning: jump in all 8 directions from each
    node, only stop at obstacles, forced neighbors, or the goal.
    """
    open_set = MinHeap()
    closed_set = set()
    g_score = {start: 0.0}
    parent = {}

    open_set.push(_octile_heuristic(start, goal), start)

    while not open_set.is_empty():
        curr = open_set.pop()
        if curr is None:
            break
        if curr in closed_set:
            continue
        if curr == goal:
            return _reconstruct(parent, curr)

        closed_set.add(curr)

        # Identify successors via jumping in all 8 directions
        successors = _jps_successors(world, curr, goal, closed_set)

        for nb in successors:
            if nb in closed_set:
                continue
            dx = abs(nb[0] - curr[0])
            dy = abs(nb[1] - curr[1])
            step_cost = 1.414 if dx + dy == 2 else 1.0

            # Compute actual cost along the jumped path via octile distance
            g_new = g_score[curr] + _octile_heuristic(curr, nb)

            if nb not in g_score or g_new < g_score[nb]:
                parent[nb] = curr
                g_score[nb] = g_new
                f = g_new + _octile_heuristic(nb, goal)
                open_set.push(f, nb)

    return None


def _jps_successors(world, node, goal, closed_set):
    """Find all jump-point successors from `node` in 8 directions."""
    result = []
    x, y = node
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            jp = _jump(world, x, y, dx, dy, goal)
            if jp is not None and jp not in closed_set:
                result.append(jp)
    return result


def _jump(world, cx, cy, dx, dy, goal):
    """
    Jump from (cx,cy) in direction (dx,dy).
    Returns furthest walkable jump point, or None if blocked.
    """
    x, y = cx, cy
    while True:
        x += dx
        y += dy
        if not world.is_walkable(x, y):
            return None  # hit wall
        # Corner-cutting prevention (same as _n8 check)
        if dx != 0 and dy != 0:
            if not world.is_walkable(x - dx, y) and not world.is_walkable(x, y - dy):
                return None
        if (x, y) == goal:
            return (x, y)

        if dx != 0 and dy != 0:
            # Diagonal: check if straight components are blocked -> forced neighbor
            blocked_h = not world.is_walkable(x - dx, y)
            open_h = world.is_walkable(x + dx, y)
            blocked_v = not world.is_walkable(x, y - dy)
            open_v = world.is_walkable(x, y + dy)
            if (blocked_h and open_h) or (blocked_v and open_v):
                return (x, y)
            # Also check if straight jumps from here would find anything
            if _jump_straight(world, x, y, dx, 0, goal) or \
               _jump_straight(world, x, y, 0, dy, goal):
                return (x, y)
        else:
            # Straight: stop at any forced neighbor
            if _forced_straight(world, x, y, dx, dy):
                return (x, y)

    return None


def _jump_straight(world, x, y, dx, dy, goal):
    """Jump straight; returns furthest point before obstacle or None."""
    cx, cy = x, y
    while True:
        cx += dx
        cy += dy
        if not world.is_walkable(cx, cy):
            return None
        if (cx, cy) == goal:
            return (cx, cy)
        if _forced_straight(world, cx, cy, dx, dy):
            return (cx, cy)
    return None


def _forced_straight(world, x, y, dx, dy):
    """Check for forced neighbors on straight moves."""
    if dx != 0:  # horizontal
        for sy in (-1, 1):
            if not world.is_walkable(x, y + sy) and world.is_walkable(x + dx, y + sy):
                return True
    if dy != 0:  # vertical
        for sx in (-1, 1):
            if not world.is_walkable(x + sx, y) and world.is_walkable(x + sx, y + dy):
                return True
    return False


# ═══════════════════════════════════════════════════════════════
#  Utility
# ═══════════════════════════════════════════════════════════════

def _reconstruct(parent, node):
    """Reconstruct path from goal back to start."""
    path = []
    while node is not None:
        path.append(node)
        node = parent.get(node)
    path.reverse()
    return path


# ═══════════════════════════════════════════════════════════════
#  Algorithm 6: Weighted A* (terrain-aware)
# ═══════════════════════════════════════════════════════════════

# Diagonal penalty
_WEIGHT_COST = {
    (-1, -1): 1.5, (0, -1): 1, (1, -1): 1.5,
    (-1,  0): 1,                (1,  0): 1,
    (-1,  1): 1.5, (0,  1): 1, (1,  1): 1.5,
}


def pathfind_weighted(world, start, goal):
    """
    Weighted A* — orthogonal=1, diagonal=1.5, ground bonus -0.7.

    Walking on solid ground costs 0.3/step (cheap).
    Moving through air costs 1.0-1.5/step (normal).
    Naturally biases paths toward the floor without forced post-processing.
    """
    GROUND_BONUS = 0.7
    open_set = MinHeap()
    closed_set = set()
    g_score = {start: 0.0}
    parent = {}

    open_set.push(_octile_heuristic(start, goal), start)

    while not open_set.is_empty():
        curr = open_set.pop()
        if curr is None: break
        if curr in closed_set: continue
        if curr == goal:
            return _reconstruct(parent, curr)

        closed_set.add(curr)

        for nb in _grid_neighbors_8(world, curr):
            if nb in closed_set: continue
            dx = nb[0] - curr[0]
            dy = nb[1] - curr[1]
            step_cost = _WEIGHT_COST.get((dx, dy), 1.0)
            # Solid ground below = discount
            if not world.is_walkable(nb[0], nb[1] + 1):
                step_cost = max(0.1, step_cost - GROUND_BONUS)

            g_new = g_score[curr] + step_cost
            if nb not in g_score or g_new < g_score[nb]:
                parent[nb] = curr
                g_score[nb] = g_new
                open_set.push(g_new + _octile_heuristic(nb, goal), nb)

    return None


def _gravity_drop(world, path):
    """
    Drop each path node onto the surface below, then reconnect gaps.

    1. Keep start/goal fixed in place.
    2. For each intermediate node: while cell below is walkable, move down.
    3. Scan for non-adjacent consecutive nodes (gaps from differential drop).
    4. Fill gaps with 8-directional mini-BFS.
    """
    if len(path) < 2:
        return path

    # Step 1: drop intermediate nodes (keep start/goal)
    dropped = [path[0]]
    for node in path[1:-1]:
        x, y = node
        while world.is_walkable(x, y + 1):
            y += 1
        dropped.append((x, y))
    dropped.append(path[-1])

    # Step 2: reconnect gaps (8-dir adjacency check)
    result = [dropped[0]]
    for i in range(1, len(dropped)):
        prev = result[-1]
        curr = dropped[i]
        if max(abs(curr[0] - prev[0]), abs(curr[1] - prev[1])) > 1:
            # Gap detected — fill with mini pathfind
            filler = _mini_pathfind(world, prev, curr)
            if filler and len(filler) > 2:
                result.extend(filler[1:-1])  # exclude endpoints (already in result)
        result.append(curr)

    return result


def _mini_pathfind(world, a, b):
    """8-directional BFS from a to b. Returns path or None."""
    from collections import deque
    q = deque([a])
    came_from = {a: None}
    while q:
        node = q.popleft()
        if node == b:
            path = []
            while node is not None:
                path.append(node)
                node = came_from[node]
            path.reverse()
            return path
        for nb in _grid_neighbors_8(world, node):
            if nb not in came_from:
                came_from[nb] = node
                q.append(nb)
    return None


# ═══════════════════════════════════════════════════════════════
#  Algorithm registry
# ═══════════════════════════════════════════════════════════════

ALGORITHMS = {
    "mod":    ("1.Mod-Accurate A*",   pathfind_mod),
    "astar":  ("2.Simple A*",         pathfind_astar),
    "bfs":    ("3.BFS",               pathfind_bfs),
    "greedy": ("4.Greedy Best-First", pathfind_greedy),
    "jps":    ("5.Jump Point Search", pathfind_jps),
    "weight": ("6.Weighted A*",         pathfind_weighted),
}

DEFAULT_ALGO = "mod"
