-- weighted_runner.lua — binary I/O for weighted_astar.lua
dofile("pathfind_c/weighted_astar.lua")

local fi = io.open(arg[1], "rb")
if not fi then print("Cannot open " .. arg[1]); os.exit(1) end
local function ri()
    local b1,b2,b3,b4 = fi:read(4):byte(1,4)
    return b1 + b2*256 + b3*65536 + b4*16777216
end
local W  = ri(); local H  = ri()
local sx = ri(); local sy = ri()
local gx = ri(); local gy = ri()
local data = fi:read(W * H)
fi:close()

local cells = {}
for y = 0, H - 1 do
    cells[y] = {}
    for x = 0, W - 1 do
        cells[y][x] = (data:byte(y * W + x + 1) ~= 0)
    end
end
local function world(x, y)
    if x < 0 or x >= W or y < 0 or y >= H then return false end
    return cells[y][x]
end

local t0 = os.clock()
local path = pathfind_weighted(world, W, H, sx, sy, gx, gy)
local ems = math.floor((os.clock() - t0) * 1000 + 0.5)

local of = io.open(arg[2] or "lua_out.bin", "wb")
local function wi(v)
    of:write(string.char(v%256, math.floor(v/256)%256,
                          math.floor(v/65536)%256, math.floor(v/16777216)%256))
end
if path then wi(#path) else wi(0) end
wi(ems)
if path then for _, p in ipairs(path) do wi(p[1]); wi(p[2]) end end
of:close()
print(string.format("Lua: %d steps, %dms", path and #path or 0, ems))
