local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
--[[
    入口为FindPath()，主要用于搜索到一条可用路径
]]

dofile_once(now_file .. "astar.lua")
local M_utils = dofile_once(now_file .. "move_utils.lua")

-- 网格密度：8像素间隔生成节点
local grid_density = 8
local R = 256



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
	

	-- 将起点坐标对齐到网格
	local start_x_rounded = M_utils.nearest(start_x, grid_density)
	local start_y_rounded = M_utils.nearest(start_y, grid_density)
	-- local time_start = GameGetRealWorldTimeSinceStarted()

	-- 生成路径节点网格（在起点周围512像素范围内）
	if (node_grid[1] == nil) then
		for x = start_x_rounded - R, start_x_rounded + R, grid_density do
			for y = start_y_rounded - R, start_y + R, grid_density do
				-- 只在可通过的位置生成节点（不与固体表面相交）
				-- 一轮全筛
				--保证每个点至少站的下一个米娜？
				local b1,x1 =  RaytracePlatforms(x, y, x+6, y)
				local b2,x2 = RaytracePlatforms(x, y, x-6, y)
				local b3,_,y1 = RaytracePlatforms(x, y, x, y-16)
				local b4,_,y2 = RaytracePlatforms(x, y, x, y+16)
				local b =not  (b1 or b2 or b3 or b4 ) or (x1-x2>=6) or (y2-y1 >=16) 
				if (b) then
					local idx = M_utils.get_point_idx(x/grid_density-start_x_rounded+256,y/grid_density-start_y_rounded+256,65)
					id = id +1
					node_grid[idx] = {x=x,y=y}
					
				end


			end
		end
	end

	logger:info("节点网络生成情况" .. id )
	logger:debug("节点网络情况" .. logger:print_table(node_grid))
	local find_closed_start_idx = M_utils.findClosest(start_x, start_y, node_grid)
	local find_closed_goal_idx = M_utils.findClosest(goal_x, goal_y, node_grid)
	logger:info ("开始点情况" .. logger:print_table(node_grid[find_closed_start_idx]) .. "结束点情况"
	.. logger:print_table(node_grid[find_closed_goal_idx])
)
	-- 使用A*算法查找路径

	local path_idx = logger:func(CreatePath,{
		find_closed_start_idx,   -- 起点（最近的网格节点）
		find_closed_goal_idx,     -- 终点（最近的网格节点）
		node_grid,
		grid_density,
		custom_solver,
		logger
	},{
		current_fore = logger.current_fore + 1,
        current_pos =  "CreatePath", 	
	})
	local path = {}
	for _,v in ipairs(path_idx or {}) do 
		table.insert(path,node_grid[v])
	end
	-- 路径查找失败
	if (path_idx == nil) then
		return nil,node_grid,node_grid[find_closed_start_idx],node_grid[find_closed_goal_idx]
	end
	logger:info("节点序号列表" .. logger:print_table(path_idx))
	logger:info("节点列表" .. logger:print_table(path))
	-- 不需要平滑则返回原始路径

	return path, node_grid

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











