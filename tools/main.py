"""
Grid Explorer — cave pathfinding visualisation tool.

Controls:
  Left-click  → set target position
  T / t       → trigger pathfinding (animated, 1 step per interval)
  R / r       → regenerate map
  Esc         → quit
"""

import sys, os, random, math
from pathlib import Path
from collections import deque

import pygame
from pygame.locals import QUIT, MOUSEBUTTONDOWN, KEYDOWN, K_ESCAPE, K_t, K_UP, K_DOWN, K_q

from config import (
    CELL_SIZE, WORLD_WIDTH, WORLD_HEIGHT,
    DEFAULT_MODE, DEFAULT_INTENSITY,
    DEFAULT_CAVE_FILL, DEFAULT_CAVE_ITERATIONS, DEFAULT_CAVE_WALL_NEED,
    DEFAULT_PATHFIND_INTERVAL, EDIT_TARGET, EDIT_DRAW, EDIT_ERASE,
)
from core.world import GridWorld
from gen.map_gen import generate_random_walk, generate_cave
from core.player import Player
from core.renderer import Renderer
from algo.spatial import reset_spatial_memory, raytrace5
from algo.pathfind import ALGORITHMS, DEFAULT_ALGO
from util.logger import Logger, Level

ROOT = Path(__file__).parent
CMD_FILE = ROOT / "command.txt"
logger = Logger(global_level=Level.INFO, log_to_file=True,
                log_dir=str(ROOT) + os.sep, current_pos="main")


# ═══════════════════════════════════════════════════════════════
#  Step-by-step pathfinding engines (all algorithms)
# ═══════════════════════════════════════════════════════════════

def _n8(world, node):
    """8-directional walkable neighbors, diagonal corner-cut blocked."""
    x, y = node
    r = []
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nx, ny = x + dx, y + dy
            if world.is_walkable(nx, ny):
                if dx != 0 and dy != 0:
                    if not world.is_walkable(x + dx, y) and not world.is_walkable(x, y + dy):
                        continue
                r.append((nx, ny))
    return r


def _n4(world, node):
    """4-directional only."""
    x, y = node
    r = []
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        nx, ny = x + dx, y + dy
        if world.is_walkable(nx, ny):
            r.append((nx, ny))
    return r


def _h(a, goal):
    dx, dy = abs(a[0] - goal[0]), abs(a[1] - goal[1])
    return max(dx, dy) + (math.sqrt(2) - 1) * min(dx, dy)


