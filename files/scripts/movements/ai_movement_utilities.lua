local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
--[[
    入口为FindPath()，主要用于搜索到一条可用路径
]]
dofile_once(base_file .. "files/scripts/utils/astar.lua")
local M_utils = dofile_once(now_file .. "move_utils.lua")
-- 网格密度：8像素间隔生成节点
local grid_density = 4
local max_path_length = 256
local function CreatePath(config,func)
	local resPath = config.logger:func(func,{config},{
		current_fore = config.logger.current_fore + 1,
        current_pos =  "寻路算法"
	})
	return resPath
end
local Path_Find = {}   --存储一些路径
--- 搜索算法
---@param start_x number 起始点
---@param start_y number 起始y
---@param goal_x number 目标x
---@param goal_y number 目标y
---@param smooth boolean 是否启用平滑
---@param custom_solver function|table|nil 当其为table时，当node_grid用;否则为自定义节点验证函数
---@param node_grid table|nil 节点网络，用于复用
function FindPath(start_x, start_y, goal_x, goal_y, smooth, custom_solver, node_grid,logger)
	-- 兼容处理：如果custom_solver是表，则作为node_grid处理
	if (type(custom_solver) == "table") then
		node_grid = custom_solver
		custom_solver = nil
	end

	-- 初始化节点网格（如果未提供）
	node_grid = node_grid or {}
	local id = 0
	-- 碰撞箱修正
	local start = {
		x = math.floor(start_x),
		y = math.floor(start_y - 4)
	}
	-- math.floor(i / v) * v
	local goal = {
		x =math.floor(goal_x/grid_density)*grid_density,     
		y = math.floor(goal_y/grid_density)*grid_density
	}
	if math.abs(goal.x-start.x) + math.abs(goal.y-start.y) > max_path_length  then
		logger:info("目标点与起始点距离过远")
		return nil,nil 
	end 
	-- 使用A*算法查找路径
	local config = {
		start = start,
		goal = goal,
		logger = logger,
		get_node_key = Path_Find.get_node_key,
		get_h_func = Path_Find.get_h_func,
		get_neighbors_func = Path_Find.get_neighbors_func,
		get_cost = Path_Find.get_cost,
		is_goal = Path_Find.is_goal,
	}
	local path,nodes = logger:func(CreatePath,{config,AStar},{
		current_fore = logger.current_fore + 1,
        current_pos =  "CreatePath"
	})
	-- 路径查找失败
	if (path == nil) then
		logger:info("路径查找失败")
		return nil,nodes
	end
	logger:info("路径节点数量: " .. #path)
	-- 不需要平滑则返回原始路径
	return path, nodes
end



function Path_Find.get_node_key(node)
    return string.format("%.0f_%.0f",node.x,node.y)
end
function Path_Find.get_h_func(nodeA,goal)
	-- 精确距离
	local dx = math.abs(nodeA.x - goal.x)
	local dy = math.abs(nodeA.y - goal.y)
	local dist =  math.max(dx,dy) + (math.sqrt(2) - 1 ) * math.min(dx,dy)
	-- local dist = math.sqrt(dx^2 + dy^2)
	return dist
end
function Path_Find.get_neighbors_func(current_node)
	local neighbors =  {}
	local dd = {grid_density,0,-grid_density}
	-- 八向节点
	for _,dx in ipairs(dd) do 
		for _,dy in ipairs(dd) do 
			local x = current_node.x +dx
			local y = current_node.y +dy
			if dx~= 0 or dy~=0 then
				if not RaytracePlatforms(x, y,x+1,y) then
					table.insert(neighbors,{x=x,y=y})
				end				
			end
		end
	end
	return neighbors
end
function Path_Find.get_cost(nodeA,nodeB)
	local loss = 0
	if (RaytracePlatforms(nodeA.x,nodeA.y,nodeB.x,nodeB.y)) then
        return grid_density/0.00001
    end
	--5射线检查
	local point= {
		{-3, -8}, {3, -8}, {-3, 8}, {3, 8}
	}
	local count = 0 
	for _,v in ipairs(point) do
		local bx = RaytracePlatforms(nodeA.x + v[1], nodeA.y + v[2], nodeB.x + v[1], nodeB.y + v[2])
		if bx then
			count = count + 1
		end
	end
	--0条射线完美，1条命中可接受，2条命中难以接受，3以上无法接受
	if count == 0 then
		loss = 0 
	elseif count == 1 then
		loss = grid_density / 0.5
	elseif count == 2 then
		loss =  grid_density /0.1 
	else
		return grid_density/0.00001
	end 
	--计算两个节点
	local dx =  nodeB.x - nodeA.x 
	local dy  = nodeB.y -nodeA.y
	if dx == 0 or dy ==0 then 
		return grid_density +loss
	else
		return math.sqrt(2) * grid_density+loss
	end
end
function Path_Find.is_goal(node,goal)
	local dist =  ( goal.x  -node.x ) ^ 2 + ( goal.y - node.y ) ^ 2 
	return dist<=grid_density^2
end