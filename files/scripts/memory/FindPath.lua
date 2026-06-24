--#region 全局变量
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
--Astar模块
dofile_once(base_file .. "files/scripts/utils/astar.lua")
--记忆模块
---@type Manager
local ME = dofile_once(base_file .. "files/scripts/memory/manager.lua")

local node_size = 8
local max_dist = 75

local curr_chunk_key = nil
local blocks_nodes = {}

--#endregion

--#region 局部函数

---底层移动控制——向目标位置移动一步
---@param player Player 玩家实体
---@param target table 目标坐标
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
---停止所有移动按键——无路径时原地待命
---@param player Player 玩家实体
local Move_no_path = function (player)
    local controls = player:controls_comp()
    controls.mButtonDownDown = false
    controls.mButtonDownFly = false
    controls.mButtonDownRight = false
    controls.mButtonDownLeft  = false
end
---@param x number
---@param y number
---@return number|nil block_id,number|nil nx,number|nil ny
local function find_near_block(x,y)
    --寻找坐标在哪个连通块
    local nx = math.floor(x/node_size) * node_size
    local ny = math.floor(y/node_size) * node_size
    local key = nx .. "_" .. ny
    for block_id,nodes in pairs(blocks_nodes) do
        if nodes[key] ~= nil then
            return block_id,nx,ny
        end
    end
end


--#endregion

--#region 类的定义

---@class FindPath
---@field find function 寻路函数
---@field move function 对外APi
---@field refresh function 刷新
---@field path table 路径
---@field path_index number 路径索引
---@field is_finding boolean 是否正在寻路
local FindPath = {}
FindPath.__index = FindPath
---@return FindPath
function FindPath:new()
    local obj = {}
    setmetatable(obj, self)
    obj.path = {}
    obj.path_index = 1
    obj.is_finding = false
    return obj
end
function FindPath:refresh()
    self.path = {}
    self.path_index = 1
    self.is_finding = false
end

--#endregion

--#region 大小寻路实现

local BigFind = FindPath:new()
local SmallFind = FindPath:new()

--[[
    实现大寻路
]]
function BigFind:find(sx,sy)
    local config = AStarConfig:new()
    config.start = find_near_block(sx,sy)
    if config.start == nil then
        print("[BigFind] start error")
        return
    end
    local chunk = ME.get_block_chunk_key(config.start)
    local _,scy = chunk:match("(-?%d+)_(-?%d+)")
    config.max_count = 1000
    config.get_node_key = function(node)
        return tostring(node)
    end
    config.get_h_func = function(node)
        local cy 
        if type(node) == "number" then
            local nchunk = ME.get_block_chunk_key(node)
            _,cy = nchunk:match("(-?%d+)_(-?%d+)")
        elseif type(node) == "string" then
            _,cy = node:match("(-?%d+)_(-?%d+)")
        end
        --惩罚比起点小的区块
        return math.max(0, scy - cy)
    end
    config.get_neighbors_func = function(node)
        return ME.get_block_neighbors(node)
    end
    config.get_cost = function(from_node, to_node)
        return 1
    end
    config.is_goal = function(node)
        if type(node) == "string" then
            return true
        end
        return false
    end

    self.path = AStar(config) or {}
    self.is_finding = true
    self.path_index = 1
end
function BigFind:move(player,find)
    local x,y = player:get_pos()
    local is_change = false
    if find or self.is_finding == false then
        self:find(x,y)
        is_change = true
    end
    if #self.path > 1 then
        --检查是否寻路成功
        if self.path_index > #self.path then
            self:refresh()
            return true
        end
        local curr_node = self.path[self.path_index]
        local next_node = self.path[self.path_index+1]
        --委托给小Find
        if SmallFind:move(player,curr_node,next_node,is_change) then
            self.path_index = self.path_index + 1
            return false
        end
    end
    return false