class StepEngine:
    """
    Universal step-by-step pathfinding wrapper.
    Supports A* (mod/astar), BFS, Greedy, JPS — all animated.
    """

    def __init__(self, world, start, goal, algo, show_rays=False):
        self.world = world
        self.start = start
        self.goal = goal
        self.algo = algo
        self.show_rays = show_rays

        self.done = False
        self.found = False
        self.path = []
        self.current_node = None
        self.iterations = 0
        self._all_rays = [] if show_rays else None
        self._step_func = None  # generator yielding (curr, open_set, closed_set, done, found, path)

        self.open_nodes = set()
        self.closed_nodes = set()

        self._init_engine()

    # Weighted A* — orth=1, diag=1.5, ground bonus -0.7
    _WEIGHT = {(-1,-1):1.5,(0,-1):1,(1,-1):1.5,(-1,0):1,(1,0):1,(-1,1):1.5,(0,1):1,(1,1):1.5}

    def _init_engine(self):
        if self.algo in ("mod", "astar", "weight"):
            self._init_astar()
        elif self.algo == "bfs":
            self._init_bfs()
        elif self.algo == "greedy":
            self._init_greedy()
        elif self.algo == "jps":
            self._init_jps()

    # ── A* (mod / astar / weight) ──────────────────
    def _init_astar(self):
        from heapq import heappush, heappop
        open_heap = []
        closed_set = set()
        g_score = {self.start: 0.0}
        parent = {}
        all_rays = self._all_rays

        heappush(open_heap, (_h(self.start, self.goal), self.start))
        self.current_node = self.start
        self.open_nodes = {self.start}

        def stepper():
            nonlocal open_heap, closed_set, g_score, parent
            while open_heap:
                _, curr = heappop(open_heap)
                if curr in closed_set:
                    continue
                self.current_node = curr
                closed_set.add(curr)
                self.closed_nodes = set(closed_set)
                self.open_nodes = {item[1] for item in open_heap if item[1] not in closed_set}
                self.iterations += 1
                yield

                if curr == self.goal:
                    self.path = [self.goal]
                    while self.path[-1] != self.start:
                        self.path.append(parent[self.path[-1]])
                    self.path.reverse()
                    self.found = True
                    self.done = True
                    return

                for nb in _n8(self.world, curr):
                    if nb in closed_set:
                        continue
                    rdx = nb[0] - curr[0]
                    rdy = nb[1] - curr[1]
                    if self.algo == "weight":
                        step_cost = self._WEIGHT.get((rdx, rdy), 1.0)
                        if not self.world.is_walkable(nb[0], nb[1] + 1):
                            step_cost = max(0.1, step_cost - 0.7)
                    else:
                        step_cost = 1.414 if abs(rdx) + abs(rdy) == 2 else 1.0

                    if self.show_rays or self.algo == "mod":
                        cnt, rays = raytrace5(self.world, curr, nb)
                        if all_rays is not None:
                            all_rays.extend(rays)
                        if cnt >= 3:
                            continue

                    g_new = g_score[curr] + step_cost
                    if nb not in g_score or g_new < g_score[nb]:
                        parent[nb] = curr
                        g_score[nb] = g_new
                        heappush(open_heap, (g_new + _h(nb, self.goal), nb))

            self.done = True

        self._gen = stepper()

    # ── BFS ───────────────────────────────────────
    def _init_bfs(self):
        queue = deque([self.start])
        visited = {self.start}
        parent = {}
        self.open_nodes = {self.start}

        def stepper():
            nonlocal queue, visited, parent
            while queue:
                curr = queue.popleft()
                self.current_node = curr
                self.closed_nodes = set(visited)
                self.open_nodes = set(queue)
                self.iterations += 1
                yield

                if curr == self.goal:
                    self.path = [self.goal]
                    while self.path[-1] != self.start:
                        self.path.append(parent[self.path[-1]])
                    self.path.reverse()
                    self.found = True
                    self.done = True
                    return

                for nb in _n4(self.world, curr):
                    if nb not in visited:
                        visited.add(nb)
                        parent[nb] = curr
                        queue.append(nb)

            self.done = True

        self._gen = stepper()

    # ── Greedy Best-First ─────────────────────────
    def _init_greedy(self):
        from heapq import heappush, heappop
        open_heap = []
        closed_set = set()
        parent = {}
        heappush(open_heap, (_h(self.start, self.goal), self.start))
        self.open_nodes = {self.start}

        def stepper():
            nonlocal open_heap, closed_set, parent
            while open_heap:
                _, curr = heappop(open_heap)
                if curr in closed_set:
                    continue
                self.current_node = curr
                closed_set.add(curr)
                self.closed_nodes = set(closed_set)
                self.open_nodes = {item[1] for item in open_heap if item[1] not in closed_set}
                self.iterations += 1
                yield

                if curr == self.goal:
                    self.path = [self.goal]
                    while self.path[-1] != self.start:
                        self.path.append(parent[self.path[-1]])
                    self.path.reverse()
                    self.found = True
                    self.done = True
                    return

                for nb in _n8(self.world, curr):
                    if nb not in closed_set and nb not in parent:
                        parent[nb] = curr
                        heappush(open_heap, (_h(nb, self.goal), nb))

            self.done = True

        self._gen = stepper()

    # ── JPS ───────────────────────────────────────
    def _init_jps(self):
        from heapq import heappush, heappop
        open_heap = []
        closed_set = set()
        g_score = {self.start: 0.0}
        parent = {}
        heappush(open_heap, (_h(self.start, self.goal), self.start))
        self.open_nodes = {self.start}

        def stepper():
            nonlocal open_heap, closed_set, g_score, parent
            while open_heap:
                _, curr = heappop(open_heap)
                if curr in closed_set:
                    continue
                self.current_node = curr
                closed_set.add(curr)
                self.closed_nodes = set(closed_set)
                self.open_nodes = {item[1] for item in open_heap if item[1] not in closed_set}
                self.iterations += 1
                yield

                if curr == self.goal:
                    self.path = [self.goal]
                    while self.path[-1] != self.start:
                        self.path.append(parent[self.path[-1]])
                    self.path.reverse()
                    self.found = True
                    self.done = True
                    return

                for jp in _jps_successors(self.world, curr, self.goal, closed_set):
                    g_new = g_score[curr] + _h(curr, jp)
                    if jp not in g_score or g_new < g_score[jp]:
                        parent[jp] = curr
                        g_score[jp] = g_new
                        heappush(open_heap, (g_new + _h(jp, self.goal), jp))

            self.done = True

        self._gen = stepper()

    def step(self):
        """Advance one node.  Returns True if still running."""
        if self.done:
            return False
        try:
            next(self._gen)
            return not self.done
        except StopIteration:
            self.done = True
            return False


