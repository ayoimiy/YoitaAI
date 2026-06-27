"""
Config-driven A* pathfinding (cloned from YoitaAI files/scripts/utils/astar.lua).

Usage:
    config = AStarConfig(
        start = (sx, sy),
        get_node_key = lambda node: f"{node[0]}_{node[1]}",
        get_h_func = lambda node: abs(node[0] - gx) + abs(node[1] - gy),
        get_neighbors_func = lambda node: [...],
        get_cost = lambda a, b: 1,
        is_goal = lambda node: node == goal,
    )
    path, visited = astar(config)
"""

from dataclasses import dataclass, field
from typing import Any, Callable

from .heap import MinHeap


@dataclass
class AStarConfig:
    """Pluggable configuration for the A* algorithm.

    Fields:
        start:                   The start node (any hashable representation).
        get_node_key:            node → str key.
        get_h_func:              node → heuristic float.
        get_neighbors_func:      node → list of neighbor nodes.
        get_cost:                (from_node, to_node) → edge cost float.
        is_goal:                 node → bool.
        max_count:               max iterations (default 5000).
    """
    start: Any = None
    get_node_key: Callable[[Any], str] = field(default=lambda n: str(n))
    get_h_func: Callable[[Any], float] = field(default=lambda n: 0.0)
    get_neighbors_func: Callable[[Any], list] = field(default=lambda n: [])
    get_cost: Callable[[Any, Any], float] = field(default=lambda a, b: 1.0)
    is_goal: Callable[[Any], bool] = field(default=lambda n: False)
    max_count: int = 5000


def astar(config: AStarConfig):
    """
    Run A* from config.start to goal.

    Returns (path_list, nodes_dict) where:
      - path_list is a list of nodes from start to goal, or None if no path.
      - nodes_dict maps node_key → node for all visited nodes (for viz).
    """
    start = config.start
    get_key = config.get_node_key
    h_func = config.get_h_func
    neighbors_func = config.get_neighbors_func
    cost_func = config.get_cost
    is_goal = config.is_goal
    max_count = config.max_count

    open_set = MinHeap()
    closed_set = set()           # set of keys
    path_set = {}                # key → parent_key
    g_score = {}                 # key → g
    f_score = {}                 # key → f
    nodes_set = {}               # key → node

    start_key = get_key(start)
    g_score[start_key] = 0.0
    f_score[start_key] = h_func(start)
    open_set.push(f_score[start_key], start_key)
    nodes_set[start_key] = start

    count = 0
    while not open_set.is_empty():
        count += 1
        if count > max_count:
            break

        curr_key = open_set.pop()
        if curr_key is None:
            break
        if curr_key in closed_set:
            continue

        if is_goal(nodes_set[curr_key]):
            # Reconstruct path
            path = []
            key = curr_key
            while key is not None:
                path.insert(0, nodes_set[key])
                key = path_set.get(key)
            return path, nodes_set

        closed_set.add(curr_key)

        for neighbor in neighbors_func(nodes_set[curr_key]):
            key = get_key(neighbor)
            if key not in nodes_set:
                nodes_set[key] = neighbor
            if key in closed_set:
                continue

            g = g_score[curr_key] + cost_func(nodes_set[curr_key], neighbor)
            if key not in g_score or g < g_score[key]:
                path_set[key] = curr_key
                g_score[key] = g
                f_score[key] = g + h_func(neighbor)
                open_set.push(f_score[key], key)

    # No path found
    return None, nodes_set
