"""
Map generators — random-walk digging (default) + cellular automata cave.

Random walk: constrained branching from centre.
  - Anti-bloat: walkers avoid carving cells that already have 3+ open neighbors
  - Two-phase denoise: strict cleanup removes isolated specks
"""

import random
from collections import deque


# ═══════════════════════════════════════════════════════════════
#  Random-walk digging (DEFAULT)
# ═══════════════════════════════════════════════════════════════

def generate_random_walk(world, intensity=1.0, seed=None):
    """
    Branching corridors from centre with controlled width.

    intensity (0.3–3.0): step count + branch frequency.
    Default 1.0 = narrow corridors, good pathfinding test terrain.
    """
    if seed is not None:
        random.seed(seed)

    w, h = world.width, world.height
    cx, cy = w // 2, h // 2

    world.fill_all(False)

    steps_total = int(w * h * 0.35 * intensity)
    branch_chance = 0.025 * intensity
    max_walkers = max(2, int(intensity * 4))
    death_chance = 0.25
    # Anti-bloat: skip if all 4 neighbors already open (fully surrounded)
    bloat_limit = 4

    # Seed centre 3x3
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if 0 <= cx + dx < w and 0 <= cy + dy < h:
                world.set_cell(cx + dx, cy + dy, True)

    walkers = [(cx, cy)]
    steps_taken = 0

    while walkers and steps_taken < steps_total:
        idx = random.randrange(len(walkers))
        wx, wy = walkers[idx]

        dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]
        random.shuffle(dirs)
        moved = False

        for dx, dy in dirs:
            nx, ny = wx + dx, wy + dy
            if not (1 < nx < w - 2 and 1 < ny < h - 2):
                continue
            # Anti-bloat: count open neighbors of target
            open_n = 0
            for ndx, ndy in ((-1,0),(1,0),(0,-1),(0,1)):
                if world.is_walkable(nx + ndx, ny + ndy):
                    open_n += 1
            if open_n >= bloat_limit:
                continue  # skip — too many open neighbors → would create hole
            world.set_cell(nx, ny, True)
            walkers[idx] = (nx, ny)
            moved = True
            break

        if not moved:
            walkers.pop(idx)
            continue

        steps_taken += 1

        if random.random() < branch_chance and len(walkers) < max_walkers:
            walkers.append((wx, wy))

        if len(walkers) > 1 and random.random() < death_chance:
            walkers.pop(random.randrange(len(walkers)))

    # ── Two-phase denoise ──────────────────────────
    _cleanup(world)

    world.set_cell(cx, cy, True)


def _cleanup(world):
    """
    Remove noise cells:
      1. Flip truly isolated cells (≤1 open 4-neighbor)
      2. Fill tiny disconnected blobs (≤2 cells)
    """
    w, h = world.width, world.height

    # Pass 1: only truly isolated
    to_flip = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if not world.is_walkable(x, y):
                continue
            n = 0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                if world.is_walkable(x + dx, y + dy):
                    n += 1
            if n <= 1:
                to_flip.append((x, y))
    for x, y in to_flip:
        world.set_cell(x, y, False)

    # Pass 2: remove tiny specks (≤2 cells)
    visited_global = set()
    for y in range(h):
        for x in range(w):
            if not world.is_walkable(x, y) or (x, y) in visited_global:
                continue
            blob = _flood_small(world, x, y)
            visited_global |= blob
            if len(blob) <= 2:
                for bx, by in blob:
                    world.set_cell(bx, by, False)


def _flood_small(world, sx, sy):
    """4-directional flood fill, returns set of cells in component."""
    visited = set()
    q = deque([(sx, sy)])
    visited.add((sx, sy))
    while q:
        x, y = q.popleft()
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if world.is_walkable(nx, ny) and (nx, ny) not in visited:
                visited.add((nx, ny))
                q.append((nx, ny))
    return visited


# ═══════════════════════════════════════════════════════════════
#  Cellular automata cave (alternative)
# ═══════════════════════════════════════════════════════════════

