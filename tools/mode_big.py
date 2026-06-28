"""
Big-grid pathfinding test mode (1000x1000).
Pre-rendered map surface for smooth zoom/pan.

Controls:
  Left-drag  — pan
  Right-click — set target
  Wheel      — zoom toward cursor
  WASD/arrows — pan
  T — run pathfinding
  R — regenerate map
  1-8 — switch algorithm
  Esc — quit
"""

import sys, os, time, random, math
from pathlib import Path
import pygame
from pygame.locals import QUIT, KEYDOWN, MOUSEBUTTONDOWN, MOUSEBUTTONUP, MOUSEMOTION, K_ESCAPE

sys.path.insert(0, str(Path(__file__).parent))
from core.world import GridWorld
from algo.pathfind import (pathfind_astar, pathfind_mod, pathfind_bfs,
                           pathfind_greedy, pathfind_jps, pathfind_weighted)
from gen.map_gen import generate_cave_large
import struct as _struct, subprocess as _sp

ROOT = Path(__file__).parent
PF_IN  = ROOT / "pathfind_c" / "pf_in.bin"
PF_OUT = ROOT / "pathfind_c" / "pf_out.bin"

# ── C bridge ────────────────────────────────────────
BRIDGE_EXE = ROOT / "pathfind_c" / "pf_bridge.exe"

