"""
2D grid world — cell storage and chunk division (cloned from manager.lua Chunk system).
"""

from config import WORLD_WIDTH, WORLD_HEIGHT, CHUNK_SIZE


class GridWorld:
    """A 2D grid of bool cells.  True = open/walkable, False = wall/solid."""

    def __init__(self, width=WORLD_WIDTH, height=WORLD_HEIGHT):
        self.width = width
        self.height = height
        self.cells = [[False] * width for _ in range(height)]
        self.chunk_size = CHUNK_SIZE
        # Number of chunks in each dimension
        self.chunks_x = (width + CHUNK_SIZE - 1) // CHUNK_SIZE
        self.chunks_y = (height + CHUNK_SIZE - 1) // CHUNK_SIZE

    # ── Cell access ────────────────────────────────────
    def in_bounds(self, x, y):
        return 0 <= x < self.width and 0 <= y < self.height

    def is_walkable(self, x, y):
        if not self.in_bounds(x, y):
            return False
        return self.cells[y][x]

    def set_cell(self, x, y, walkable):
        if self.in_bounds(x, y):
            self.cells[y][x] = walkable

    def fill_all(self, walkable):
        for y in range(self.height):
            for x in range(self.width):
                self.cells[y][x] = walkable

    # ── Chunk helpers ──────────────────────────────────
    @staticmethod
    def get_chunk_key(world_x, world_y):
        """Return (cx, cy) chunk coordinates for a world position."""
        return (world_x // CHUNK_SIZE, world_y // CHUNK_SIZE)

    def chunk_origin(self, cx, cy):
        """Top-left world coordinates of chunk (cx, cy)."""
        return (cx * CHUNK_SIZE, cy * CHUNK_SIZE)

    def iter_chunks(self):
        """Yield (chunk_key, cx, cy) for all chunks."""
        for cy in range(self.chunks_y):
            for cx in range(self.chunks_x):
                yield ((cx, cy), cx, cy)

    def chunk_cells(self, cx, cy):
        """Return list of (x, y) world coords inside chunk (cx, cy)."""
        ox, oy = self.chunk_origin(cx, cy)
        cells = []
        for dy in range(CHUNK_SIZE):
            for dx in range(CHUNK_SIZE):
                wx, wy = ox + dx, oy + dy
                if self.in_bounds(wx, wy):
                    cells.append((wx, wy))
        return cells
