
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
--Astar模块
dofile_once(base_file .. "files/scripts/utils/astar.lua")
--记忆模块
dofile_once(base_file .. "files/scripts/memory/manager.lua")


---底层移动
---@param player Player
---@param target table 目标id
local move = function (player,target)
    local controls = player:controls_comp()
    local x,y = player:get_pos()
    if controls then
        local target_left = target.x < x      -- 目标在左边
        local target_above = target.y < y - 5 -- 目标在上方（留3像素容差）
        -- 设置左右移动按键
        controls.mButtonDownRight = not target_left
        controls.mButtonDownLeft  = target_left
        -- 处理垂直移动
        if target_above then
            controls.mButtonDownFly = true
            controls.mButtonDownDown = false
            controls.mFlyingTargetY = y - 100
        else
            -- 关闭喷气背包
            controls.mButtonDownFly = false
            controls.mButtonDownDown = true
        end
        -- 检测是否在水中，设置下蹲按键
        local in_water = RaytraceSurfacesAndLiquiform(x, y, x, y)
        controls.mButtonDownDown = in_water and not RaytraceSurfaces(x, y, x, y)
    end
end
---@param player Player
local Move_no_path = function (player)
    local controls = player:controls_comp()
    controls.mButtonDownDown = false
    controls.mButtonDownFly = false
    controls.mButtonDownRight = false
    controls.mButtonDownLeft  = false
end


local FindPath = {}
--维护的全局变量
FindPath.last_chunk_key = ""  -- 上一个区块的key
FindPath.path = {}   --当前大路径
FindPath.path_index = 0  -- 当前大路径的索引
FindPath.little_path = {}
FindPath.little_path_index = 0
FindPath.max_dist = 75   -- 最大容忍距离
FindPath._components = nil  -- 当前区块的连通分量集缓存
FindPath.is_finding = false  -- 是否启用寻路
FindPath.cur_chunk = nil     -- 当前所在区块 key
FindPath._chunk_changed = false  -- 同 chunk 内地形是否变化(由 Floor_fill 设置)
FindPath._scan_frame_counter = 0  -- 强制重扫节流计数器

-- 网格对齐常量，与 manager.lua 保持一致
local NODE_SIZE = 8
-- 同 chunk 内强制重扫帧间隔(约0.5秒),用于检测地形变化
local SCAN_INTERVAL = 30
-- chunk 尺寸常量，与 manager.lua 保持一致
local CHUNK_W, CHUNK_H = 256, 256

-- 获取玩家所在的连通分量 id
---@param player Player
---@return number|nil comp_id 玩家所在分量，nil 表示不在任何分量中
function FindPath:get_player_component(player)
    local x, y = player:get_pos()
    if not (x and y) then
        return nil
    end

    local ccx, ccy = Chunk.get_pos(x, y)
    local chunk_key = ccx .. "_" .. ccy

    -- 区块变化 或 节流到时 才重新 Floor_fill(检测同 chunk 内地形变化)
    if self.last_chunk_key ~= chunk_key or self._scan_frame_counter <= 0 then
        local comps, unchanged = Floor_fill(ccx, ccy)
        self._components = comps
        self._chunk_changed = not unchanged
        self.last_chunk_key = chunk_key
        self._scan_frame_counter = SCAN_INTERVAL
    end

    if not self._components then
        return nil
    end

    -- 玩家坐标对齐到网格节点
    local nx = math.floor(x / NODE_SIZE) * NODE_SIZE
    local ny = math.floor(y / NODE_SIZE) * NODE_SIZE
    local node_key = nx .. "_" .. ny

    -- 查找该节点属于哪个分量
    for comp_id, comp in pairs(self._components) do
        if comp[node_key] then
            -- 填充调试显示：分量全节点集
            local vis_comp = {}
            for k in pairs(comp) do
                local kx, ky = k:match("(-?%d+)_(-?%d+)")
                table.insert(vis_comp, {x = tonumber(kx), y = tonumber(ky)})
            end
            self._display_comp = vis_comp
            -- 填充调试显示：分量边界节点集（mask 四条边全扫描）
            local vis_edge = {}
            local c_info = All_Components[comp_id]
            if c_info then
                local ex, ey = c_info.sx + CHUNK_W, c_info.sy + CHUNK_H
                for _, eo in ipairs({{1,"top"},{5,"right"},{9,"bottom"},{13,"left"}}) do
                    local bs, en = eo[1], eo[2]
                    for b = 0, 3 do
                        local bv = string.byte(c_info.mask, bs + b)
                        if bv ~= 0 then
                            for bit_in_byte = 0, 7 do
                                if math.floor(bv / (2 ^ bit_in_byte)) % 2 == 1 then
                                    local bit = (bs - 1 + b) * 8 + bit_in_byte
                                    local ex2, ey2
                                    if en == "top" then ex2, ey2 = c_info.sx + bit * NODE_SIZE, c_info.sy
                                    elseif en == "right" then ex2, ey2 = ex, c_info.sy + (bit - 32) * NODE_SIZE
                                    elseif en == "bottom" then ex2, ey2 = ex - (bit - 64) * NODE_SIZE, ey
                                    else ex2, ey2 = c_info.sx, ey - (bit - 96) * NODE_SIZE end
                                    table.insert(vis_edge, {x = ex2, y = ey2})
                                end
                            end
                        end
                    end
                end
            end
            self._display_edge = vis_edge
            return comp_id
        end
    end

    return nil
