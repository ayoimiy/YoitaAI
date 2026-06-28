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
local curr_block_id = nil
---@type table<number,NodeSet>
local blocks_nodes = {}

local Is_change = false
local re_ff = false
local change_cool_down = 0
local stay_time = 0
local leave_time = 0


local function re_flood_fill()
    if change_cool_down > 0 then
        return
    else
        change_cool_down = 10
        Is_change = true
        re_ff = true
    end
end



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
    local dist =   (x-target.x)^2 + (y-4-target.y)^2
    if dist < max_dist then
        return true
    end
    return false
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
-- helper for debug
local function table_length(t)
    local c = 0
    for _,_ in pairs(t) do c = c + 1 end
    return c
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
        local exist,id = nodes:exist2(x,y)
        if exist then
            return block_id,nx,ny
        else
            local nnodes = nodes:get_neighbors(id)
            for i,v in ipairs(nnodes) do 
                if nodes:exist(v) then
                    return block_id,nodes:get_pos(v)
                end
            end
        end
    end

    print("[DEBUG] find_near_block: key=" .. key .. " not found in " .. table_length(blocks_nodes) .. " blocks")
    --打印
    -- for block_id,nodes in pairs(blocks_nodes) do
    --     local nodes_set = nodes:to_nodes2(curr_chunk_key)
    --     print("block" .. block_id .. " nodes:")
    --     local str = ""
    --     for k in pairs(nodes_set) do
    --         str = str .. k .. "  "
    --     end
    --     print(str)
    -- end

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

--debug变量，之后删
local debug_target_nodes = {}
local debug_all_nodes = {}

--#region 大小寻路实现

local BigFind = FindPath:new()
local SmallFind = FindPath:new()

