"""
Big-grid pathfinding test mode (1000x1000).
Instant pathfinding with zoom/pan — compares algorithms at scale.

Controls:
  Mouse wheel  — zoom in/out
  Middle drag  — pan the view
  Left-click   — set target position
  Arrow keys   — pan the view
  T key        — run pathfinding
  R key        — regenerate map
  1-5 keys     — switch algorithm
  Esc          — quit
"""

import sys, os, time, random, math
from pathlib import Path

import pygame
from pygame.locals import QUIT, KEYDOWN, MOUSEBUTTONDOWN, MOUSEBUTTONUP, MOUSEMOTION, K_ESCAPE

sys.path.insert(0, str(Path(__file__).parent))

from core.world import GridWorld
from algo.pathfind import pathfind_astar, pathfind_mod, pathfind_bfs, pathfind_greedy, pathfind_jps, pathfind_weighted
from gen.map_gen import generate_cave_large

ROOT = Path(__file__).parent
CMD_FILE = ROOT / "command.txt"

# ── Algorithm registry ────────────────────────────────
ALGOS = {
    "1. A*":           pathfind_astar,
    "2. Mod (5-ray)":  pathfind_mod,
    "3. BFS":          pathfind_bfs,
    "4. Greedy":       pathfind_greedy,
    "5. JPS":          pathfind_jps,
    "6. Weighted":     pathfind_weighted,
}
ALGO_KEYS = list(ALGOS.keys())


# ── Renderer with zoom + pan ─────────────────────────
class BigGridRenderer:
    def __init__(self, world_w, world_h, win_w=1200, win_h=900):
        self.screen = pygame.display.set_mode((win_w, win_h), pygame.RESIZABLE)
        pygame.display.set_caption("Big Grid Explorer — 1000x1000 Pathfinding")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("consolas", 13)
        self.win_w, self.win_h = win_w, win_h
        self.zoom = 1.0
        self.cx = world_w / 2
        self.cy = world_h / 2
        self.dragging = False
        self.drag_start = (0, 0)
        self.cam_start = (0, 0)
        self._auto_zoom(world_w, world_h, win_w, win_h)

    def _auto_zoom(self, ww, wh, vw, vh):
        self.zoom = min(vw / ww, vh / wh)
        self.cx, self.cy = ww / 2, wh / 2

    def world_to_screen(self, wx, wy):
        sx = (wx - self.cx) * self.zoom + self.win_w / 2
        sy = (wy - self.cy) * self.zoom + self.win_h / 2
        return (int(sx), int(sy))

    def screen_to_world(self, sx, sy):
        wx = (sx - self.win_w / 2) / self.zoom + self.cx
        wy = (sy - self.win_h / 2) / self.zoom + self.cy
        return (wx, wy)

    def visible_cells(self, world):
        x0, y0 = self.screen_to_world(0, 0)
        x1, y1 = self.screen_to_world(self.win_w, self.win_h)
        return (max(0, int(x0)-1), max(0, int(y0)-1),
                min(world.width, int(x1)+2), min(world.height, int(y1)+2))

    def render(self, world, player_pos, path, elapsed_ms, algo_name, target_pos=None):
        self.screen.fill((15, 15, 18))

        cell_sz = max(1, math.ceil(self.zoom))
        step = max(1, int(1.0 / max(0.5, self.zoom)))

        x0, y0, x1, y1 = self.visible_cells(world)
        for y in range(y0, y1, step):
            for x in range(x0, x1, step):
                sx, sy = self.world_to_screen(x, y)
                if sx < -cell_sz or sy < -cell_sz or sx > self.win_w or sy > self.win_h:
                    continue
                color = (180, 160, 140) if world.is_walkable(x, y) else (25, 25, 30)
                if cell_sz == 1:
                    self.screen.set_at((sx, sy), color)
                else:
                    pygame.draw.rect(self.screen, color, (sx, sy, cell_sz, cell_sz))

        # Draw path as filled squares (same style as terrain cells)
        #   Red  = on solid ground (landing / grounded step)
        #   Blue = long floating run (≥10 consecutive air cells)
        #   Gold = normal air movement (<10 consecutive)
        if len(path) >= 2 and len(path) < 5000:
            # Identify floating runs
            floating = [world.is_walkable(p[0], p[1] + 1) for p in path]
            long_run = [False] * len(path)
            run_start = 0
            for i in range(1, len(path) + 1):
                flt = floating[i-1] if i <= len(path) else True
                if not flt or i > len(path):
                    if i - 1 - run_start >= 10:
                        for j in range(run_start, i - 1):
                            long_run[j] = True
                    run_start = i

            for idx, (px, py) in enumerate(path):
                sx, sy = self.world_to_screen(px, py)
                on_ground = not world.is_walkable(px, py + 1)
                if on_ground:
                    color = (220, 40, 40)       # red — grounded
                elif long_run[idx]:
                    color = (60, 140, 255)       # blue — long float (≥10)
                else:
                    color = (255, 200, 0)        # gold — short float
                if cell_sz <= 2:
                    self.screen.set_at((sx, sy), color)
                else:
                    pygame.draw.rect(self.screen, color, (sx, sy, cell_sz, cell_sz))

        # Draw player
        px, py = self.world_to_screen(*player_pos)
        pr = max(2, int(self.zoom * 0.6))
        pygame.draw.rect(self.screen, (200, 60, 255), (px-pr, py-pr, pr*2, pr*2))

        # Draw target
        if target_pos:
            tx, ty = self.world_to_screen(*target_pos)
            tr = max(3, int(self.zoom * 0.8))
            pygame.draw.rect(self.screen, (255, 30, 30), (tx-tr, ty-tr, tr*2, tr*2),
                             max(1, int(self.zoom*0.3)))

        # Compute floating stats
        floating_total = sum(1 for p in path if world.is_walkable(p[0], p[1] + 1)) if path else 0
        gnd = len(path) - floating_total if path else 0
        long_float = 0; run = 0
        for p in path:
            if world.is_walkable(p[0], p[1] + 1): run += 1
            else:
                if run >= 10: long_float += run
                run = 0
        if run >= 10: long_float += run

        # HUD
        lines = [
            f"Zoom: {self.zoom:.2f}x  |  {algo_name}",
            f"Path: {len(path)} cells  |  {elapsed_ms:.0f}ms",
            f"RED=ground({gnd})  BLUE=float>={10}({long_float})  GOLD=float<10({floating_total-long_float})",
            f"Visible: {x0},{y0} - {x1},{y1}",
            "Mouse: wheel=zoom  drag=pan  L-click=target  T=find  R=regen  1-6=algo",
        ]
        for i, line in enumerate(lines):
            surf = self.font.render(line, True, (180, 180, 180))
            pygame.draw.rect(self.screen, (10, 10, 14), (4, 4 + i * 18, surf.get_width() + 6, 18))
            self.screen.blit(surf, (7, 5 + i * 18))

        pygame.display.flip()
        self.clock.tick(60)