end

--[[
    记忆模块单独导入，为单例
    运行会使用Astar算法寻找路径，需要输入起点的分量，目标点，
    最终会返回一个路径数组，数组中为分量id, 最后一个目标点可能为`string`的区块id,或者`number`的分量id,其余均为分量id
]]
--大寻路
---@param start_id number 起点分量id
FindPath.Find = function (start_id)
    -- 起点分量不存在则直接返回
    if not All_Components[start_id] then
        return nil
    end
    local start_info = All_Components[start_id]
    local cx, cy = Chunk.get_pos(start_info.sx, start_info.sy)
    ---@type AStarConfig
    local config = {
        start = start_id,
        get_node_key = function (node)
            if type(node) == "number" then
                return "#" .. node
            else
                return node  -- string 即 chunk_key
            end
        end,
        get_h_func = function (node)
            -- 向下偏好：高于起点的区块被惩罚，使搜索优先向下扩散
            if type(node) == "number" then
                local comp_info = All_Components[node]
                if comp_info then
                    local _, ccy = Chunk.get_pos(comp_info.sx, comp_info.sy)
                    return math.max(0, cy - ccy)
                end
            elseif type(node) == "string" then
                local _, ccy = node:match("(-?%d+)_(-?%d+)")
                ccy = tonumber(ccy)
                if ccy then
                    return math.max(0, cy - ccy)
                end
            end
            return 0
        end,
        get_neighbors_func = function (node)
            local neighbors = {}
            if type(node) == "number" then
                local comp_info = All_Components[node]
                if comp_info then
                    -- 已探索的相邻分量
                    local comp_neighbors = Get_component_neighbors(node)
                    for neighbor_id in pairs(comp_neighbors) do
                        table.insert(neighbors, neighbor_id)
                    end
                    -- 未探索的相邻区块：仅在分量接触该边时才可达
                    local ccx, ccy = Chunk.get_pos(comp_info.sx, comp_info.sy)
                    -- mask 128位 = 16字节, 四边各4字节: 顶1-4, 右5-8, 底9-12, 左13-16
                    local edge_dirs = {
                        {dx = 0,  dy = -1, byte_start = 1},   -- 上
                        {dx = 1,  dy = 0,  byte_start = 5},   -- 右
                        {dx = 0,  dy = 1,  byte_start = 9},   -- 下
                        {dx = -1, dy = 0,  byte_start = 13},  -- 左
                    }
                    for _, dir in ipairs(edge_dirs) do
                        local ak = (ccx + dir.dx) .. "_" .. (ccy + dir.dy)
                        if Chunk_data[ak] == nil then
                            local has_edge = false
                            for b = 0, 3 do
                                if string.byte(comp_info.mask, dir.byte_start + b) ~= 0 then
                                    has_edge = true
                                    break
                                end
                            end
                            if has_edge then
                                table.insert(neighbors, ak)
                            end
                        end
                    end
                end
            end
            return neighbors
        end,
        get_cost = function(from_node, to_node)
            return 1
        end,
        is_goal = function (node)
            -- 未探索区块即为目标
            if type(node) == "string" then
                return true
            end
            return false
        end,
        max_count = 1000,
    }

    local path, nodes = AStar(config)
    if path then
        local parts = {}
        for i, node in ipairs(path) do
            if type(node) == "number" then
                local info = All_Components[node]
                local ck = info and Chunk.get_key(info.sx, info.sy) or "?"
                parts[i] = "comp#" .. node .. "(" .. ck .. ")"
            else
                parts[i] = node .. "(unexplored)"
            end
        end
        print("[YoitaAI] big path (" .. #path .. "): " .. table.concat(parts, " -> "))
        FindPath.path = path
        FindPath.path_index = 1
        FindPath._find_failed = false
        FindPath._push_target = nil
        FindPath.little_path = {}
        FindPath.little_path_index = 0
    else
        FindPath.path = {}
        FindPath._find_failed = true
    end
    return path, nodes
end


-- chunk 尺寸常量，与 manager.lua 保持一致

-- mask → 坐标：将指定边上第一个置位节点转为 {x,y}
local function mask_edge_to_pos(mask, sx, sy, byte_start, edge_name)
    local ex, ey = sx + CHUNK_W, sy + CHUNK_H
    for b = 0, 3 do
        local byte_val = string.byte(mask, byte_start + b)
        if byte_val ~= 0 then
            for bit_in_byte = 0, 7 do
                if math.floor(byte_val / (2 ^ bit_in_byte)) % 2 == 1 then
                    local bit = (byte_start - 1 + b) * 8 + bit_in_byte
                    if edge_name == "top" then
                        return {x = sx + bit * NODE_SIZE, y = sy}
                    elseif edge_name == "right" then
                        return {x = ex, y = sy + (bit - 32) * NODE_SIZE}
                    elseif edge_name == "bottom" then
                        return {x = ex - (bit - 64) * NODE_SIZE, y = ey}
                    else
                        return {x = sx, y = ey - (bit - 96) * NODE_SIZE}
                    end
                end
            end
        end
    end
    return nil
end

-- mask → 目标边全部节点集 { ["x_y"] = true }，供小 find 的多目标寻路
---@param comp_id number 当前分量id
---@param tarChunk.get_key string 未探索区块key
---@return table|nil
function FindPath:_edge_nodes_set(comp_id, tarChunk.get_key)
    local comp_info = All_Components[comp_id]
    if not comp_info then return nil end

    local ccx, ccy = Chunk.get_pos(comp_info.sx, comp_info.sy)
    local tcx, tcy = tarChunk.get_key:match("(-?%d+)_(-?%d+)")
    tcx, tcy = tonumber(tcx), tonumber(tcy)
    if not (tcx and tcy) then return nil end

    local dx, dy = tcx - ccx, tcy - ccy
    local byte_start, edge_name
    if dy < 0 then
        byte_start, edge_name = 1, "top"
    elseif dx > 0 then
        byte_start, edge_name = 5, "right"
    elseif dy > 0 then
        byte_start, edge_name = 9, "bottom"
    else
        byte_start, edge_name = 13, "left"
    end

    local result = {}
    local ex, ey = comp_info.sx + CHUNK_W, comp_info.sy + CHUNK_H
    for b = 0, 3 do
        local byte_val = string.byte(comp_info.mask, byte_start + b)
        if byte_val ~= 0 then
            for bit_in_byte = 0, 7 do
                if math.floor(byte_val / (2 ^ bit_in_byte)) % 2 == 1 then
                    local bit = (byte_start - 1 + b) * 8 + bit_in_byte
                    local nx, ny
                    if edge_name == "top" then
                        nx, ny = comp_info.sx + bit * NODE_SIZE, comp_info.sy
                    elseif edge_name == "right" then
                        nx, ny = ex, comp_info.sy + (bit - 32) * NODE_SIZE
                    elseif edge_name == "bottom" then
                        nx, ny = ex - (bit - 64) * NODE_SIZE, ey
                    else
                        nx, ny = comp_info.sx, ey - (bit - 96) * NODE_SIZE
                    end
                    result[nx .. "_" .. ny] = true
                end
            end
        end
    end
    return result
end

-- 获取路径中当前步的具体目标坐标
---@param curr number 当前分量id
---@param next_node number|string 下一步（分量id 或 区块key）
---@return table|nil {x,y}
function FindPath:_step_target(curr, next_node)
    if type(next_node) == "number" then
        -- 分量 → 分量：取共享边节点
        local info = Get_component_neighbors(curr)
        local edge = info[next_node]
        if edge and edge.nodes and #edge.nodes > 0 then
            local k = edge.nodes[1]
            local tx, ty = k:match("(-?%d+)_(-?%d+)")
            return {x = tonumber(tx), y = tonumber(ty)}
        end
    else
        -- 分量 → 未探索区块：取分量在该边上的第一个节点
        local comp_info = All_Components[curr]
        if comp_info then
            local ccx, ccy = Chunk.get_pos(comp_info.sx, comp_info.sy)
            local tcx, tcy = next_node:match("(-?%d+)_(-?%d+)")
            tcx, tcy = tonumber(tcx), tonumber(tcy)
            if tcx and tcy then
                local dx, dy = tcx - ccx, tcy - ccy
                local byte_start, edge_name
                if dy < 0 then
                    byte_start, edge_name = 1, "top"
                elseif dx > 0 then
                    byte_start, edge_name = 5, "right"
                elseif dy > 0 then
                    byte_start, edge_name = 9, "bottom"
                else
                    byte_start, edge_name = 13, "left"
                end
                return mask_edge_to_pos(comp_info.mask, comp_info.sx, comp_info.sy, byte_start, edge_name)
            end
        end
    end
    return nil
end

---小寻路：分量内细粒度寻路，从玩家位置到最近的目标门节点
---@param nodes table { [node_key] = true }  分量完整节点集
---@param target_nodes table { [node_key] = true }  目标门节点集
---@return boolean ok 是否找到路径
---@return table|nil path 节点key数组
function FindPath:find(nodes, target_nodes)
    if not self._player then return false end

    local x, y = self._player:get_pos()
    if not (x and y) then return false end

    -- 网格对齐
    local sx = math.floor(x / NODE_SIZE) * NODE_SIZE
    local sy = math.floor(y / NODE_SIZE) * NODE_SIZE
    local start_key = sx .. "_" .. sy

    -- 玩家不在分量节点上，找最近的可走节点兜底
    if not nodes[start_key] then
        local best_key, best_dist
        for key in pairs(nodes) do
            local nx, ny = key:match("(-?%d+)_(-?%d+)")
            nx, ny = tonumber(nx), tonumber(ny)
            local d = (sx - nx) ^ 2 + (sy - ny) ^ 2
            if not best_dist or d < best_dist then
                best_dist = d
                best_key = key
            end
        end
        if not best_key then return false end
        start_key = best_key
    end

    -- 无目标门则直接返回
    if not next(target_nodes) then return false end

    -- 预判越界方向：取第一个目标门节点，找不在 nodes 中的邻居即为外侧
    local exit_dx, exit_dy
    do
        local any_key = next(target_nodes)
        local ax, ay = any_key:match("(-?%d+)_(-?%d+)")
        ax, ay = tonumber(ax), tonumber(ay)
        for dx = -NODE_SIZE, NODE_SIZE, NODE_SIZE do
            for dy = -NODE_SIZE, NODE_SIZE, NODE_SIZE do
                if (dx == 0) ~= (dy == 0) then
                    local key = (ax + dx) .. "_" .. (ay + dy)
                    if not nodes[key] then
                        exit_dx, exit_dy = dx, dy
                        break
                    end
                end
            end
            if exit_dx then break end
        end
    end

    ---@type AStarConfig
    local config = {
        start = start_key,
        get_node_key = function(node)
            return node
        end,
        get_h_func = function(node)
            return 0
        end,
        get_neighbors_func = function(node)
            local nx, ny = node:match("(-?%d+)_(-?%d+)")
            nx, ny = tonumber(nx), tonumber(ny)
            local neighbors = {}
            for dx = -NODE_SIZE, NODE_SIZE, NODE_SIZE do
                for dy = -NODE_SIZE, NODE_SIZE, NODE_SIZE do
                    if dx ~= 0 or dy ~= 0 then
                        local key = (nx + dx) .. "_" .. (ny + dy)
                        if nodes[key] then
                            table.insert(neighbors, key)
                        end
                    end
                end
            end
            return neighbors
        end,
        get_cost = function(from_node, to_node)
            local fx, fy = from_node:match("(-?%d+)_(-?%d+)")
            local tx, ty = to_node:match("(-?%d+)_(-?%d+)")
            fx, fy = tonumber(fx), tonumber(fy)
            tx, ty = tonumber(tx), tonumber(ty)
            -- 5-ray terrain penalty (preference only, never blocks)
            local loss = 0
            if RaytracePlatforms(fx, fy, tx, ty) then
                loss = NODE_SIZE * 100
            else
                local offsets = {{-3,-8},{3,-8},{-3,8},{3,8}}
                local count = 0
                for _, v in ipairs(offsets) do
                    if RaytracePlatforms(fx + v[1], fy + v[2], tx + v[1], ty + v[2]) then
                        count = count + 1
                    end
                end
                if count == 0 then loss = 0
                elseif count == 1 then loss = NODE_SIZE / 0.5
                elseif count == 2 then loss = NODE_SIZE / 0.1
                else loss = NODE_SIZE * 100
                end
            end
            local dx = math.abs(fx - tx)
            local dy = math.abs(fy - ty)
            local base = (dx == 0 or dy == 0) and NODE_SIZE or (math.sqrt(2) * NODE_SIZE)
            return base + loss
        end,
        is_goal = function(node)
            if not target_nodes[node] then return false end
            if exit_dx then
                local nx, ny = node:match("(-?%d+)_(-?%d+)")
                nx, ny = tonumber(nx), tonumber(ny)
                local bx, by = nx + exit_dx, ny + exit_dy
                return not RaytracePlatforms(nx, ny, bx, by)
            end
            return true
        end,
        max_count = 1000,
    }

    local path = AStar(config)
    if path then
        return true, path
    end
    return false
end


-- 移动
---@param player Player
function FindPath:move(player)
    self._player = player
    local x, y = player:get_pos()
    if not (x and y) then
        return
    end

    if not self.path or #self.path < 2 then
        Move_no_path(player)
        return
    end

    -- 路径走完，自动重置
    if self.path_index >= #self.path then
        self.path = {}
        self.path_index = 0
        Move_no_path(player)
        return
    end

    local curr = self.path[self.path_index]
    local next_node = self.path[self.path_index + 1]

    -- 越界推力：小路径走完后推玩家跨过区块边界
    if self._push_target then
        move(player, self._push_target)
        local cur_ck = Chunk.get_key(x, y)
        local pd = (x - self._push_target.x) ^ 2 + (y - 4 - self._push_target.y) ^ 2
        if cur_ck ~= self.cur_chunk or pd < NODE_SIZE * 2 ^ 2 then
            self._push_target = nil
            self.path_index = self.path_index + 1
            print("[YoitaAI] push done (chunk=" .. cur_ck .. "), big path index -> " .. self.path_index)
        end
        return
    end

    -- 生成细粒度路径（分量→分量 或 分量→未探索区块）
    if #self.little_path == 0 then
        local comp_nodes = self._components[curr]
        if comp_nodes then
            local target_set = nil
            if type(next_node) == "number" then
                -- 共享边节点集
                local info = Get_component_neighbors(curr)
                local edge = info[next_node]
                if edge and edge.nodes then
                    target_set = {}
                    for _, k in ipairs(edge.nodes) do
                        target_set[k] = true
                    end
                end
                if target_set then
                    print("[YoitaAI] gen little path: comp " .. curr .. " -> comp " .. next_node .. ", doors=" .. #edge.nodes)
                end
            else
                -- 面向未探索区块的边上所有周长节点
                target_set = self:_edge_nodes_set(curr, next_node)
                if target_set then
                    local n = 0
                    for _ in pairs(target_set) do n = n + 1 end
                    print("[YoitaAI] gen little path: comp " .. curr .. " -> unexplored " .. next_node .. ", doors=" .. n)
                end
            end
            if target_set then
                local ok, p = self:find(comp_nodes, target_set)
                if ok and p then
                    self.little_path = p
                    self.little_path_index = 1
                    print("[YoitaAI] little path found, len=" .. #p .. " path: " .. table.concat(p, " -> "))
                else
                    print("[YoitaAI] little path NOT found")
                end
            end
        else
            print("[YoitaAI] no comp_nodes for curr=" .. curr .. ", waiting for chunk update")
        end
    end

    -- 跟随细粒度路径
    if #self.little_path > 0 then
        local node_key = self.little_path[self.little_path_index]
        local tx, ty = node_key:match("(-?%d+)_(-?%d+)")
        tx, ty = tonumber(tx), tonumber(ty)
        if tx and ty then
            move(player, {x = tx, y = ty})

            local dist = (x - tx) ^ 2 + (y - 4 - ty) ^ 2
            if dist < NODE_SIZE ^ 2 then
                self.little_path_index = self.little_path_index + 1
            end

            -- 细粒度路径走完 → 越界推力：朝边界外推一步跨过区块线
            if self.little_path_index > #self.little_path then
                local last_key = self.little_path[#self.little_path]
                local lx, ly = last_key:match("(-?%d+)_(-?%d+)")
                lx, ly = tonumber(lx), tonumber(ly)
                if lx and ly then
                    local push_x, push_y = lx, ly
                    local c_info = All_Components[curr]
                    if c_info then
                        local ex, ey = c_info.sx + CHUNK_W, c_info.sy + CHUNK_H
                        if ly == c_info.sy then
                            push_y = ly - NODE_SIZE          -- 顶边 → 上
                        elseif lx == ex then
                            push_x = lx + NODE_SIZE          -- 右边 → 右
                        elseif ly == ey then
                            push_y = ly + NODE_SIZE          -- 底边 → 下
                        else
                            push_x = lx - NODE_SIZE          -- 左边 → 左
                        end
                    end
                    self._push_target = {x = push_x, y = push_y}
                    print("[YoitaAI] push target set (" .. push_x .. "," .. push_y .. ")")
                end
                self.little_path = {}
                self.little_path_index = 0
            end
        end
        return
    end

    -- 无小路径兜底：停止移动
    Move_no_path(player)
end

---每帧执行：切换区块 或 路径走完时自动重规划大寻路
---@param player Player
function FindPath:update(player)
    if self.is_finding ~= true then
        return
    end

    local x, y = player:get_pos()
    if not (x and y) then
        return
    end

    local cur_chunk = Chunk.get_key(x, y)

    -- 每帧递减节流计数器,并刷新连通分量(内部按计数器节流 Floor_fill)
    self._scan_frame_counter = self._scan_frame_counter - 1
    local comp_id = self:get_player_component(player)

    -- 区块变化 或 地形变化 或 路径走完（且上次未失败）→ 重新规划
    if cur_chunk ~= self.cur_chunk or self._chunk_changed or (#self.path == 0 and not self._find_failed) then
        self.cur_chunk = cur_chunk
        self._chunk_changed = false  -- 消费标志
        if comp_id then
            self.Find(comp_id)
        end
    end

    self:move(player)
end


return FindPath