--[[
    实现大寻路
]]
---@param start_id number 起点block_id
function BigFind:find(start_id)
    print("\n")
    print("BigFind start")
    local config = AStarConfig:new()
    config.start = start_id
    print("now block_id is " .. tostring(config.start or "nil"))
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
        local cx,cy 
        if type(node) == "number" then
            local nchunk = ME.get_block_chunk_key(node)
            cx,cy = nchunk:match("(-?%d+)_(-?%d+)")
        elseif type(node) == "string" then
            cx,cy = node:match("(-?%d+)_(-?%d+)")
        end
        --惩罚比起点小的区块
        return math.max(0, scy - cy, -cx )
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
    print("BigFind finished,find path size:" .. #self.path )
    print("\n")
end
function BigFind:move(player,find)
    local x,y = player:get_pos()
    local is_change = false

    --检查一下玩家是否在位于一个连通块中
    local start_id,nx,ny = find_near_block(x,y)


    
    if self.path[self.path_index] ~= start_id then
        stay_time = stay_time + 1 
        leave_time = 0 
        if stay_time > 100 then
            --尝试刷新区块，这个可以看做不小心偏离，所以只需要重新刷即可
            re_flood_fill()
            stay_time = 0
        end
    else
        leave_time = leave_time + 1
        stay_time = 0
        if leave_time > 300 then
            --卡注了，需要其他寻路
            


            leave_time = 0
        end
    end

    --向最近的分量寻路
    if start_id == nil then
        --委托给其他寻路，以便回到分量中


        --尝试刷新区块
        re_flood_fill()
        return
    end
    curr_block_id = start_id

  

    --常规寻路
    if find or self.is_finding == false  then
        self:find(start_id)
        is_change = true
    end
    if #self.path > 1 then
        --检查是否寻路成功
        if self.path_index >= #self.path then
            self:refresh()
            return true
        end
        local curr_node = self.path[self.path_index]
        local next_node = self.path[self.path_index+1]

        --委托给小Find
        if SmallFind:move(player,curr_node,next_node,is_change,start_id,nx,ny) then
            self.path_index = self.path_index + 1
            return false
        end
    end
    return false
end


local function Raytrace5check(from_node,to_node)
    local loss = 0
    --5射线检查（与 BFS 的连通性判断一致）
    local point= {
        {-3, -8}, {3, -8}, {-3, 8}, {3, 8}
    }
    local count = 0 
    for _,v in ipairs(point) do
        local bx = RaytracePlatforms(from_node.x + v[1], from_node.y + v[2], to_node.x + v[1], to_node.y + v[2])
        if bx then
            count = count + 1
        end
    end
    return count
end 





---@param nodes NodeSet
---@param target_nodes NodeSet
---@param sx number
---@param sy number
function SmallFind:find(nodes,target_nodes,sx,sy)
    print("\n")
    print("SmallFind start")
    print("useful nodes: " .. table_length(nodes.nodes))
    print("target nodes: " .. table_length(target_nodes))
    print("start pos: " .. sx .. "," .. sy)
    local config = AStarConfig:new()
    config.start = {x=sx,y=sy}
    config.max_count = 1000
    config.get_node_key = function(node)
        return node.x.."_"..node.y
    end
    config.get_h_func = function(node)
        return 0 
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
                    if nodes:exist3(x,y) or target_nodes:exist3(x,y) then
                        local count = Raytrace5check(node,{x=x,y=y})
                        if count < 3 then
                            table.insert(neighbors,{x = x, y = y })
                        end
                    end
                end
            end
        end
        return neighbors
    end
    config.get_cost = function(from_node, to_node)
        local loss = 0
        local count = Raytrace5check(from_node,to_node)
        --0条射线完美，1条命中可接受，2条命中难以接受，3以上无法接受
        if count == 0 then
            loss = 0 
        elseif count == 1 then
            loss = node_size / 0.5
        elseif count == 2 then
            loss =  node_size /0.1 
        else
            return node_size/0.00001
        end

        --计算两个节点
        local dx =  to_node.x - from_node.x 
        local dy  = to_node.y - from_node.y
        if dx == 0 or dy ==0 then 
            return node_size + loss
        else
            return math.sqrt(2) * node_size + loss
        end
    end
    config.is_goal = function(node)
        if target_nodes:exist3(node.x,node.y) then
            return true
        end
        return false
    end
    local path = AStar(config)
    self.path = path or {}
    self.is_finding = true
    self.path_index = 1
    print("SmallFind finished,find path size:" .. #self.path)
    print("\n")
end
---@param from_node string|number
---@param to_node string|number
---@param is_change boolean
---@param block_id number
---@param sx number
---@param sy number
function SmallFind:move(player,from_node, to_node,is_change,block_id,sx,sy)
   
    if self.is_finding == false or is_change == true then
        local target_nodes =  ME.get_block_edge(from_node, to_node)
        if not (block_id and sx and sy) then
            error("[SmallFind]block_id error")
            return
        end
        local nodes = blocks_nodes[block_id]

        print("[SmallFind]Path finding started, received delegation info: " .. string.format("Nodes " .. from_node .. "--->" .. to_node))
     
        self:find(nodes,target_nodes,sx,sy)

        debug_all_nodes = nodes
        debug_target_nodes = target_nodes
    end
    --移动
    if #self.path > 0 then
        --检查是否寻路成功
        if self.path_index > #self.path then
            self:refresh()
            return true
        end
        --委托给底层移动,到达目标点的判断也一并委托了
        local target = self.path[self.path_index]
        if move(player,target) then 
            self.path_index = self.path_index + 1
        end
    else
        --无寻路，但需要移动状态
        Move_no_path(player)
    end
    return false
end

--#endregion

--#region 对外接口

---主控制状态的接口表
---@class FindPathMain
---@field is_finding boolean 是否正在执行寻路
---@field debug FindPath_Debug 调试信息
local M = {
    is_finding = false,
    
}
function M.update(player)
    local x,y = player:get_pos()
    --计算当前区间
    local cc_key = ME.get_chunk_key(x,y)
    local set = {}


    change_cool_down = change_cool_down - 1
    if cc_key ~= curr_chunk_key then
        re_ff = true
        curr_chunk_key = cc_key
        print("curr_chunk_key changed,start floor fill,now chunk:" .. cc_key .. "\n")
    end
    if re_ff then
        local change = false
        set,change = ME.Floor_fill(cc_key)
        Is_change = Is_change or change
        blocks_nodes = set
        local count = 0
        for k,v in pairs(set) do
            count = count + 1
        end
        print("floor fill finished:")
        print("blocks count:" .. count)
        for k,v in pairs(set) do
            print("block" .. k .. " nodes count:" .. v.count )
        end
        re_ff = false
    end
    if M.is_finding then
        BigFind:move(player,Is_change)
        Is_change = false
    end
end

--#endregion

--#region debug

---@param nodes NodeSet
local function nodes_to_nodes(nodes)
    local ret = {}
    for id in pairs(nodes.nodes) do 
        local x,y = nodes:get_pos(id)
        table.insert(ret,{x=x,y=y})
    end
    return ret
end
---@class FindPath_Debug
---@field path_nodes function
---@field index  function
---@field curr_chunk_key  function
M.debug = {
    path_nodes = function ()
        return SmallFind.path
    end,
    target_nodes = function ()
        return nodes_to_nodes(debug_target_nodes)
    end,
    all_nodes = function (x,y)
        local block_id = find_near_block(x,y)
        local nodes = blocks_nodes[block_id]
        if not nodes then
            return {}
        end
        return nodes_to_nodes(nodes)
    end,
    index = function ()
        return SmallFind.path_index
    end,
    big_path = function ()
        return BigFind.path
    end,
    big_index = function ()
        return BigFind.path_index
    end,
    curr_chunk_key = function ()
        return curr_chunk_key
    end,
    curr_block_id = function ()
        return curr_block_id
    end
}

--#endregion

return M