end
---@param nodes table<string,boolean>
---@param target_nodes table<string,boolean>
---@param sx number
---@param sy number
function SmallFind:find(nodes,target_nodes,sx,sy)
    local config = AStarConfig:new()
    local tx,ty
    local count = 0
    for k,v in pairs(target_nodes) do
        local x,y = k:match("(-?%d+)_(-?%d+)")
        x,y = tonumber(x),tonumber(y)
        tx = (tx or 0) + x
        ty = (ty or 0) + y
        count = count + 1
    end
    tx,ty = tx/count,ty/count
    config.start = {x=sx,y=sy}
    config.max_count = 1000
    config.get_node_key = function(node)
        return node.x.."_"..node.y
    end
    config.get_h_func = function(node)
        if not (tx and ty) then
            return 0
        end
        -- 曼哈顿距离
        return math.abs(node.x - tx) + math.abs(node.y - ty)
    end
    config.get_neighbors_func = function(node)
        local neighbors = {}
        local t = {-1,0,1}
        for _,dx in ipairs(t) do
            for _,dy in ipairs(t) do
                if dx ~= 0 or dy ~= 0 then
                    local x = node.x + dx * node_size
                    local y = node.y + dy * node_size
                    local key = x .. "_" .. y
                    if nodes[key] ~= nil then
                        table.insert(neighbors,{x = x, y = y })
                    end
                end
            end
        end
        return neighbors
    end
    config.get_cost = function(from_node, to_node)
        local loss = 0 
        --计算两个节点
        local dx =  to_node.x - from_node.x 
        local dy  = to_node.y -from_node.y
        if dx == 0 or dy ==0 then 
            return node_size + loss
        else
            return math.sqrt(2) * node_size + loss
        end
    end
    config.is_goal = function(node)
        local key  = node.x .. "_" .. node.y
        if target_nodes[key] then
            return true
        end
        return false
    end

    self.path = AStar(config) or {}
    self.is_finding = true
    self.path_index = 1
end
---@param from_node string|number
---@param to_node string|number
---@param is_change boolean
function SmallFind:move(player,from_node, to_node,is_change)
    local x,y = player:get_pos()
    if self.is_finding == false or is_change == true then
        local target_nodes =  ME.get_block_edge(from_node, to_node)
        local block_id,sx,sy = find_near_block(x,y)
        if not (block_id and sx and sy) then
            error("[SmallFind]block_id error")
            return
        end

        local nodes = blocks_nodes[block_id]
        self:find(nodes,target_nodes,sx,sy)
    end
    --移动
    if #self.path > 0 then
        --检查是否寻路成功
        if self.path_index > #self.path then
            self:refresh()
            return true
        end
        --委托给底层移动
        local target = self.path[self.path_index]
        move(player,target)
        
        local dist =   (x-target.x)^2 + (y-4-target.y)^2
        if dist < max_dist then
            self.path_index = self.path_index + 1
        end
    end
    return false
end


--#endregion

--#region 对外接口

---主控制状态的接口表
---@class FindPathMain
---@field is_finding boolean 是否正在执行寻路
---@field debug table 调试信息
local M = {
    is_finding = false,
    
}
function M.update(player)
    local x,y = player:get_pos()
    --计算当前区间
    local cc_key = ME.get_chunk_key(x,y)
    local set = {}
    local is_change = false
    if cc_key ~= curr_chunk_key then 
        set,is_change = ME.Floor_fill(cc_key)
        curr_chunk_key = cc_key
        blocks_nodes = set
    end
    if M.is_finding then
        BigFind:move(player,is_change)
        is_change = false
    end
end

--#endregion

--#region debug

---@param nodes table<string,boolean>
local function nodes_to_nodes(nodes)
    local ret = {}
    for k,v in pairs(nodes or {}) do
        local x,y = k:match("(-?%d+)_(-?%d+)")
        x,y = tonumber(x),tonumber(y)
        table.insert(ret,{x=x,y=y})
    end
    return ret
end
M.debug = {
    path_nodes = function ()
        return SmallFind.path
    end,
    -- get_target_nodes = function ()
    --     return nodes_to_nodes(Big_find.blocks_nodes)
    -- end,
    index = function ()
        return SmallFind.path_index
    end,
    curr_chunk_key = function ()
        return curr_chunk_key
    end
}

--#endregion

return M
