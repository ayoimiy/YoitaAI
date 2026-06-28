-- segment_demo.lua — Path segment classifier demo
-- Usage: lua5.1 segment_demo.lua <input.bin>
--
-- Reads a binary map (same format as pf_in.bin), runs pathfinding via
-- pathfind_c.compute(), and prints the path with segment-type colour coding.
--
-- Segment types (matches mode_big.py renderer colours):
--   SEG_GROUND      (0) = RED    — cell below is solid
--   SEG_SHORT_FLOAT (1) = GOLD   — airborne < 10 consecutive steps
--   SEG_LONG_FLOAT  (2) = BLUE   — airborne >= 10 consecutive steps

local pf = require("pathfind_c")

-- ── ANSI colour codes ──────────────────────────────
local RED   = "\27[31m"
local GOLD  = "\27[33m"
local BLUE  = "\27[34m"
local RESET = "\27[0m"
local SEG_LABEL = { [0]="GROUND     ", [1]="SHORT_FLOAT", [2]="LONG_FLOAT " }
local SEG_COLOR = { [0]=RED,          [1]=GOLD,          [2]=BLUE }

-- ── Read input ─────────────────────────────────────
local infile = arg[1] or "pf_in.bin"
local fi = io.open(infile, "rb")
if not fi then print("Cannot open " .. infile); os.exit(1) end

local function ri()
    local b1,b2,b3,b4 = fi:read(4):byte(1,4)
    return b1 + b2*256 + b3*65536 + b4*16777216
end
local W, H   = ri(), ri()
local sx, sy = ri(), ri()
local gx, gy = ri(), ri()
local data   = fi:read(W * H)
fi:close()

-- ── Run pathfinding ────────────────────────────────
local r = pf.compute(W, H, data, sx, sy, gx, gy)
if not r then
    print("ERROR: pathfinding failed")
    os.exit(1)
end

-- ── Statistics ─────────────────────────────────────
local counts = {0, 0, 0}
for i = 1, r.len do
    counts[r.seg[i] + 1] = (counts[r.seg[i] + 1] or 0) + 1
end

print(string.format("Map: %dx%d  start=(%d,%d)  goal=(%d,%d)", W, H, sx, sy, gx, gy))
print(string.format("Path: %d steps  time: %dms", r.len, r.ms))
print(string.format("Segments:  %sGROUND%s=%d  %sSHORT%s=%d  %sLONG%s=%d",
    RED, RESET, counts[1],
    GOLD, RESET, counts[2],
    BLUE, RESET, counts[3]))
print()

-- ── Print path with colour ─────────────────────────
print(" Step   X      Y    Segment")
print("------ ----- -----   -------------")
for i = 1, r.len do
    local t  = r.seg[i]
    local c  = SEG_COLOR[t] or RESET
    local lb = SEG_LABEL[t] or "UNKNOWN"
    print(string.format(" %s%4d%s  %s%5d%s %s%5d%s   %s%s%s",
        c, i, RESET,
        c, r.px[i], RESET,
        c, r.py[i], RESET,
        c, lb, RESET))
end
print()

-- ── Compact segment-run summary ─────────────────────
print("Run summary (contiguous segments):")
local cur_type = r.seg[1]
local run_start = 1
for i = 2, r.len do
    if r.seg[i] ~= cur_type then
        local c = SEG_COLOR[cur_type] or RESET
        local lb = SEG_LABEL[cur_type] or "UNKNOWN"
        print(string.format("  %ssteps %3d-%3d (%2d): %s%s",
            c, run_start, i-1, i - run_start, lb, RESET))
        cur_type = r.seg[i]
        run_start = i
    end
end
-- Last run
local c = SEG_COLOR[cur_type] or RESET
local lb = SEG_LABEL[cur_type] or "UNKNOWN"
print(string.format("  %ssteps %3d-%3d (%2d): %s%s",
    c, run_start, r.len, r.len - run_start + 1, lb, RESET))

print("\nDone.")
