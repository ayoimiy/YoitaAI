"""
Spatial memory system (cloned from YoitaAI files/scripts/memory/manager.lua).

Key components:
  - Direction   : cardinal direction with negation
  - NodeSet     : set of grid cells within a chunk, keyed by local ID
  - Chunk / Block : spatial partitioning and connected-component tracking
  - raytrace5   : 5-ray collision check (adapted from Noita RaytracePlatforms)
  - bfs         : flood-fill connected component discovery
  - Edge fingerprint : 16-byte hash of chunk boundary occupancy
  - floor_fill  : main scanning function — incremental block matching
"""

import math
from collections import deque

from config import CHUNK_SIZE, NODE_SPACING, RAYTRACE_OFFSETS, RAYTRACE_BLOCK_THRESHOLD

# ═══════════════════════════════════════════════════════════════
#  Direction
# ═══════════════════════════════════════════════════════════════

class Direction:
    """Cardinal direction with support for negation and equality."""
    __slots__ = ('dx', 'dy')

    def __init__(self, dx, dy):
        self.dx = dx
        self.dy = dy

    def __neg__(self):
        return Direction(-self.dx, -self.dy)

    def __eq__(self, other):
        if not isinstance(other, Direction):
            return False
        return self.dx == other.dx and self.dy == other.dy

    def __hash__(self):
        return hash((self.dx, self.dy))

    def to_key(self):
        return f"{self.dx}_{self.dy}"


LEFT    = Direction(-1, 0)
RIGHT   = Direction(1, 0)
TOP     = Direction(0, -1)
BOTTOM  = Direction(0, 1)

DIRECTIONS = [LEFT, RIGHT, TOP, BOTTOM]


# ═══════════════════════════════════════════════════════════════
#  NodeSet
# ═══════════════════════════════════════════════════════════════