# JPS helpers (inline for StepEngine)
def _jps_successors(world, node, goal, closed_set):
    result = []
    x, y = node
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            jp = _jps_jump(world, x, y, dx, dy, goal)
            if jp is not None and jp not in closed_set:
                result.append(jp)
    return result


def _jps_jump(world, cx, cy, dx, dy, goal):
    x, y = cx, cy
    while True:
        x += dx; y += dy
        if not world.is_walkable(x, y):
            return None
        # Corner-cutting prevention: diagonal move blocked if both
        # adjacent orthogonal cells are walls (same check as _n8)
        if dx != 0 and dy != 0:
            if not world.is_walkable(x - dx, y) and not world.is_walkable(x, y - dy):
                return None
        if (x, y) == goal:
            return (x, y)
        if dx != 0 and dy != 0:
            if _jps_jump(world, x, y, dx, 0, goal) or _jps_jump(world, x, y, 0, dy, goal):
                return (x, y)
        else:
            if _jps_forced(world, x, y, dx, dy):
                return (x, y)


def _jps_forced(world, x, y, dx, dy):
    if dx != 0:
        for sy in (-1, 1):
            if not world.is_walkable(x, y + sy) and world.is_walkable(x + dx, y + sy):
                return True
    if dy != 0:
        for sx in (-1, 1):
            if not world.is_walkable(x + sx, y) and world.is_walkable(x + sx, y + dy):
                return True
    return False


# ═══════════════════════════════════════════════════════════════
#  Settings & commands
# ═══════════════════════════════════════════════════════════════

class GameSettings:
    def __init__(self):
        self.mode = DEFAULT_MODE
        self.intensity = DEFAULT_INTENSITY
        self.fill = DEFAULT_CAVE_FILL
        self.iterations = DEFAULT_CAVE_ITERATIONS
        self.wall_threshold = DEFAULT_CAVE_WALL_NEED
        self.seed = random.randint(0, 999999)
        self.pathfind_interval = DEFAULT_PATHFIND_INTERVAL
        self.algo = DEFAULT_ALGO
        self.show_rays = False
        self.target = None
        self.grid_w = WORLD_WIDTH
        self.grid_h = WORLD_HEIGHT
        self.map_slot = 1          # current map slot (1-9)
        self.running = True
        self._need_pf_reset = False


