local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
--[[
    入口为FindPath()，主要用于搜索到一条可用路径
]]

dofile_once(now_file .. "astar.lua")
local M_utils = dofile_once(now_file .. "move_utils.lua")

-- 网格密度：8像素间隔生成节点
local grid_density = 4



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
	local goal = {
		x = M_utils.nearest(goal_x,grid_density),
		y = M_utils.nearest(goal_y,grid_density)
	}
	
	-- 使用A*算法查找路径

	local path,nodes = logger:func(CreatePath,{
		start,   -- 起点（最近的网格节点）
		goal,     -- 终点（最近的网格节点）
		node_grid,
		grid_density,
		custom_solver,
		logger
	},{
		current_fore = logger.current_fore + 1,
        current_pos =  "CreatePath", 	
	})

	-- 路径查找失败
	if (path == nil) then
		return nil,nodes
	end
	logger:info("节点序号列表" .. logger:print_table(path))
	logger:info("节点列表" .. logger:print_table(path))
	-- 不需要平滑则返回原始路径

	return path, nodes

end

--[[
	需要引入 AStar函数
]]
--- 搜素中转，可能是用来适配其他算法？

function CreatePath(start, goal, nodes, grid_density, valid_node_func,logger)
	local resPath = logger:func(AStar,{start, goal, nodes, grid_density, valid_node_func,logger},{
		current_fore = logger.current_fore + 1,
        current_pos =  "AStar", 
	})
	if resPath then
		GamePrint("[CreatePath] 路径找到! 节点数: " .. #resPath)
	else
		GamePrint("[CreatePath] 路径未找到!")
	end
	
	return resPath
end











