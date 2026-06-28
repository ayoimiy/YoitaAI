"""
Jump Point Search (JPS) — grid pathfinding with symmetry pruning.

JPS only expands "jump points" — nodes where the optimal path changes
direction.  10-30x fewer expansions than A* on open terrain.

Based on the algorithm by Daniel Harabor and Alban Grastien (2011).
"""

import math
from .heap import MinHeap


# ═══════════════════════════════════════════════════════════════
#  Heuristic
# ═══════════════════════════════════════════════════════════════

def _octile_heuristic(a, goal):
    """Octile distance — admissible for 8-direction grid."""
    dx = abs(a[0] - goal[0])
    dy = abs(a[1] - goal[1])
    return max(dx, dy) + (math.sqrt(2) - 1) * min(dx, dy)


# ═══════════════════════════════════════════════════════════════
#  JPS pathfinding
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

        successors = _jps_successors(world, curr, goal, closed_set)

        for nb in successors:
            if nb in closed_set:
                continue
            g_new = g_score[curr] + _octile_heuristic(curr, nb)

            if nb not in g_score or g_new < g_score[nb]:
                parent[nb] = curr
                g_score[nb] = g_new
                f = g_new + _octile_heuristic(nb, goal)
                open_set.push(f, nb)

    return None


# ═══════════════════════════════════════════════════════════════
#  JPS helpers
# ═══════════════════════════════════════════════════════════════

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
            return None
        # Corner-cutting prevention
        if dx != 0 and dy != 0:
            if not world.is_walkable(x - dx, y) and not world.is_walkable(x, y - dy):
                return None
        if (x, y) == goal:
            return (x, y)

        if dx != 0 and dy != 0:
            # Diagonal: forced neighbor check
            blocked_h = not world.is_walkable(x - dx, y)
            open_h = world.is_walkable(x + dx, y)
            blocked_v = not world.is_walkable(x, y - dy)
            open_v = world.is_walkable(x, y + dy)
            if (blocked_h and open_h) or (blocked_v and open_v):
                return (x, y)
            if _jump_straight(world, x, y, dx, 0, goal) or \
               _jump_straight(world, x, y, 0, dy, goal):
                return (x, y)
        else:
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
    if dx != 0:
        for sy in (-1, 1):
            if not world.is_walkable(x, y + sy) and world.is_walkable(x + dx, y + sy):
                return True
    if dy != 0:
        for sx in (-1, 1):
            if not world.is_walkable(x + sx, y) and world.is_walkable(x + sx, y + dy):
                return True
    return False


def _reconstruct(parent, node):
    """Reconstruct path from goal back to start."""
    path = []
    while node is not None:
        path.append(node)
        node = parent.get(node)
    path.reverse()
    return path