def _pathfind_c(world, start, goal):
    w, h = world.width, world.height
    with open(PF_IN, "wb") as f:
        f.write(_struct.pack("i", w)); f.write(_struct.pack("i", h))
        f.write(_struct.pack("i", start[0])); f.write(_struct.pack("i", start[1]))
        f.write(_struct.pack("i", goal[0])); f.write(_struct.pack("i", goal[1]))
        data = bytearray(w * h)
        for y in range(h):
            row = world.cells[y]; off = y * w
            for x in range(w): data[off + x] = 1 if row[x] else 0
        f.write(data)
    try:
        _sp.run([str(BRIDGE_EXE), str(PF_IN), str(PF_OUT)], check=True, timeout=30,
                creationflags=_sp.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
    except Exception as e:
        print(f"C bridge error: {e}"); return [], 0
    try:
        with open(PF_OUT, "rb") as f:
            plen = _struct.unpack("i", f.read(4))[0]
            ems  = _struct.unpack("f", f.read(4))[0]
            if plen <= 0: return [], ems
            px = _struct.unpack(f"{plen}i", f.read(4 * plen))
            py = _struct.unpack(f"{plen}i", f.read(4 * plen))
        return list(zip(px, py)), ems
    except Exception as e:
        print(f"C result error: {e}"); return [], 0

# ── Lua bridge ──────────────────────────────────────
LUA_EXE = "E:/dev/lua5.1.exe"
LUA_RUNNER = ROOT / "pathfind_c" / "lua_bridge_runner.lua"

def _pathfind_lua(world, start, goal):
    w, h = world.width, world.height
    with open(PF_IN, "wb") as f:
        f.write(_struct.pack("i", w)); f.write(_struct.pack("i", h))
        f.write(_struct.pack("i", start[0])); f.write(_struct.pack("i", start[1]))
        f.write(_struct.pack("i", goal[0])); f.write(_struct.pack("i", goal[1]))
        data = bytearray(w * h)
        for y in range(h):
            row = world.cells[y]; off = y * w
            for x in range(w): data[off + x] = 1 if row[x] else 0
        f.write(data)
    try:
        _sp.run([LUA_EXE, str(LUA_RUNNER), str(PF_IN), str(PF_OUT)],
                cwd=str(LUA_RUNNER.parent), check=True, timeout=120,
                creationflags=_sp.CREATE_NO_WINDOW if sys.platform == "win32" else 0)
    except Exception as e:
        print(f"Lua error: {e}"); return [], 0
    try:
        with open(PF_OUT, "rb") as f:
            plen = _struct.unpack("i", f.read(4))[0]
            ems  = _struct.unpack("i", f.read(4))[0]
            if plen <= 0: return [], ems
            px = _struct.unpack(f"{plen}i", f.read(4 * plen))
            py = _struct.unpack(f"{plen}i", f.read(4 * plen))
        return list(zip(px, py)), ems
    except Exception as e:
        print(f"Lua result error: {e}"); return [], 0

# ── Algorithm registry ──────────────────────────────
ALGOS = {
    "1. A* (py)":          pathfind_astar,
    "2. Mod 5-ray (py)":   pathfind_mod,
    "3. BFS (py)":          pathfind_bfs,
    "4. Greedy (py)":       pathfind_greedy,
    "5. JPS (py)":          pathfind_jps,
    "6. Weighted (py)":     pathfind_weighted,
    "7. Weighted (C)":      _pathfind_c,
    "8. Weighted (Lua)":    _pathfind_lua,
}
ALGO_KEYS = list(ALGOS.keys())

# ── Colors ──────────────────────────────────────────
COLOR_OPEN  = (180, 160, 140)
COLOR_WALL  = (25, 25, 30)
COLOR_BG    = (15, 15, 18)
COLOR_GND   = (220, 40, 40)
COLOR_LONG  = (60, 140, 255)
COLOR_SHORT = (255, 200, 0)
COLOR_PLAY  = (200, 60, 255)
COLOR_TGT   = (255, 30, 30)

# ── Renderer with pre-rendered map ──────────────────
class BigGridRenderer:
    def __init__(self, world, win_w=1200, win_h=900):
        self.screen = pygame.display.set_mode((win_w, win_h), pygame.RESIZABLE)
        pygame.display.set_caption("Big Grid Explorer — Pathfinding Lab")
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("consolas", 13)
        self.win_w, self.win_h = win_w, win_h
        self.zoom = 1.0
        self.cx = world.width / 2.0
        self.cy = world.height / 2.0
        self.dragging = False
        self.drag_start = (0, 0)
        self.cam_start = (0.0, 0.0)
        self._map_surf = None
        self._build_map(world)
        self._auto_zoom(world.width, world.height, win_w, win_h)

    def _auto_zoom(self, ww, wh, vw, vh):
        self.zoom = min(vw / ww, vh / wh)
        self.cx, self.cy = ww / 2.0, wh / 2.0

    def _build_map(self, world):
        w, h = world.width, world.height
        surf = pygame.Surface((w, h))
        pix = pygame.PixelArray(surf)
        for y in range(h):
            row = world.cells[y]
            for x in range(w):
                pix[x, y] = COLOR_OPEN if row[x] else COLOR_WALL
        pix.close()
        self._map_surf = surf.convert()

    def rebuild_map(self, world):
        self._build_map(world)

    def world_to_screen(self, wx, wy):
        return ((wx - self.cx) * self.zoom + self.win_w / 2,
                (wy - self.cy) * self.zoom + self.win_h / 2)

    def screen_to_world(self, sx, sy):
        return ((sx - self.win_w / 2) / self.zoom + self.cx,
                (sy - self.win_h / 2) / self.zoom + self.cy)

    def _visible_rect(self, world):
        wx0, wy0 = self.screen_to_world(0, 0)
        wx1, wy1 = self.screen_to_world(self.win_w, self.win_h)
        return (max(0, int(wx0)), max(0, int(wy0)),
                min(world.width, int(wx1) + 1),
                min(world.height, int(wy1) + 1))

    def render(self, world, player_pos, path, elapsed_ms, algo_name, target_pos=None):
        self.screen.fill(COLOR_BG)
        x0, y0, x1, y1 = self._visible_rect(world)
        vw, vh = x1 - x0, y1 - y0
        if vw > 0 and vh > 0:
            sx0, sy0 = self.world_to_screen(x0, y0)
            sx1, sy1 = self.world_to_screen(x1, y1)
            dw, dh = int(sx1 - sx0), int(sy1 - sy0)
            if dw > 0 and dh > 0:
                try:
                    sub = self._map_surf.subsurface((x0, y0, vw, vh))
                except ValueError:
                    vw2 = min(vw, self._map_surf.get_width() - x0)
                    vh2 = min(vh, self._map_surf.get_height() - y0)
                    sub = self._map_surf.subsurface((x0, y0, vw2, vh2))
                    dw = max(1, dw); dh = max(1, dh)
                if dw != vw or dh != vh:
                    sub = pygame.transform.scale(sub, (dw, dh))
                self.screen.blit(sub, (int(sx0), int(sy0)))

        if len(path) >= 2 and len(path) < 10000:
            cell_sz = max(2, int(self.zoom))
            floating = [world.is_walkable(p[0], p[1] + 1) for p in path]
            long_run = [False] * len(path)
            rs = 0
            for i in range(1, len(path) + 1):
                flt = floating[i - 1] if i <= len(path) else True
                if not flt or i > len(path):
                    if i - 1 - rs >= 10:
                        for j in range(rs, i - 1): long_run[j] = True
                    rs = i
            for idx, (px, py) in enumerate(path):
                sx, sy = self.world_to_screen(px, py)
                on_gnd = not world.is_walkable(px, py + 1)
                if on_gnd:         c = COLOR_GND
                elif long_run[idx]: c = COLOR_LONG
                else:               c = COLOR_SHORT
                pygame.draw.rect(self.screen, c, (int(sx), int(sy), cell_sz, cell_sz))

        if target_pos:
            tx, ty = self.world_to_screen(*target_pos)
            tr = max(3, int(self.zoom * 0.8))
            pygame.draw.rect(self.screen, COLOR_TGT,
                             (int(tx - tr), int(ty - tr), tr * 2, tr * 2),
                             max(1, int(self.zoom * 0.3)))
        px, py = self.world_to_screen(*player_pos)
        pr = max(2, int(self.zoom * 0.6))
        pygame.draw.rect(self.screen, COLOR_PLAY, (int(px - pr), int(py - pr), pr * 2, pr * 2))

        if elapsed_ms > 0:
            big_font = pygame.font.SysFont("consolas", 28, bold=True)
            ts = big_font.render(f"{elapsed_ms:.0f} ms", True, (255, 50, 30))
            tx = self.win_w - ts.get_width() - 12
            pygame.draw.rect(self.screen, (10, 10, 14),
                             (tx - 4, 6, ts.get_width() + 8, ts.get_height() + 4))
            self.screen.blit(ts, (tx, 8))

        ft = sum(1 for p in path if world.is_walkable(p[0], p[1] + 1)) if path else 0
        gnd = len(path) - ft if path else 0
        lf = 0; run = 0
        for p in path:
            if world.is_walkable(p[0], p[1] + 1): run += 1
            else:
                if run >= 10: lf += run; run = 0
        if run >= 10: lf += run

        lines = [
            f"Zoom: {self.zoom:.3f}x  |  {algo_name}",
            f"Path: {len(path)} cells  |  {elapsed_ms:.0f}ms",
            f"RED=ground({gnd})  BLUE=float>={10}({lf})  GOLD=float<10({ft - lf})",
            f"View: {x0},{y0} - {x1},{y1}",
            "L-drag=pan  Wheel=zoom  R-click=target  T=find  R=regen  1-8=algo",
        ]
        for i, line in enumerate(lines):
            surf = self.font.render(line, True, (180, 180, 180))
            pygame.draw.rect(self.screen, (10, 10, 14),
                             (4, 4 + i * 18, surf.get_width() + 6, 18))
            self.screen.blit(surf, (7, 5 + i * 18))
        pygame.display.flip()
        self.clock.tick(60)

# ── Main loop ───────────────────────────────────────
def main():
    WORLD_W, WORLD_H = 1000, 1000
    pygame.init()

    print("Generating 1000x1000 cave...")
    world = GridWorld(WORLD_W, WORLD_H)
    generate_cave_large(world, intensity=2.0, seed=random.randint(0, 999999))

    open_count = sum(1 for y in range(WORLD_H) for x in range(WORLD_W)
                     if world.is_walkable(x, y))
    print(f"Map: {open_count}/1M open ({open_count / 10000:.1f}%)")

    cx, cy = WORLD_W // 2, WORLD_W // 2
    if not world.is_walkable(cx, cy):
        for dist in range(1, 100):
            ok = False
            for dy in range(-dist, dist + 1):
                for dx in range(-dist, dist + 1):
                    if world.is_walkable(cx + dx, cy + dy):
                        cx, cy = cx + dx, cy + dy; ok = True; break
                if ok: break
            if ok: break
    player_pos = (cx, cy)
    target_pos = None
    path = []
    algo_idx = 5  # default: Weighted (py)
    elapsed_ms = 0
    running = True

    renderer = BigGridRenderer(world)

    while running:
        for event in pygame.event.get():
            if event.type == QUIT or (event.type == KEYDOWN and event.key == K_ESCAPE):
                running = False
            elif event.type == KEYDOWN:
                if pygame.K_1 <= event.key <= pygame.K_8:
                    algo_idx = event.key - pygame.K_1
                elif event.key == pygame.K_t and target_pos:
                    algo_name = ALGO_KEYS[algo_idx]
                    algo_func = ALGOS[algo_name]
                    if algo_func in (_pathfind_c, _pathfind_lua):
                        path, elapsed_ms = algo_func(world, player_pos, target_pos)
                    else:
                        t0 = time.perf_counter()
                        result = algo_func(world, player_pos, target_pos)
                        elapsed_ms = (time.perf_counter() - t0) * 1000
                        path = result if result else []
                    print(f"{algo_name}: {elapsed_ms:.0f}ms, {len(path)} steps")
                elif event.key == pygame.K_r:
                    print("Regenerating...")
                    generate_cave_large(world, intensity=2.0,
                                        seed=random.randint(0, 999999))
                    renderer.rebuild_map(world)
                    cx2, cy2 = WORLD_W // 2, WORLD_W // 2
                    if not world.is_walkable(cx2, cy2):
                        for dist in range(1, 100):
                            ok = False
                            for dy in range(-dist, dist + 1):
                                for dx in range(-dist, dist + 1):
                                    if world.is_walkable(cx2 + dx, cy2 + dy):
                                        cx2, cy2 = cx2 + dx, cy2 + dy; ok = True; break
                                if ok: break
                            if ok: break
                    player_pos = (cx2, cy2)
                    path = []; target_pos = None; elapsed_ms = 0
            elif event.type == MOUSEBUTTONDOWN:
                mx, my = pygame.mouse.get_pos()
                if event.button == 4:   # wheel up
                    wx, wy = renderer.screen_to_world(mx, my)
                    renderer.zoom = min(20.0, renderer.zoom * 1.2)
                    renderer.cx = wx - (mx - renderer.win_w / 2) / renderer.zoom
                    renderer.cy = wy - (my - renderer.win_h / 2) / renderer.zoom
                elif event.button == 5: # wheel down
                    wx, wy = renderer.screen_to_world(mx, my)
                    renderer.zoom = max(0.02, renderer.zoom / 1.2)
                    renderer.cx = wx - (mx - renderer.win_w / 2) / renderer.zoom
                    renderer.cy = wy - (my - renderer.win_h / 2) / renderer.zoom
                elif event.button == 1: # left — start drag
                    renderer.dragging = True
                    renderer.drag_start = (mx, my)
                    renderer.cam_start = (renderer.cx, renderer.cy)
                elif event.button == 3: # right — set target
                    wx, wy = renderer.screen_to_world(mx, my)
                    wx, wy = int(wx), int(wy)
                    if world.is_walkable(wx, wy):
                        target_pos = (wx, wy)
            elif event.type == MOUSEBUTTONUP:
                if event.button == 1:
                    renderer.dragging = False
            elif event.type == MOUSEMOTION and renderer.dragging:
                mx, my = pygame.mouse.get_pos()
                dx = (mx - renderer.drag_start[0]) / renderer.zoom
                dy = (my - renderer.drag_start[1]) / renderer.zoom
                renderer.cx = renderer.cam_start[0] - dx
                renderer.cy = renderer.cam_start[1] - dy

        keys = pygame.key.get_pressed()
        pan = 50.0 / max(0.02, renderer.zoom)
        if keys[pygame.K_LEFT] or keys[pygame.K_a]:   renderer.cx -= pan
        if keys[pygame.K_RIGHT] or keys[pygame.K_d]:  renderer.cx += pan
        if keys[pygame.K_UP] or keys[pygame.K_w]:     renderer.cy -= pan
        if keys[pygame.K_DOWN] or keys[pygame.K_s]:   renderer.cy += pan

        renderer.render(world, player_pos, path, elapsed_ms,
                        ALGO_KEYS[algo_idx], target_pos)

    pygame.quit()

if __name__ == "__main__":
    main()