def regenerate_map(world, settings):
    reset_spatial_memory()
    if settings.mode == "cave":
        generate_cave(world, settings.fill, settings.iterations,
                      settings.wall_threshold, settings.seed)
    else:
        generate_random_walk(world, settings.intensity, settings.seed)
    world.set_cell(world.width // 2, world.height // 2, True)


def resize_world(world, settings, w, h):
    world.width = w; world.height = h
    world.cells = [[False] * w for _ in range(h)]
    world.chunks_x = (w + world.chunk_size - 1) // world.chunk_size
    world.chunks_y = (h + world.chunk_size - 1) // world.chunk_size
    settings.grid_w = w; settings.grid_h = h
    regenerate_map(world, settings)


def execute_command(line, world, player, settings):
    parts = line.strip().split()
    if not parts: return
    cmd = parts[0].lower()
    logger.info(f"Command: {line}")
    try:
        if cmd == "restart":
            regenerate_map(world, settings)
            player.reset_to_center()
            settings._need_pf_reset = True
        elif cmd == "set" and len(parts) >= 3:
            key = parts[1].lower()
            if key == "mode":
                v = parts[2].lower()
                if v in ("walk", "random"): settings.mode = "walk"
                elif v in ("cave", "ca", "perlin"): settings.mode = "cave"
            elif key == "intensity":   settings.intensity = max(0.3, min(3.0, float(parts[2])))
            elif key == "fill":        settings.fill = float(parts[2])
            elif key == "iterations":  settings.iterations = int(parts[2])
            elif key == "wall":        settings.wall_threshold = int(parts[2])
            elif key == "seed":        settings.seed = int(parts[2]); random.seed(settings.seed)
            elif key == "interval":    settings.pathfind_interval = max(0.05, min(10.0, float(parts[2])))
            elif key == "algo":
                a = parts[2].lower()
                if a in ALGORITHMS: settings.algo = a
            elif key == "rays":        settings.show_rays = parts[2].lower() in ("on", "true", "1")
            elif key == "map":
                slot = int(parts[2])
                if 1 <= slot <= 9:
                    settings.map_slot = slot
                    if load_map(world, str(slot)):
                        player.reset_to_center(); settings._need_pf_reset = True
            elif key == "grid" and len(parts) >= 4:
                w, h = int(parts[2]), int(parts[3])
                resize_world(world, settings, max(5, min(100, w)), max(5, min(100, h)))
                player.reset_to_center(); settings._need_pf_reset = True
        elif cmd == "quit":
            settings.running = False
    except Exception as e:
        logger.error(f"Command failed: {e}")


def read_commands(world, player, settings):
    if not CMD_FILE.exists(): return
    try:
        with open(CMD_FILE, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
        with open(CMD_FILE, "w", encoding="utf-8") as f: pass
        for line in lines:
            execute_command(line, world, player, settings)
    except OSError: pass


# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

# ── Map save / load ─────────────────────────────────────
MAPS_DIR = ROOT / "maps"

def save_map(world, name="default"):
    """Save world to maps/<name>.map.  Returns True on success."""
    MAPS_DIR.mkdir(exist_ok=True)
    path = MAPS_DIR / f"{name}.map"
    try:
        lines = []
        for y in range(world.height):
            line = ''.join('.' if world.is_walkable(x, y) else '#' for x in range(world.width))
            lines.append(line)
        with open(path, 'w') as f:
            f.write('\n'.join(lines))
        logger.info(f"Map saved: {path}")
        return True
    except OSError as e:
        logger.error(f"Save failed: {e}")
        return False


def load_map(world, name="default"):
    """Load world from maps/<name>.map.  Returns True on success."""
    path = MAPS_DIR / f"{name}.map"
    if not path.exists():
        logger.warn(f"Map not found: {path}")
        return False
    with open(path, 'r') as f:
        lines = [l.rstrip() for l in f if l.strip()]
    for y, line in enumerate(lines):
        if y >= world.height: break
        for x, ch in enumerate(line):
            if x >= world.width: break
            world.set_cell(x, y, ch == '.')
    logger.info(f"Map loaded: {path}")
    return True


def main():
    logger.start()
    world = GridWorld()
    world.fill_all(True)  # empty map by default
    settings = GameSettings()
    player = Player()

    # Startup: load map slot 1 if it exists
    load_map(world, str(settings.map_slot))

    pygame.init()
    renderer = Renderer()

    engine = None
    pf_path = []; pf_closed = set(); pf_open = set()
    pf_current = None; pf_rays = []; pf_working = False
    last_step = 0; cmd_poll = 0
    edit_mode = EDIT_TARGET
    mouse_cell = None
    mouse_down = False
    save_msg = ""
    save_msg_time = 0
    num_mode = "algo"  # "algo" or "map" — what 1-9 keys control

    def _reset_pf():
        nonlocal engine, pf_path, pf_closed, pf_open, pf_current, pf_rays, pf_working
        engine = None; pf_path = []; pf_closed = set(); pf_open = set()
        pf_current = None; pf_rays = []; pf_working = False

    def _handle_click(cx, cy):
        if not (0 <= cx < world.width and 0 <= cy < world.height):
            return
        if edit_mode == EDIT_TARGET:
            if world.is_walkable(cx, cy):
                settings.target = (cx, cy)
        elif edit_mode == EDIT_DRAW:
            world.set_cell(cx, cy, False)
        elif edit_mode == EDIT_ERASE:
            world.set_cell(cx, cy, True)

    logger.info("Grid Explorer started")

    while settings.running:
        now = pygame.time.get_ticks()
        mx, my = pygame.mouse.get_pos()
        cx, cy = mx // CELL_SIZE, my // CELL_SIZE
        if 0 <= cx < world.width and 0 <= cy < world.height:
            mouse_cell = (cx, cy)

        for event in pygame.event.get():
            if event.type == QUIT:
                settings.running = False
            elif event.type == KEYDOWN:
                if event.key == K_ESCAPE:
                    settings.running = False
                # ── Edit mode switches ────────────
                elif event.key == pygame.K_f:
                    edit_mode = EDIT_TARGET
                elif event.key == pygame.K_p:
                    edit_mode = EDIT_DRAW
                elif event.key == pygame.K_e:
                    edit_mode = EDIT_ERASE
                # ── Pathfinding trigger ───────────
                elif event.key in (K_t, pygame.K_t):
                    if settings.target and world.is_walkable(*player.pos()):
                        engine = StepEngine(world, player.pos(), settings.target,
                                            settings.algo, settings.show_rays)
                        pf_path = []; pf_closed = set(); pf_open = set()
                        pf_current = None; pf_rays = []; pf_working = True
                        last_step = now
                # ── Regenerate procedural map ─────
                elif event.key == pygame.K_r:
                    regenerate_map(world, settings); player.reset_to_center()
                    _reset_pf()
                elif event.key == pygame.K_q:
                    world.fill_all(True); player.reset_to_center()
                    _reset_pf()
                elif event.key == pygame.K_g:
                    # G = set player position to mouse cursor
                    if mouse_cell and world.is_walkable(*mouse_cell):
                        player.set_pos(*mouse_cell)
                elif event.key == pygame.K_s:
                    ok = save_map(world, str(settings.map_slot))
                    save_msg = f"Saved: slot {settings.map_slot}" if ok else "Save FAILED"
                    save_msg_time = now
                elif event.key == pygame.K_n:
                    num_mode = "algo"   # 1-9 keys now control algorithms
                elif event.key == pygame.K_m:
                    num_mode = "map"    # 1-9 keys now control map slots
                # ── Number keys 1-9: algo or map ──
                elif pygame.K_1 <= event.key <= pygame.K_9:
                    idx = event.key - pygame.K_1  # 0-8
                    keys = list(ALGORITHMS.keys())
                    if num_mode == "algo":
                        if idx < len(keys):
                            settings.algo = keys[idx]
                    else:  # map mode
                        slot = idx + 1
                        settings.map_slot = slot
                        if load_map(world, str(slot)):
                            player.reset_to_center(); _reset_pf()
                            save_msg = f"Loaded: slot {slot}"
                        else:
                            world.fill_all(True); player.reset_to_center(); _reset_pf()
                            save_msg = f"New: slot {slot} (empty)"
                        save_msg_time = now
                # ── Intensity ─────────────────────
                elif event.key == K_UP:
                    settings.intensity = min(3.0, settings.intensity + 0.1)
                elif event.key == K_DOWN:
                    settings.intensity = max(0.3, settings.intensity - 0.1)
            elif event.type == pygame.MOUSEBUTTONDOWN:
                if event.button == 1:  # left click
                    mouse_down = True
                    _handle_click(cx, cy)
            elif event.type == pygame.MOUSEBUTTONUP:
                if event.button == 1:
                    mouse_down = False

        # ── Continuous paint/erase while mouse held ──
        if mouse_down and mouse_cell and edit_mode in (EDIT_DRAW, EDIT_ERASE):
            _handle_click(*mouse_cell)

        if now - cmd_poll > 500:
            read_commands(world, player, settings); cmd_poll = now

        if settings._need_pf_reset:
            _reset_pf()
            settings._need_pf_reset = False

        # ── Animated stepping (time-based) ──────────
        if engine and not engine.done:
            if now - last_step >= int(settings.pathfind_interval * 1000):
                engine.step()
                last_step = now
                pf_closed = set(engine.closed_nodes)
                pf_open = set(engine.open_nodes)
                pf_current = engine.current_node
                pf_rays = engine._all_rays if engine._all_rays else []
                if engine.done:
                    pf_working = False
                    if engine.found:
                        pf_path = list(engine.path)

        pf_state = {
            "path": pf_path,
            "open_set": pf_open,
            "closed_set": pf_closed,
            "current_node": pf_current,
            "target": settings.target,
            "rays": pf_rays,
            "show_rays": settings.show_rays,
            "component_cells": set(),
            "working": pf_working,
            "algo_name": f"[{settings.algo}] {ALGORITHMS[settings.algo][0].split('(')[0].strip()}",
            "intensity": settings.intensity,
            "map_slot": settings.map_slot,
            "num_mode": num_mode,
            "edit_mode": edit_mode,
            "mouse_cell": mouse_cell,
            "save_msg": save_msg if now - save_msg_time < 2000 else "",
        }

        renderer.render(world, player, pf_state)

    logger.info("Grid Explorer shutting down")
    logger.flush()
    pygame.quit()
    sys.exit(0)


if __name__ == "__main__":
    main()
