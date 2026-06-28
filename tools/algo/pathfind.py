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
from .jps import pathfind_jps
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
#  (defined in algo/jps.py — imported above)
# ═══════════════════════════════════════════════════════════════

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
#  Algorithm 6: Weighted A* (terrain-aware, exponential flight fatigue)
# ═══════════════════════════════════════════════════════════════

# Base movement costs
_WEIGHT_COST = {
    (-1, -1): 1.5, (0, -1): 1, (1, -1): 1.5,
    (-1,  0): 1,                (1,  0): 1,
    (-1,  1): 1.5, (0,  1): 1, (1,  1): 1.5,
}

# Exponential flight fatigue — three curves, one counter
_UP_BASE    = 2.0    # upward:  base penalty at air_step=1
_UP_EXP     = 1.30   # upward:  steep exponential
_HORIZ_BASE = 0.5    # horizontal: gentler base
_HORIZ_EXP  = 1.20   # horizontal: slower growth than upward
_DOWN_BASE  = 0.5    # downward: flat component
_DOWN_LINEAR = 0.08  # downward: linear per air_step (nearly flat)

_GROUND_BONUS = 0.7   # subtracted when on solid ground
_LANDING_TAX  = 1.0   # one-time cost: airborne → ground (reduced)
_TAKEOFF_TAX  = 0.5   # one-time cost: ground → upward flight (reduced)


def pathfind_weighted(world, start, goal):
    """
    Weighted A* — terrain-aware with exponential flight fatigue.

    State: (x, y, air_steps)  where air_steps = consecutive air steps.
    Capped at _MAX_AIR to prevent state-space explosion.
    Dominance pruning: (cost, air) — lower cost + lower air dominates.

    Cost model per step (n = air_steps after this step):
      Ground (any direction):  weight - 0.7           → 0.3 ~ 0.8
      Air up:                  weight + 2.0×1.30^(n-1)  steep
      Air horizontal:          weight + 0.5×1.20^(n-1)  gentler
      Air down:                weight + 0.5 + 0.08×n     nearly flat

    Transition taxes:
      Landing  (+1.0):  airborne → solid ground
      Takeoff  (+0.5):  ground → upward flight
    """
    _MAX_AIR  = 15   # cap consecutive air steps (beyond this, penalty is prohibitive)
    _MAX_ITER = 200000  # safety net — abort if too many expansions

    open_set = MinHeap()
    closed_set = set()

    start_state = (start[0], start[1], 0)
    g_score = {start_state: 0.0}
    parent = {start_state: None}

    # Dominance tracking: (x, y) → list[best_g_at_air_0, ..., best_g_at_air_MAX]
    # State (x,y,a1) with cost c1 dominates (x,y,a2) with cost c2 iff a1 <= a2 and c1 <= c2
    best_at = {}

    def _is_dominated(pos, air, cost):
        """True if an existing state at `pos` has <= air AND <= cost."""
        if pos not in best_at:
            best_at[pos] = [float('inf')] * (_MAX_AIR + 1)
            return False
        arr = best_at[pos]
        # Check states with air_steps <= `air` — if any has lower cost, we're dominated
        for a in range(air + 1):
            if arr[a] <= cost:
                return True
        return False

    def _record_state(pos, air, cost):
        """Register this (pos, air, cost) in the dominance table."""
        arr = best_at[pos]
        # Update this air level
        if cost < arr[air]:
            arr[air] = cost
        # Propagate: if we have cost C at air A, any state at air > A
        # with cost >= C is dominated → mark as inf (will be pruned later)
        for a in range(air + 1, _MAX_AIR + 1):
            if arr[a] >= cost:
                arr[a] = min(arr[a], float('inf'))  # keep inf marker

    open_set.push(_octile_heuristic(start, goal), start_state)
    iterations = 0

    while not open_set.is_empty():
        curr_state = open_set.pop()
        if curr_state is None:
            break
        if curr_state in closed_set:
            continue

        iterations += 1
        if iterations > _MAX_ITER:
            break  # safety net — return partial result

        cx, cy, curr_air = curr_state

        if (cx, cy) == goal:
            path = []
            state = curr_state
            while state is not None:
                path.append((state[0], state[1]))
                state = parent.get(state)
            path.reverse()
            return path

        closed_set.add(curr_state)

        for nb in _grid_neighbors_8(world, (cx, cy)):
            dx = nb[0] - cx
            dy = nb[1] - cy
            nb_on_ground = not world.is_walkable(nb[0], nb[1] + 1)

            step_cost = _WEIGHT_COST.get((dx, dy), 1.0)

            if nb_on_ground:
                # ── Solid ground ──
                step_cost = max(0.1, step_cost - _GROUND_BONUS)
                new_air = 0
                if curr_air > 0:
                    step_cost += _LANDING_TAX
            else:
                # ── In the air — cap new_air ──
                new_air = curr_air + 1
                if new_air > _MAX_AIR:
                    continue  # too many consecutive air steps, path is non-viable
                if dy < 0:
                    step_cost += _UP_BASE * (_UP_EXP ** (new_air - 1))
                    if curr_air == 0:
                        step_cost += _TAKEOFF_TAX
                elif dy > 0:
                    step_cost += _DOWN_BASE + _DOWN_LINEAR * new_air
                else:
                    step_cost += _HORIZ_BASE * (_HORIZ_EXP ** (new_air - 1))

            g_new = g_score[curr_state] + step_cost

            # ── Dominance pruning ──
            nb_pos = (nb[0], nb[1])
            if _is_dominated(nb_pos, new_air, g_new):
                continue

            nb_state = (nb[0], nb[1], new_air)

            if nb_state in closed_set:
                continue

            if nb_state not in g_score or g_new < g_score[nb_state]:
                parent[nb_state] = curr_state
                g_score[nb_state] = g_new
                _record_state(nb_pos, new_air, g_new)
                open_set.push(g_new + _octile_heuristic(nb, goal), nb_state)

    return None  # no path (or exceeded iteration limit)


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
