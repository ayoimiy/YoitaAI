# pathfind_c — Lua C Module for Noita Mod Pathfinding

Weighted A\* pathfinding with exponential flight fatigue, compiled as a Lua 5.1
C module (`pathfind_c.dll`).  Callable directly from Lua via `require()` — no
file I/O needed in production.

## Quick Start

```lua
local pf = require("pathfind_c")

-- Build a binary grid string (1 byte per cell, 1 = walkable, 0 = wall)
local data = ""
for y = 0, H - 1 do
    for x = 0, W - 1 do
        data = data .. string.char(is_walkable(x, y) and 1 or 0)
    end
end

local r = pf.compute(W, H, data, start_x, start_y, goal_x, goal_y)
if r and r.ok then
    for i = 1, r.len do
        local x, y, seg = r.px[i], r.py[i], r.seg[i]
        -- seg: 0=ground  1=short-float  2=long-float
    end
end
```

## Building

```bash
# From tools/pathfind_c/
# 1. Generate import library (one-time)
python gen_def.py                          # → lua51.def
dlltool -d lua51.def -l liblua51.a -D lua51/lua51.dll

# 2. Compile the DLL
gcc -O3 -shared -o pathfind_c.dll pathfind_module.c pathfind.c -I. -L. -llua51 -lm
```

Requires: GCC (MinGW/MSYS2 UCRT64), Lua 5.1 runtime DLLs (`lua5.1.dll` + `lua51.dll`).

## Runtime Requirements

Place these files in the same directory as `pathfind_c.dll` or in `package.cpath`:
- `pathfind_c.dll` — this module
- `lua5.1.dll`   — Lua 5.1 VM
- `lua51.dll`    — Lua C API forwarder

From a Lua script:
```lua
package.cpath = package.cpath .. ";./?.dll"   -- ensure DLL search path
local pf = require("pathfind_c")
```

## API Reference

### `pf.compute(w, h, data, sx, sy, gx, gy)`

In-memory pathfinding.  No file I/O.

**Parameters:**

| Param | Type    | Description                          |
|-------|---------|--------------------------------------|
| w     | integer | Map width (cells)                    |
| h     | integer | Map height (cells)                   |
| data  | string  | Binary grid: `data:byte(y*w+x+1) ~= 0` means walkable |
| sx    | integer | Start X (0-indexed)                  |
| sy    | integer | Start Y (0-indexed)                  |
| gx    | integer | Goal X (0-indexed)                   |
| gy    | integer | Goal Y (0-indexed)                   |

**Returns (on success):**  A Lua table:

```lua
{
    ok  = true,
    len = 651,        -- number of path steps
    ms  = 47,         -- algorithm time in milliseconds
    px  = {x0, x1, ...},  -- X coords, 1-indexed
    py  = {y0, y1, ...},  -- Y coords, 1-indexed
    seg = {s0, s1, ...},  -- segment types, 1-indexed
}
```

**Returns (on failure):** `nil, error_message`

**Segment types (`seg[i]`):**

| Value | Name          | Colour | Meaning                           |
|-------|---------------|--------|-----------------------------------|
| 0     | `SEG_GROUND`  | RED    | Cell below is solid (on ground)   |
| 1     | `SEG_SHORT`   | GOLD   | Airborne, < 10 consecutive steps  |
| 2     | `SEG_LONG`    | BLUE   | Airborne, ≥ 10 consecutive steps  |

The segment classification matches the colour scheme in `mode_big.py`:
- **RED**   = entity has solid ground underfoot
- **GOLD**  = short jump / gap crossing
- **BLUE**  = extended flight (the "long float" the weighted heuristic penalises)

### `pf.find(infile, outfile)`

File-based interface — mainly for offline benchmarking.

Reads `infile` (binary format: 6 × int32 header + w×h bytes grid),
writes `outfile` (int32 len + int32 ms + len int32s px + len int32s py).

Returns `len, ms`.

This matches the format used by `bridge.c` / `pf_bridge.exe` and `mode_big.py`.

## Noita Mod Integration

```lua
-- In your mod's init.lua or a helper module:
local pf = require("pathfind_c")

function mod_pathfind(grid_w, grid_h, is_walkable_fn, sx, sy, gx, gy)
    -- Serialise the walkable-grid to a binary string
    local data = ""
    for y = 0, grid_h - 1 do
        for x = 0, grid_w - 1 do
            data = data .. string.char(is_walkable_fn(x, y) and 1 or 0)
        end
    end

    local r = pf.compute(grid_w, grid_h, data, sx, sy, gx, gy)
    if not r or not r.ok then
        return nil  -- no path
    end

    return r
end

-- Example: navigate an entity along the path
local result = mod_pathfind(100, 80, WorldIsWalkable, player_x, player_y, goal_x, goal_y)
if result then
    for i = 1, result.len do
        local seg = result.seg[i]
        if seg == 2 then
            -- LONG_FLOAT: prepare for extended flight
            -- TODO: check flight energy before takeoff (see Design Notes below)
        elseif seg == 1 then
            -- SHORT_FLOAT: small hop
        end
        -- Move entity toward (result.px[i], result.py[i])
    end
end
```

## Algorithm

Weighted A\* with exponential flight fatigue, matching the Python reference
in `algo/pathfind.py` and the C implementation in `pathfind.c`.

- **State space**: `(x, y, air_count)` where `air_count ∈ [0, 15]`
- **Heuristic**: octile distance
- **Tie-breaking**: `f_score + state_index × 1e-12` (deterministic)
- **Movement costs**: 1.0 (cardinal), 1.5 (diagonal)
- **Ground bonus**: −0.7 movement cost, min 0.1
- **Flight penalty**: exponential growth with consecutive air time
  - Up: `2.0 × 1.30ⁿ⁻¹`
  - Horizontal: `0.5 × 1.20ⁿ⁻¹`
  - Down: `0.5 + 0.08×n`
- **Landing tax**: +1.0 when transitioning from air to ground
- **Takeoff tax**: +0.5 when leaving ground
- **Max iterations**: 2,000,000

## Design Notes — Future Work

### Flight-Energy Gate (pre-takeoff check)

In Noita, the player/entity has a limited flight energy that recharges while on
the ground.  The weighted pathfinder already models flight cost through
exponential air penalties, but it does **not** currently gate takeoff on
available energy.

A future version should add a **pre-takeoff energy check**: when the path's next
step transitions from ground (seg=0) into the air (seg=1 or 2), and the
accumulated flight cost of the upcoming airborne segment exceeds the entity's
current energy reserve, insert a **wait-on-ground** waypoint.  The entity stays
at the edge until energy recharges sufficiently, then takes off.

This maps to the segment classification as follows:
```
seg[i] == 0  and  seg[i+1] != 0  →  potential takeoff point
  → check: sum_flight_cost(upcoming_airborne_run) > current_energy ?
      yes → insert hold position, wait for recharge
      no  → proceed with takeoff
```

This is noted here as a design direction; the current `compute()` returns raw
segment types so the caller (mod Lua) can implement this logic externally until
it is built into the C layer.