class NodeSet:
    """
    A set of grid cells within one chunk, keyed by integer ID.

    ID = (local_x // NODE_SPACING) + (local_y // NODE_SPACING) * nodes_per_row
    """

    def __init__(self):
        self.nodes = {}   # id → bool (visited flag for BFS)
        self.count = 0

    # ── Adding ───────────────────────────────────────
    def add(self, wx, wy, chunk_ox, chunk_oy):
        """Add a world-coord cell to this set. Returns its ID."""
        id_ = self._get_id(wx, wy, chunk_ox, chunk_oy)
        self.add_from_id(id_)
        return id_

    def add_from_id(self, id_):
        self.nodes[id_] = False
        self.count += 1

    # ── Coordinate helpers ───────────────────────────
    @staticmethod
    def _nodes_per_row():
        return (CHUNK_SIZE // NODE_SPACING) + 1

    @staticmethod
    def _get_id(wx, wy, chunk_ox, chunk_oy):
        lx = (wx - chunk_ox) // NODE_SPACING
        ly = (wy - chunk_oy) // NODE_SPACING
        npr = NodeSet._nodes_per_row()
        return lx + ly * npr

    @staticmethod
    def get_pos(id_, chunk_ox, chunk_oy):
        """Convert an ID back to world coordinates."""
        npr = NodeSet._nodes_per_row()
        lx = id_ % npr
        ly = id_ // npr
        return (lx * NODE_SPACING + chunk_ox, ly * NODE_SPACING + chunk_oy)

    # ── State ────────────────────────────────────────
    def get_state(self, id_):
        return self.nodes.get(id_)

    def set_state(self, id_, state):
        if id_ in self.nodes:
            self.nodes[id_] = state
            return True
        return False

    def exist(self, id_):
        return id_ in self.nodes

    def exist2(self, wx, wy, chunk_ox, chunk_oy):
        """Check existence by world coords. Returns (exists, id)."""
        id_ = self._get_id(wx, wy, chunk_ox, chunk_oy)
        return (id_ in self.nodes), id_

    # ── Neighbors (Manhattan-adjacent IDs in the same set) ──
    def get_neighbors(self, id_):
        """Return list of existing neighbor IDs (4-directional)."""
        npr = NodeSet._nodes_per_row()
        lx = id_ % npr
        ly = id_ // npr
        result = []
        for d in DIRECTIONS:
            nx, ny = lx + d.dx, ly + d.dy
            if 0 <= nx < npr and 0 <= ny < npr:
                nid = nx + ny * npr
                if nid in self.nodes:
                    result.append(nid)
        return result

    @staticmethod
    def get_distance(id1, id2):
        npr = NodeSet._nodes_per_row()
        lx1, ly1 = id1 % npr, id1 // npr
        lx2, ly2 = id2 % npr, id2 // npr
        return abs(lx1 - lx2) + abs(ly1 - ly2)

    # ── Edge / inner node extraction ─────────────────
    def get_edges_nodes(self):
        """Return a new NodeSet containing only boundary cells."""
        npr = NodeSet._nodes_per_row()
        out = NodeSet()
        for id_ in self.nodes:
            lx = id_ % npr
            ly = id_ // npr
            if lx == 0 or lx == npr - 1 or ly == 0 or ly == npr - 1:
                out.add_from_id(id_)
        return out

    def get_inner_nodes(self):
        """Return a new NodeSet containing only non-boundary cells."""
        npr = NodeSet._nodes_per_row()
        out = NodeSet()
        for id_ in self.nodes:
            lx = id_ % npr
            ly = id_ // npr
            if 0 < lx < npr - 1 and 0 < ly < npr - 1:
                out.add_from_id(id_)
        return out

    # ── Export ───────────────────────────────────────
    def to_nodes(self, chunk_ox, chunk_oy):
        """Export as {(world_x, world_y): bool} dict."""
        out = {}
        for id_, state in self.nodes.items():
            pos = NodeSet.get_pos(id_, chunk_ox, chunk_oy)
            out[pos] = state
        return out


# ═══════════════════════════════════════════════════════════════
#  Raytrace5 — collision detection
# ═══════════════════════════════════════════════════════════════

def bresenham_line(x0, y0, x1, y1):
    """Yield all integer grid cells along the line from (x0,y0) to (x1,y1)."""
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    cx, cy = x0, y0
    while True:
        yield (cx, cy)
        if cx == x1 and cy == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            if cx == x1:
                break
            err += dy
            cx += sx
        if e2 <= dx:
            if cy == y1:
                break
            err += dx
            cy += sy


def raytrace5(world, from_node, to_node):
    """
    5-ray check between two nodes (world coords (x, y)).
    Uses 4 corner offsets plus centre.

    Returns: (count_hit, ray_results)
      count_hit   — number of rays that hit a wall (int)
      ray_results — list of (from_px, to_px, hit_bool) tuples for viz
    """
    offsets = [(0, 0)] + list(RAYTRACE_OFFSETS)  # centre + 4 corners
    count_hit = 0
    ray_results = []

    fx, fy = from_node
    tx, ty = to_node
    for ox, oy in offsets:
        hit = False
        prev_cell = None
        for cx, cy in bresenham_line(fx + ox, fy + oy, tx + ox, ty + oy):
            cell = (cx, cy)
            if cell != (fx + ox, fy + oy) and cell != (tx + ox, ty + oy):
                if not world.is_walkable(cx, cy):
                    hit = True
                    break
            prev_cell = cell
        if hit:
            count_hit += 1
        ray_results.append(((fx + ox, fy + oy), (tx + ox, ty + oy), hit))

    return count_hit, ray_results


def is_connection_blocked(world, from_node, to_node):
    """True if the 5-ray check considers the connection blocked."""
    count, _ = raytrace5(world, from_node, to_node)
    return count >= RAYTRACE_BLOCK_THRESHOLD


# ═══════════════════════════════════════════════════════════════
#  BFS — flood-fill connected components
# ═══════════════════════════════════════════════════════════════

def bfs(world, nodes, edge_set, start_node, chunk_ox, chunk_oy):
    """
    BFS flood-fill from start_node within `nodes`.
    Skips edge-to-edge connections (prevents bleeding across chunks).

    Returns a new NodeSet containing the connected component.
    """
    component = NodeSet()
    queue = deque([start_node])

    nodes.set_state(start_node, True)
    component.add_from_id(start_node)

    while queue:
        node = queue.popleft()
        x, y = NodeSet.get_pos(node, chunk_ox, chunk_oy)

        for nid in nodes.get_neighbors(node):
            if nodes.get_state(nid) is False:
                nx, ny = NodeSet.get_pos(nid, chunk_ox, chunk_oy)
                # check connectivity via raytrace5
                count, _ = raytrace5(world, (x, y), (nx, ny))
                if count < RAYTRACE_BLOCK_THRESHOLD:
                    # skip edge-to-edge connections
                    if not (edge_set.exist(node) and edge_set.exist(nid)):
                        queue.append(nid)
                        nodes.set_state(nid, True)
                        component.add_from_id(nid)

    return component


# ═══════════════════════════════════════════════════════════════
#  Edge fingerprint encoding
# ═══════════════════════════════════════════════════════════════

# The 4 chunk edges, described as (direction, (x_start, y_start, x_end, y_end))
# in local-index space.
def _edge_iter(npr):
    """Yield (direction, local_x, local_y) for all boundary positions."""
    # Top edge (y=0)
    for x in range(1, npr - 1):
        yield TOP, x, 0
    # Bottom edge (y=npr-1)
    for x in range(1, npr - 1):
        yield BOTTOM, x, npr - 1
    # Left edge (x=0)
    for y in range(1, npr - 1):
        yield LEFT, 0, y
    # Right edge (x=npr-1)
    for y in range(1, npr - 1):
        yield RIGHT, npr - 1, y


def encode_edge_key(node_set):
    """Encode the boundary occupancy of a NodeSet into a 16-byte fingerprint."""
    npr = NodeSet._nodes_per_row()
    bits = bytearray(16)
    count = 0
    for _dir, lx, ly in _edge_iter(npr):
        id_ = lx + ly * npr
        byte_idx = count // 8
        bit = count % 8
        if node_set.exist(id_):
            bits[byte_idx] |= (1 << bit)
        count += 1
    return bytes(bits)


def decode_edge_key(key, direction=None):
    """Decode a 16-byte fingerprint back into a NodeSet, optionally filtered by direction."""
    npr = NodeSet._nodes_per_row()
    out = NodeSet()
    count = 0
    for dr, lx, ly in _edge_iter(npr):
        byte_idx = count // 8
        bit = count % 8
        if byte_idx < len(key) and (key[byte_idx] >> bit) & 1:
            if direction is None or dr == direction:
                id_ = lx + ly * npr
                out.add_from_id(id_)
        count += 1
    return out


# ═══════════════════════════════════════════════════════════════
#  Chunk
# ═══════════════════════════════════════════════════════════════

class Chunk:
    """A subdivision of the world grid.  Tracks its Block IDs."""
    __slots__ = ('cx', 'cy', 'blocks')

    def __init__(self, cx, cy):
        self.cx = cx
        self.cy = cy
        self.blocks = []  # list of block IDs

    def origin(self):
        return (self.cx * CHUNK_SIZE, self.cy * CHUNK_SIZE)

    @staticmethod
    def get_key(world_x, world_y):
        return (world_x // CHUNK_SIZE, world_y // CHUNK_SIZE)

    def to_nodes(self, world):
        """Sample the chunk's cells → NodeSet of walkable positions."""
        ox, oy = self.origin()
        nodes = NodeSet()
        for dy in range(0, CHUNK_SIZE, NODE_SPACING):
            for dx in range(0, CHUNK_SIZE, NODE_SPACING):
                wx, wy = ox + dx, oy + dy
                if not world.in_bounds(wx, wy):
                    continue
                # "check_node": a cell is usable if it is walkable
                if world.is_walkable(wx, wy):
                    nodes.add(wx, wy, ox, oy)
        return nodes

    def get_components(self, world):
        """Run BFS on inner nodes to discover connected components."""
        ox, oy = self.origin()
        nodes = self.to_nodes(world)
        edge_set = nodes.get_edges_nodes()
        inner_set = nodes.get_inner_nodes()

        comps = []
        for node_id in inner_set.nodes:
            if nodes.get_state(node_id) is False:
                comp = bfs(world, nodes, edge_set, node_id, ox, oy)
                if comp.count > 1:
                    comps.append(comp)
        return comps


# ═══════════════════════════════════════════════════════════════
#  Block
# ═══════════════════════════════════════════════════════════════

_block_id_counter = 0


def _next_block_id():
    global _block_id_counter
    _block_id_counter += 1
    return _block_id_counter


class Block:
    """A connected component that spans part of a chunk."""
    __slots__ = ('id', 'hash_key', 'chunk_key', 'neighbors')

    def __init__(self, hash_key, chunk_key):
        self.id = _next_block_id()
        self.hash_key = hash_key    # bytes (16-byte fingerprint)
        self.chunk_key = chunk_key  # (cx, cy)
        self.neighbors = {}         # block_id → True, or chunk_key_str → True


# ═══════════════════════════════════════════════════════════════
#  Global state
# ═══════════════════════════════════════════════════════════════

# chunk_key (cx,cy) → Chunk
_chunk_data = {}
# block_id → Block
_block_data = {}
# block_id → NodeSet (the actual walkable cells of that block)
_block_nodes = {}


# ═══════════════════════════════════════════════════════════════
#  Block lifecycle
# ═══════════════════════════════════════════════════════════════

def _clean_old_block(block_id):
    """Remove a stale block and its neighbor references."""
    block = _block_data.pop(block_id, None)
    if block is None:
        return
    _block_nodes.pop(block_id, None)
    chunk = _chunk_data.get(block.chunk_key)
    if chunk:
        # Remove neighbor references from adjacent chunks
        for dr in DIRECTIONS:
            ncx, ncy = block.chunk_key[0] + dr.dx, block.chunk_key[1] + dr.dy
            nchunk = _chunk_data.get((ncx, ncy))
            if nchunk:
                for nbid in nchunk.blocks:
                    nb = _block_data.get(nbid)
                    if nb and block_id in nb.neighbors:
                        del nb.neighbors[block_id]


def _get_intersection(set1, set2):
    """Return (common_keys_dict, count) of two {pos: bool} dicts."""
    common = {}
    cnt = 0
    for k in set1:
        if k in set2:
            common[k] = True
            cnt += 1
    return common, cnt


def _create_new_block(block_fps, chunk_key):
    """Create a new Block and wire up cross-chunk neighbor relationships."""
    block = Block(block_fps, chunk_key)
    _block_data[block.id] = block
    chunk = _chunk_data[chunk_key]
    ox, oy = chunk.origin()

    for dr in DIRECTIONS:
        ncx, ncy = chunk_key[0] + dr.dx, chunk_key[1] + dr.dy
        nkey = (ncx, ncy)
        nchunk = _chunk_data.get(nkey)

        if nchunk:
            for nbid in nchunk.blocks:
                nblock = _block_data.get(nbid)
                if nblock is None:
                    continue
                # Decode both blocks' edge fingerprints in opposite directions
                nedge = decode_edge_key(nblock.hash_key, -dr)
                edge = decode_edge_key(block.hash_key, dr)

                nox, noy = nchunk.origin()
                inter, cnt = _get_intersection(
                    nedge.to_nodes(nox, noy),
                    edge.to_nodes(ox, oy),
                )
                if cnt > 0:
                    block.neighbors[nbid] = True
                    nblock.neighbors[block.id] = True
                    # Clear placeholder chunk-key entries
                    nblock.neighbors.pop(str(chunk_key), None)

            # Clear placeholder
            block.neighbors.pop(str(nkey), None)
        else:
            # Neighbor chunk not yet scanned → leave a placeholder
            edge = decode_edge_key(block.hash_key, dr)
            if edge.count > 0:
                block.neighbors[str(nkey)] = True

    return block


# ═══════════════════════════════════════════════════════════════
#  floor_fill — the main scanning function
# ═══════════════════════════════════════════════════════════════

def floor_fill(world, chunk_key):
    """
    Scan a chunk, find connected components, and update block data.

    Returns: (blocks_dict, is_changed)
      blocks_dict: block_id → NodeSet
      is_changed:  True if any blocks were added or removed
    """
    # Ensure chunk exists
    if chunk_key not in _chunk_data:
        _chunk_data[chunk_key] = Chunk(*chunk_key)
    chunk = _chunk_data[chunk_key]

    is_changed = False
    comps = chunk.get_components(world)

    # Compute fingerprints for new components
    comps_fps = [encode_edge_key(c) for c in comps]

    # Match new fingerprints against old blocks
    old_block_ids = list(chunk.blocks)
    matched = {}   # comp_index → old_block_index
    used_old = set()

    for i, fp in enumerate(comps_fps):
        for j, bid in enumerate(old_block_ids):
            if j not in used_old and bid in _block_data:
                if fp == _block_data[bid].hash_key:
                    matched[i] = j
                    used_old.add(j)
                    break

    # Remove unmatched old blocks
    for j, bid in enumerate(old_block_ids):
        if j not in used_old:
            _clean_old_block(bid)
            is_changed = True

    # Build new block list
    new_block_ids = []
    blocks_out = {}

    for i, comp in enumerate(comps):
        if i in matched:
            bid = old_block_ids[matched[i]]
        else:
            block = _create_new_block(comps_fps[i], chunk_key)
            bid = block.id
            is_changed = True
        new_block_ids.append(bid)
        blocks_out[bid] = comp

    chunk.blocks = new_block_ids
    _block_nodes.update(blocks_out)

    return blocks_out, is_changed


# ═══════════════════════════════════════════════════════════════
#  Manager — public API
# ═══════════════════════════════════════════════════════════════

def reset_spatial_memory():
    """Clear all spatial memory (for map regeneration)."""
    global _block_id_counter
    _chunk_data.clear()
    _block_data.clear()
    _block_nodes.clear()
    _block_id_counter = 0


def get_chunk_key(x, y):
    """World coordinates → chunk key."""
    return Chunk.get_key(x, y)


def get_block_chunk_key(block_id):
    """block_id → its chunk_key."""
    blk = _block_data.get(block_id)
    if blk:
        return blk.chunk_key
    return (0, 0)


def get_block_neighbors(block_id):
    """Return list of neighbor IDs for a block (numbers = known blocks, strings = unknown chunks)."""
    blk = _block_data.get(block_id)
    if blk is None:
        return []
    return list(blk.neighbors.keys())


def get_block_distance(chunk_key1, chunk_key2):
    """Manhattan distance between two chunk keys (in chunk units)."""
    return abs(chunk_key1[0] - chunk_key2[0]) + abs(chunk_key1[1] - chunk_key2[1])


def get_block_edge(world, from_node, to_node):
    """
    Get the set of "door" positions on the shared edge between two blocks/chunks.
    Returns {(world_x, world_y): bool}.
    """
    if not isinstance(from_node, int):
        return {}

    block1 = _block_data.get(from_node)
    if block1 is None:
        return {}

    chunk1 = _chunk_data.get(block1.chunk_key)
    if chunk1 is None:
        return {}
    o1x, o1y = chunk1.origin()

    target_set = {}

    if isinstance(to_node, str):
        # to_node is a chunk key string like "(cx, cy)"
        ncx, ncy = eval(to_node)
        dr = Direction(ncx - chunk1.cx, ncy - chunk1.cy)
        edge = decode_edge_key(block1.hash_key, dr)
        for (ex, ey), _ in edge.to_nodes(o1x, o1y).items():
            nx, ny = ex + dr.dx * NODE_SPACING, ey + dr.dy * NODE_SPACING
            if world.is_walkable(nx, ny) and not is_connection_blocked(world, (ex, ey), (nx, ny)):
                target_set[(nx, ny)] = True
    elif isinstance(to_node, int):
        # to_node is a block ID
        block2 = _block_data.get(to_node)
        if block2 is None:
            return {}
        chunk2 = _chunk_data.get(block2.chunk_key)
        if chunk2 is None:
            return {}
        o2x, o2y = chunk2.origin()
        dr = Direction(chunk2.cx - chunk1.cx, chunk2.cy - chunk1.cy)

        edge1 = decode_edge_key(block1.hash_key, dr).to_nodes(o1x, o1y)
        edge2 = decode_edge_key(block2.hash_key, -dr).to_nodes(o2x, o2y)
        inter, _ = _get_intersection(edge1, edge2)

        for (ex, ey) in inter:
            nx, ny = ex + dr.dx * NODE_SPACING, ey + dr.dy * NODE_SPACING
            if world.is_walkable(nx, ny) and not is_connection_blocked(world, (ex, ey), (nx, ny)):
                target_set[(nx, ny)] = True

    return target_set


def get_node_set_for_block(block_id):
    """Return the NodeSet for a given block ID."""
    return _block_nodes.get(block_id)


def find_near_block(world, wx, wy, chunk_key):
    """Find which block (if any) contains the given world position."""
    for bid, nodeset in _block_nodes.items():
        exists, _ = nodeset.exist2(wx, wy, *(_chunk_data[chunk_key].origin()))
        if exists:
            return bid
    return None
