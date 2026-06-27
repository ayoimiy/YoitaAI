"""
Grid Explorer — configuration constants
All tunable parameters are defined here.
"""

# ── Window / Grid ──────────────────────────────────
CELL_SIZE = 40              # pixels per cell side
WORLD_WIDTH = 20            # cells (adjustable via command)
WORLD_HEIGHT = 20           # cells
WINDOW_WIDTH = WORLD_WIDTH * CELL_SIZE
WINDOW_HEIGHT = WORLD_HEIGHT * CELL_SIZE
FPS = 60

# ── Spatial memory ─────────────────────────────────
CHUNK_SIZE = 10             # cells per chunk side
NODE_SPACING = 1            # sample every N cells (1 = every cell)
RAYTRACE_OFFSETS = [(-2, -4), (2, -4), (-2, 4), (2, 4)]  # scaled-down offsets for 20x20
RAYTRACE_BLOCK_THRESHOLD = 3

# ── Map generation defaults ────────────────────────
DEFAULT_MODE = "walk"           # "walk" (random walk) or "cave" (cellular automata)
DEFAULT_INTENSITY = 1.0         # random walk intensity (0.5–3.0)
DEFAULT_CAVE_FILL = 0.45        # cave: initial fill ratio
DEFAULT_CAVE_ITERATIONS = 5     # cave: CA smoothing passes
DEFAULT_CAVE_WALL_NEED = 5      # cave: wall threshold (4-6)
DEFAULT_SEED = 42

# ── Pathfinding ────────────────────────────────────
ASTAR_MAX_ITER = 5000
DEFAULT_PATHFIND_INTERVAL = 0.001  # seconds between each A* node expansion

# ── Edit modes ─────────────────────────────────────
EDIT_TARGET = "target"   # F key — set pathfinding target (default)
EDIT_DRAW   = "draw"     # P key — paint walls
EDIT_ERASE  = "erase"    # E key — remove walls

# ── Colors (R, G, B) ───────────────────────────────
COLOR_BG = (15, 15, 18)            # wall / background (deep charcoal)
COLOR_CURSOR_DRAW  = (40, 40, 40)  # black circle for draw mode
COLOR_CURSOR_ERASE = (60, 255, 80) # green circle for erase mode
COLOR_OPEN = (220, 200, 170)       # cave floor (warm sand)
COLOR_GRID = (55, 55, 60)          # grid lines
COLOR_CHUNK_BORDER = (90, 90, 95)  # chunk boundary
COLOR_PLAYER = (200, 60, 255)      # vivid purple
COLOR_PATH = (255, 220, 0)         # bright gold path
COLOR_CURRENT_NODE = (255, 255, 50) # vivid yellow — current node
COLOR_OPEN_SET = (50, 255, 80)     # neon green X marks (open set)
COLOR_CLOSED_SET = (80, 160, 255)  # electric blue X marks (closed set)
COLOR_RAY_HIT = (255, 40, 40)      # vivid red — ray hit
COLOR_RAY_CLEAR = (40, 255, 60)    # neon green — ray clear
COLOR_TARGET = (255, 30, 30)       # bright red target outline
COLOR_COMPONENT = (140, 180, 255)  # vivid light blue overlay

# ── Logging ────────────────────────────────────────
LOG_DIR = ""
LOG_LEVEL = 2  # INFO
