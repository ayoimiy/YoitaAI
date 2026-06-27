"""
Pygame renderer — grid, player, paths, X marks, ray lines.
No text on screen; all info conveyed via colour and shape.
"""

import pygame
from config import (
    CELL_SIZE, WORLD_WIDTH, WORLD_HEIGHT, WINDOW_WIDTH, WINDOW_HEIGHT,
    CHUNK_SIZE, EDIT_TARGET, EDIT_DRAW, EDIT_ERASE,
    COLOR_BG, COLOR_OPEN, COLOR_GRID, COLOR_CHUNK_BORDER,
    COLOR_PLAYER, COLOR_PATH, COLOR_CURRENT_NODE,
    COLOR_OPEN_SET, COLOR_CLOSED_SET,
    COLOR_RAY_HIT, COLOR_RAY_CLEAR, COLOR_TARGET, COLOR_COMPONENT,
    COLOR_CURSOR_DRAW, COLOR_CURSOR_ERASE,
)


class Renderer:
    def __init__(self, width=WORLD_WIDTH, height=WORLD_HEIGHT):
        ww = width * CELL_SIZE
        wh = height * CELL_SIZE
        self.screen = pygame.display.set_mode((ww, wh), pygame.RESIZABLE)
        pygame.display.set_caption("Grid Explorer - Cave Pathfinding")
        self.clock = pygame.time.Clock()
        self.overlay = pygame.Surface((ww, wh), pygame.SRCALPHA)
        self.ray_surf = pygame.Surface((ww, wh), pygame.SRCALPHA)
        self._font = pygame.font.SysFont("consolas", 14)

    def resize(self, width, height):
        ww = width * CELL_SIZE
        wh = height * CELL_SIZE
        self.screen = pygame.display.set_mode((ww, wh), pygame.RESIZABLE)
        self.overlay = pygame.Surface((ww, wh), pygame.SRCALPHA)
        self.ray_surf = pygame.Surface((ww, wh), pygame.SRCALPHA)

    def cell_rect(self, cx, cy):
        return pygame.Rect(cx * CELL_SIZE, cy * CELL_SIZE, CELL_SIZE, CELL_SIZE)

    def cell_center(self, cx, cy):
        return (cx * CELL_SIZE + CELL_SIZE // 2, cy * CELL_SIZE + CELL_SIZE // 2)

    def _draw_x(self, cx, cy, color, ratio=0.35, width=2):
        """Draw an X mark sized slightly smaller than the cell."""
        px, py = self.cell_center(cx, cy)
        s = int(CELL_SIZE * ratio)
        pygame.draw.line(self.screen, color, (px - s, py - s), (px + s, py + s), width)
        pygame.draw.line(self.screen, color, (px + s, py - s), (px - s, py + s), width)

    def render(self, world, player, pf):
        """pf: dict with path, open_set, closed_set, current_node, target, rays, show_rays, component_cells"""
        self.screen.fill(COLOR_BG)

        # 1. Open cells
        for y in range(world.height):
            for x in range(world.width):
                if world.is_walkable(x, y):
                    pygame.draw.rect(self.screen, COLOR_OPEN, self.cell_rect(x, y))

        # 2. Grid lines
        for x in range(world.width + 1):
            px = x * CELL_SIZE
            pygame.draw.line(self.screen, COLOR_GRID, (px, 0), (px, world.height * CELL_SIZE))
        for y in range(world.height + 1):
            py = y * CELL_SIZE
            pygame.draw.line(self.screen, COLOR_GRID, (0, py), (world.width * CELL_SIZE, py))

        # 3. Chunk boundaries
        cs = CHUNK_SIZE * CELL_SIZE
        for cx in range(1, world.chunks_x):
            px = cx * cs
            pygame.draw.line(self.screen, COLOR_CHUNK_BORDER, (px, 0), (px, world.height * CELL_SIZE), 2)
        for cy in range(1, world.chunks_y):
            py = cy * cs
            pygame.draw.line(self.screen, COLOR_CHUNK_BORDER, (0, py), (world.width * CELL_SIZE, py), 2)

        # 4. Component overlay
        comp = pf.get("component_cells")
        if comp:
            self.overlay.fill((0, 0, 0, 0))
            for cx, cy in comp:
                pygame.draw.rect(self.overlay, COLOR_COMPONENT + (80,), self.cell_rect(cx, cy))
            self.screen.blit(self.overlay, (0, 0))

        # 5. Ray lines
        if pf.get("show_rays") and pf.get("rays"):
            self.ray_surf.fill((0, 0, 0, 0))
            for (ax, ay), (bx, by), hit in pf["rays"]:
                color = COLOR_RAY_HIT + (120,) if hit else COLOR_RAY_CLEAR + (120,)
                pygame.draw.line(self.ray_surf, color,
                                 self.cell_center(ax, ay),
                                 self.cell_center(bx, by), 2)
            self.screen.blit(self.ray_surf, (0, 0))

        # 6. Closed set X marks
        for cx, cy in pf.get("closed_set", set()):
            self._draw_x(cx, cy, COLOR_CLOSED_SET, ratio=0.36, width=2)

        # 7. Open set X marks (slightly larger for emphasis)
        for cx, cy in pf.get("open_set", set()):
            self._draw_x(cx, cy, COLOR_OPEN_SET, ratio=0.42, width=3)

        # 8. Current node — filled yellow, exact cell size
        curr = pf.get("current_node")
        if curr:
            cx, cy = curr
            r = self.cell_rect(cx, cy)
            pygame.draw.rect(self.screen, COLOR_CURRENT_NODE, r)

        # 9. Final path
        pts = pf.get("path", [])
        path_w = max(3, CELL_SIZE // 10)
        if len(pts) >= 2:
            pixel_pts = [self.cell_center(x, y) for (x, y) in pts]
            pygame.draw.lines(self.screen, COLOR_PATH, False, pixel_pts, path_w)
        elif len(pts) == 1:
            px, py = pts[0]
            pygame.draw.circle(self.screen, COLOR_PATH, self.cell_center(px, py), CELL_SIZE // 5)

        # 10. Target — red outline, exact cell size
        target = pf.get("target")
        if target:
            r = self.cell_rect(*target)
            pygame.draw.rect(self.screen, COLOR_TARGET, r, 3)

        # 11. Player — filled purple, exact cell size (always on top)
        px, py = player.pos()
        r = self.cell_rect(px, py)
        pygame.draw.rect(self.screen, COLOR_PLAYER, r)

        # 12. Working indicator — white dot at centre when pathfinding
        if pf.get("working"):
            cx, cy = self.cell_center(px, py)
            dot_r = max(3, CELL_SIZE // 10)
            pygame.draw.circle(self.screen, (255, 255, 255), (cx, cy), dot_r)

        # 13. Cursor indicator — circle in draw/erase mode
        edit_mode = pf.get("edit_mode", EDIT_TARGET)
        mc = pf.get("mouse_cell")
        if mc and edit_mode != EDIT_TARGET:
            cx, cy = mc
            color = COLOR_CURSOR_DRAW if edit_mode == EDIT_DRAW else COLOR_CURSOR_ERASE
            r = max(3, CELL_SIZE // 3)
            pygame.draw.circle(self.screen, color, self.cell_center(cx, cy), r, 2)

        # 14. HUD — top-left: mode + algo + intensity
        algo = pf.get("algo_name", "")
        intensity = pf.get("intensity", 1.0)
        mode_names = {EDIT_TARGET: "F: Target", EDIT_DRAW: "P: Draw", EDIT_ERASE: "E: Erase"}
        mode_label = mode_names.get(edit_mode, "")
        num_mode = pf.get("num_mode", "algo")
        num_label = f"[1-9: {'algo' if num_mode == 'algo' else 'MAP'}] N/M to switch"
        lines = [mode_label, num_label]
        if algo: lines.append(algo)
        lines.append(f"slot:{pf.get('map_slot',1)}  int:{intensity:.1f}")
        save_msg = pf.get("save_msg", "")
        if save_msg:
            lines.append(save_msg)
        if lines:
            widths = [self._font.render(l, True, (200,200,200)).get_width() for l in lines]
            bar_w = max(widths) + 10
            line_h = self._font.get_height()
            bar_h = len(lines) * line_h + 8
            pygame.draw.rect(self.screen, (10, 10, 14), (2, 2, bar_w, bar_h))
            for i, line in enumerate(lines):
                color = (120, 255, 120) if line.startswith("Saved") else (200, 200, 200)
                surf = self._font.render(line, True, color)
                self.screen.blit(surf, (6, 5 + i * line_h))

        pygame.display.flip()
        self.clock.tick(60)
