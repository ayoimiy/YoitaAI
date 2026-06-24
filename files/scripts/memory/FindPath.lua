
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
--Astar模块
dofile_once(base_file .. "files/scripts/utils/astar.lua")
--记忆模块
local ME = dofile_once(base_file .. "files/scripts/memory/manager.lua")


---当前所在的区块key缓存
local FM = {
    curr_chunk_key = nil ,
}


---底层移动控制——向目标位置移动一步
---@param player Player 玩家实体
---@param target {x:number, y:number} 目标坐标
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


---@class BigFind
---@field path table<number, number|string> 连通分量路径(block_id / chunk_key)
---@field path_index number 当前路径索引
---@field curr_block_id number|nil 玩家当前所在连通块id
---@field is_finding boolean 是否正在寻路中
---@field is_change boolean 地图是否发生变化(信号传递给Small_find)
---@field player_x number|nil 玩家位置x
---@field player_y number|nil 玩家位置y
local Big_find = {
    path  = {},
    path_index = 0,
    curr_block_id = nil ,
    is_finding = false,
    is_change = false,   --用于传递给小寻路模块
    player_x = nil,
    player_y = nil,
}


---@class SmallFind
---@field path table<number, {x:number, y:number}>|nil 节点路径
---@field path_index number 当前路径索引
---@field max_dist number 到达目标点的判定距离阈值
---@field is_finding boolean 是否正在寻路中
local Small_find = {
    path = {},
    path_index = 0 ,
    max_dist = 75,
    is_finding = false,
}



---在连通分量图上寻路(Big_find = 粗粒度跨分量路径)
---基于 A* 算法，以 Block(id) 为节点、未知区块(string)为目标
---当玩家所在分量发生变化时调用，更新 self.path
---@return table|nil path 连通分量id数组; nil 表示无路径
function Big_find:find()
    local start = self.curr_block_id
    local curr_chunk_key = ME.get_block_chunk_key(start)
    local scx,scy = curr_chunk_key:match("(-?%d+)_(-?%d+)")
    ---@type AStarConfig
    local config = {
        start = start,

        get_node_key = function(id)
            return tostring(id)
        end,

        get_h_func = function(node)
            if type(node) == "number" then
                --使其偏好下面的区块
                local chunk_key = ME.get_block_chunk_key(node)
                local cx,cy = chunk_key:match("(-?%d+)_(-?%d+)")
                return math.max(0,cy-scy)
            elseif type(node) == "string" then
                --直接为区块
                local cx,cy = node:match("(-?%d+)_(-?%d+)")
                return math.max(0,cy-scy)
            else
                print("[BigFind]出现异常节点")
                return -100000
            end
        end,

        get_neighbors_func = function(id)
            local neighbors = ME.get_block_neighbors(id)
            return neighbors
        end,

        get_cost = function(from_node, to_node)
            return 1
        end,

        is_goal = function(node)
            if type(node) == "string" then
                return true                
            end
            return false
        end,

        max_count = 1000,
    }
    local path = AStar(config)

    --更新路径
    self.path = path
    self.path_index = 1
    self.is_finding = true
    self.is_change = true

    return path
end
---沿 Big_find 路径推进，驱动 Small_find 进行细粒度寻路
---取当前分量与下一分量，交给 Small_find:find() 做节点级路径规划
---@param player Player 玩家实体
function Big_find:Move(player)
    if self.path ~= nil and #self.path > 2 then

        if self.path_index >= #self.path then
            --完美结束，即已经到达了目标点，可以进行再次寻路
            self.is_finding = false
            return
        end
      
        --进行小寻路
        if Small_find.is_finding == false or self.is_change == true  then
            --提取节点        
            local from_node = self.path[self.path_index]
            local to_node   = self.path[self.path_index + 1]
            --提供给小寻路信息

            


            Small_find:find()
            Small_find.is_finding = true
            self.is_change = false
        elseif Small_find.path == nil or #Small_find.path < 2 then
            print("[Big_find]error,no path")
        end
    
    end

end
---在单个连通分量内做细粒度A*寻路(Small_find = 节点级路径)
---以 8px 步长网格为基础，用 5 射线检测评估可通行性
---@param sx number 起点x(网格对齐)
---@param sy number 起点y(网格对齐)
---@param nodes table<string,boolean> 当前分量内所有可通行节点表，key="x_y"
---@param target_nodes table<string,boolean> 目标节点集合，key="x_y"，到达任一即达目标
---@return table|nil path {x:number,y:number}[] 节点路径数组; nil 表示无路径
function Small_find:find(sx,sy,nodes,target_nodes)
    
    local node_size = ME.node_size
    ---@type AStarConfig
    local config = {
        start = {x = sx ,y = sy},

        get_node_key = function(node)
            return  node.x .. "_" .. node.y 
        end,

        get_h_func = function(node)
            return 0
        end,

        get_neighbors_func = function(node)
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
        end,

        get_cost = function(from_node, to_node)
            local loss = 0
            if (RaytracePlatforms(from_node.x,from_node.y,to_node.x,to_node.y)) then
                return node_size/0.00001
            end
            --5射线检查
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
            local dy  = to_node.y -from_node.y
            if dx == 0 or dy ==0 then 
                return node_size + loss
            else
                return math.sqrt(2) * node_size + loss
            end
        end,

        is_goal = function(node)
            local key  = node.x .. "_" .. node.y 
            if target_nodes[key] ~= nil then
                return true
            end
            return false
        end,

        max_count = 1000,
    }
    
    local path = AStar(config)
    --更新路径
    self.path = path
    self.path_index = 1
    self.is_finding = true

    return path
end

---沿 Small_find 节点路径移动玩家
---逐节点推进，到达当前目标节点阈值后切换到路径下一个节点
---@param player Player 玩家实体
function Small_find:Move(player)
    local x,y = player:get_pos()
    if not (x and y) then
        error("entity has no pos")
    end
    --节点移动
    
    if self.path ~= nil and #self.path > 2 then 
        if self.path_index >= #self.path then
            --完成
            self.is_finding = false
            return
        end

        local target = self.path[self.path_index + 1]
    
        move(player,target)

        local dist =   (x-target.x)^2 + (y-4-target.y)^2
        if dist < self.max_dist then
            self.path_index = self.path_index + 1
        end
    end
end


---主控制状态的接口表
---@class FindPathMain
---@field is_finding boolean 是否正在执行寻路
local M = {
    is_finding = false
}
---每帧更新——负责区块扫描、路径规划和移动控制
---在玩家进入新chunk时触发 Floor_fill 扫描，然后依次执行 Big_find:find() → Big_find:Move() → Small_find:Move()
---@param player Player 玩家实体
function M.update(player)
    local x,y = player:get_pos()
    local chunk_key = ME.get_chunk_key(x,y)
    local is_change = false
    local curr_block_id = nil
    local pos = nil
    if chunk_key ~= FM.curr_chunk_key then
        curr_block_id,is_change,pos = ME.Floor_fill(x,y)
        FM.curr_chunk_key = chunk_key
        Big_find.curr_block_id = curr_block_id
        Big_find.player_x = pos.x
        Big_find.player_y = pos.y
    end
    --寻路部分
    if M.is_finding == false or is_change == true then
        if is_change then
            Big_find:find()
        end
        Big_find:Move(player)
        is_change = false
    end
end





return M