def generate_cave(world, fill_ratio=0.45, iterations=5, wall_threshold=5, seed=None):
    """Guaranteed-connected cave via CA + flood-fill repair."""
    if seed is not None:
        random.seed(seed)

    w, h = world.width, world.height
    cx, cy = w // 2, h // 2

    for y in range(h):
        for x in range(w):
            world.cells[y][x] = random.random() < fill_ratio
    world.set_cell(cx, cy, True)

    for _ in range(iterations):
        new_cells = [row[:] for row in world.cells]
        for y in range(h):
            for x in range(w):
                walls = 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == 0 and dy == 0: continue
                        if not world.is_walkable(x + dx, y + dy):
                            walls += 1
                new_cells[y][x] = walls < wall_threshold
        new_cells[cy][cx] = True
        world.cells = new_cells

    main_cave = _flood_fill(world, cx, cy)
    main_set = set(main_cave)
    for y in range(h):
        for x in range(w):
            if world.is_walkable(x, y) and (x, y) not in main_set:
                world.set_cell(x, y, False)

    _smooth_edges(world)
    world.set_cell(cx, cy, True)


def _flood_fill(world, sx, sy):
    if not world.is_walkable(sx, sy): return set()
    visited = set(); q = deque([(sx, sy)]); visited.add((sx, sy))
    while q:
        x, y = q.popleft()
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if world.is_walkable(nx, ny) and (nx, ny) not in visited:
                visited.add((nx, ny)); q.append((nx, ny))
    return visited


def _smooth_edges(world):
    to_flip = []
    for y in range(world.height):
        for x in range(world.width):
            if not world.is_walkable(x, y): continue
            n = 0
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                if world.is_walkable(x + dx, y + dy): n += 1
            if n <= 1: to_flip.append((x, y))
    for x, y in to_flip: world.set_cell(x, y, False)


# ═══════════════════════════════════════════════════════════════
#  Large-grid cave (1000x1000 — used by big mode)
# ═══════════════════════════════════════════════════════════════

def generate_cave_large(world, intensity=2.0, seed=None):
    """Generate connected cave on large grids (adapted for 1000x1000)."""
    if seed is not None:
        random.seed(seed)
    w, h = world.width, world.height
    cx, cy = w // 2, h // 2

    steps_total = int(w * h * 0.35 * intensity)
    branch_chance = 0.025 * intensity
    max_walkers = max(2, int(intensity * 6))
    death_chance = 0.15
    bloat_limit = 5

    world.fill_all(False)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if 0 <= cx + dx < w and 0 <= cy + dy < h:
                world.set_cell(cx + dx, cy + dy, True)

    walkers = [(cx, cy)]
    steps = 0
    while walkers and steps < steps_total:
        idx = random.randrange(len(walkers))
        wx, wy = walkers[idx]
        dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)]
        random.shuffle(dirs)
        moved = False
        for dx, dy in dirs:
            nx, ny = wx + dx, wy + dy
            if not (2 < nx < w - 2 and 2 < ny < h - 2):
                continue
            open_n = sum(1 for ndx, ndy in ((-1, 0), (1, 0), (0, -1), (0, 1))
                         if world.is_walkable(nx + ndx, ny + ndy))
            if open_n >= bloat_limit:
                continue
            world.set_cell(nx, ny, True)
            walkers[idx] = (nx, ny)
            moved = True
            break
        if not moved:
            walkers.pop(idx)
            continue
        steps += 1
        if random.random() < branch_chance and len(walkers) < max_walkers:
            walkers.append((wx, wy))
        if len(walkers) > 1 and random.random() < death_chance:
            walkers.pop(random.randrange(len(walkers)))

    # Cleanup isolated cells
    to_flip = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if not world.is_walkable(x, y):
                continue
            n = sum(1 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
                    if world.is_walkable(x + dx, y + dy))
            if n <= 1:
                to_flip.append((x, y))
    for x, y in to_flip:
        world.set_cell(x, y, False)
