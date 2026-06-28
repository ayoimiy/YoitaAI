-- weighted_astar.lua — Lua 5.1 Weighted A* for Noita mod
-- Usage: lua5.1 weighted_astar.lua <input.bin> [output.bin]
--   or: dofile("weighted_astar.lua"); pathfind_weighted(world, W, H, sx, sy, gx, gy)

local MAX_AIR = 15
local AIR_N = MAX_AIR + 1

-- Penalty tables
local up_pen, hz_pen, dn_pen = {}, {}, {}
for n = 1, 255 do
    up_pen[n] = 2.0 * 1.30 ^ (n - 1)
    hz_pen[n] = 0.5 * 1.20 ^ (n - 1)
    dn_pen[n] = 0.5 + 0.08 * n
end

-- Movement weights (Lua 1-indexed: dx+2, dy+2)
local wcost = {
    {1.5, 1.0, 1.5},
    {1.0, 0.0, 1.0},
    {1.5, 1.0, 1.5},
}

local function octile(x1, y1, x2, y2)
    local dx, dy = math.abs(x1 - x2), math.abs(y1 - y2)
    if dx > dy then return dx + 0.41421356 * dy
    else return dy + 0.41421356 * dx end
end

local function neighbours(world, cx, cy)
    local r = {}
    for _, dx in ipairs({-1, 0, 1}) do
        for _, dy in ipairs({-1, 0, 1}) do
            if dx == 0 and dy == 0 then
            else
                local nx, ny = cx + dx, cy + dy
                if world(nx, ny) then
                    local ok = true
                    if dx ~= 0 and dy ~= 0 then
                        if not world(cx + dx, cy) and not world(cx, cy + dy) then
                            ok = false
                        end
                    end
                    if ok then r[#r + 1] = {nx, ny} end
                end
            end
        end
    end
    return r
end

-- Min-heap
local function heap_create()
    return { n = {}, k = {} }
end
local function heap_push(h, node, key)
    h.n[#h.n + 1] = node
    h.k[#h.k + 1] = key
    local i = #h.n
    while i > 1 do
        local p = math.floor(i / 2)
        if key >= h.k[p] then break end
        h.n[i], h.k[i] = h.n[p], h.k[p]
        i = p
    end
    h.n[i], h.k[i] = node, key
end
local function heap_pop(h)
    if #h.n == 0 then return nil end
    local r = h.n[1]
    local lk = h.k[#h.k]
    local ln = h.n[#h.n]
    h.n[#h.n] = nil
    h.k[#h.k] = nil
    if #h.n == 0 then return r end
    local i = 1
    while true do
        local l, ri = 2 * i, 2 * i + 1
        local smallest = i
        if l <= #h.n then
            local cmp = (smallest == i) and lk or h.k[smallest]
            if h.k[l] < cmp then smallest = l end
        end
        if ri <= #h.n then
            local cmp = (smallest == i) and lk or h.k[smallest]
            if h.k[ri] < cmp then smallest = ri end
        end
        if smallest == i then break end
        h.n[i], h.k[i] = h.n[smallest], h.k[smallest]
        i = smallest
    end
    h.n[i], h.k[i] = ln, lk
    return r
end

-- Main pathfind function
function pathfind_weighted(world, W, H, sx, sy, gx, gy)
    local INF = 1 / 0
    local total = W * H * AIR_N

    local g_score = {}
    local parent = {}
    local closed = {}
    local dom = {}

    for i = 0, total - 1 do
        g_score[i] = INF
        parent[i] = nil
        closed[i] = false
        dom[i] = INF
    end

    local function idx(x, y, a)
        return (y * W + x) * AIR_N + a
    end

    local si = idx(sx, sy, 0)
    g_score[si] = 0
    dom[si] = 0

    local open = heap_create()
    heap_push(open, {sx, sy, 0}, octile(sx, sy, gx, gy) + si * 1e-12)

    local goal_node = nil
    local iter = 0

    while #open.n > 0 and iter < 2000000 do
        local cs = heap_pop(open)
        if not cs then break end
        local cx, cy, ca = cs[1], cs[2], cs[3]
        local ci = idx(cx, cy, ca)
        if closed[ci] then
            -- skip
        else
            closed[ci] = true
            iter = iter + 1

            if cx == gx and cy == gy then
                goal_node = cs
                break
            end

            local cur_g = g_score[ci]
            local nbs = neighbours(world, cx, cy)
            for _, nb in ipairs(nbs) do
                local nx, ny = nb[1], nb[2]
                local dxi, dyi = (nx - cx) + 2, (ny - cy) + 2
                local step = wcost[dyi][dxi]

                local on_ground = not world(nx, ny + 1)
                local na

                if on_ground then
                    step = step - 0.7
                    if step < 0.1 then step = 0.1 end
                    na = 0
                    if ca > 0 then step = step + 1.0 end
                else
                    na = ca + 1
                    if na <= MAX_AIR then
                        if (ny - cy) < 0 then
                            step = step + up_pen[na]
                            if ca == 0 then step = step + 0.5 end
                        elseif (ny - cy) > 0 then
                            step = step + dn_pen[na]
                        else
                            step = step + hz_pen[na]
                        end
                    end
                end

                if na <= MAX_AIR then
                    local ni = idx(nx, ny, na)
                    local gn = cur_g + step

                    local dominated = false
                    local base = (ny * W + nx) * AIR_N
                    local n = na < MAX_AIR and na or MAX_AIR
                    for a = 0, n do
                        if dom[base + a] <= gn then dominated = true; break end
                    end
                    if not dominated and not closed[ni] and gn < g_score[ni] then
                        g_score[ni] = gn
                        parent[ni] = cs
                        if gn < dom[ni] then dom[ni] = gn end
                        heap_push(open, {nx, ny, na},
                                  gn + octile(nx, ny, gx, gy) + ni * 1e-12)
                    end
                end
            end
        end
    end

    if not goal_node then return nil end

    local path = {}
    local node = goal_node
    while node do
        path[#path + 1] = {node[1], node[2]}
        local ni = idx(node[1], node[2], node[3])
        node = parent[ni]
    end
    for i = 1, math.floor(#path / 2) do
        path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
    end
    return path
end

-- Module only