# ── Main ─────────────────────────────────────────────
def main():
    WORLD_W, WORLD_H = 1000, 1000
    pygame.init()

    print("Generating 1000x1000 cave...")
    world = GridWorld(WORLD_W, WORLD_H)
    generate_cave_large(world, intensity=2.0, seed=random.randint(0, 999999))

    open_cells = sum(1 for y in range(WORLD_H) for x in range(WORLD_W) if world.is_walkable(x, y))
    print(f"Map: {open_cells}/1M open ({open_cells*100/1e6:.1f}%)")

    # Ensure centre is walkable
    cx, cy = WORLD_W // 2, WORLD_W // 2
    if not world.is_walkable(cx, cy):
        for dist in range(1, 50):
            found = False
            for dy in range(-dist, dist+1):
                for dx in range(-dist, dist+1):
                    if world.is_walkable(cx+dx, cy+dy):
                        cx, cy = cx+dx, cy+dy; found = True; break
                if found: break
            if found: break

    player_pos = (cx, cy)
    target_pos = None
    path = []
    algo_idx = 0
    elapsed_ms = 0
    running = True

    renderer = BigGridRenderer(WORLD_W, WORLD_H)

    while running:
        for event in pygame.event.get():
            if event.type == QUIT or (event.type == KEYDOWN and event.key == K_ESCAPE):
                running = False
            elif event.type == KEYDOWN:
                if event.key in (pygame.K_1, pygame.K_2, pygame.K_3, pygame.K_4, pygame.K_5, pygame.K_6):
                    algo_idx = event.key - pygame.K_1
                elif event.key == pygame.K_t and target_pos:
                    algo_name = ALGO_KEYS[algo_idx]
                    algo_func = ALGOS[algo_name]
                    t0 = time.perf_counter()
                    result = algo_func(world, player_pos, target_pos)
                    elapsed_ms = (time.perf_counter() - t0) * 1000
                    path = result if result else []
                    print(f"{algo_name}: {elapsed_ms:.0f}ms, {len(path)-1} steps")
                elif event.key == pygame.K_r:
                    print("Regenerating...")
                    generate_cave_large(world, intensity=2.0, seed=random.randint(0, 999999))
                    player_pos = (WORLD_W//2, WORLD_H//2)
                    if not world.is_walkable(*player_pos):
                        for dist in range(1, 50):
                            for dy in range(-dist,dist+1):
                                for dx in range(-dist,dist+1):
                                    if world.is_walkable(player_pos[0]+dx, player_pos[1]+dy):
                                        player_pos = (player_pos[0]+dx, player_pos[1]+dy); break
                                else: continue; break
                    path = []; target_pos = None
            elif event.type == MOUSEBUTTONDOWN:
                if event.button == 4:  # scroll up
                    renderer.zoom = min(20.0, renderer.zoom * 1.2)
                elif event.button == 5:  # scroll down
                    renderer.zoom = max(0.02, renderer.zoom / 1.2)
                elif event.button == 1:  # left click
                    wx, wy = renderer.screen_to_world(*pygame.mouse.get_pos())
                    wx, wy = int(wx), int(wy)
                    if world.is_walkable(wx, wy):
                        target_pos = (wx, wy)
                elif event.button == 2:  # middle click
                    renderer.dragging = True
                    renderer.drag_start = pygame.mouse.get_pos()
                    renderer.cam_start = (renderer.cx, renderer.cy)
            elif event.type == MOUSEBUTTONUP and event.button == 2:
                renderer.dragging = False
            elif event.type == MOUSEMOTION and renderer.dragging:
                mx, my = pygame.mouse.get_pos()
                dx = (mx - renderer.drag_start[0]) / renderer.zoom
                dy = (my - renderer.drag_start[1]) / renderer.zoom
                renderer.cx = renderer.cam_start[0] - dx
                renderer.cy = renderer.cam_start[1] - dy

        # Keyboard pan
        keys = pygame.key.get_pressed()
        pan_speed = 50 / max(0.02, renderer.zoom)
        if keys[pygame.K_LEFT]:  renderer.cx -= pan_speed
        if keys[pygame.K_RIGHT]: renderer.cx += pan_speed
        if keys[pygame.K_UP]:    renderer.cy -= pan_speed
        if keys[pygame.K_DOWN]:  renderer.cy += pan_speed

        renderer.render(world, player_pos, path, elapsed_ms, ALGO_KEYS[algo_idx], target_pos)

    pygame.quit()


if __name__ == "__main__":
    main()
