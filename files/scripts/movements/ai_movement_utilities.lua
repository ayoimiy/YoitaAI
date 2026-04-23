local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
--[[
    入口为FindPath()，主要用于搜索到一条可用路径
]]
-- 引入通用工具库
dofile_once("data/scripts/lib/utilities.lua")
--[[
    使用了get_distance函数
	和 rad_to_vec函数
]]
dofile_once(now_file .. "astar.lua")
--[[
	需要引入 AStar函数
]]
--- 搜素中转，可能是用来适配其他算法？
function CreatePath(start, goal, nodes, grid_density, valid_node_func,logger)
	GamePrint("[CreatePath] 开始寻路")
	GamePrint("起点: " .. tostring(start.x) .. ", " .. tostring(start.y))
	GamePrint("终点: " .. tostring(goal.x) .. ", " .. tostring(goal.y))
	GamePrint("节点数量: " .. #nodes)
	GamePrint("网格密度: " .. grid_density)
	GamePrint("使用自定义验证: " .. (valid_node_func ~= nil and "是" or "否"))

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
-- 网格密度：8像素间隔生成节点
	local grid_density = 8
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
	local start_x_rounded = nearest(start_x, grid_density)
	local start_y_rounded = nearest(start_y, grid_density)
	-- local time_start = GameGetRealWorldTimeSinceStarted()

	-- 生成路径节点网格（在起点周围512像素范围内）
	if (node_grid[1] == nil) then
		for x = start_x_rounded - 256, start_x_rounded + 256, grid_density do
			for y = start_y_rounded - 256, start_y + 256, grid_density do
				-- 只在可通过的位置生成节点（不与固体表面相交）
				-- 一轮全筛
				if not ( RaytracePlatforms(x, y, x+3, y) or  RaytracePlatforms(x, y, x-3, y)
					or  RaytracePlatforms(x, y, x, y+3)  or RaytracePlatforms(x, y, x, y-7) 
			
				) then
					id = id + 1
					table.insert(node_grid, {id = id, x = x, y = y})
				end
			end
		end
	end

	logger:info("节点网络生成情况" .. #node_grid)
	logger:debug("需要最近点情况" .. logger:print_table(node_grid))
	local find_closed_start = FindClosest(start_x, start_y, node_grid)
	local find_closed_goal = FindClosest(goal_x, goal_y, node_grid)
	logger:info ("开始点情况" .. logger:print_table(find_closed_start) .. "结束点情况"
	.. logger:print_table(find_closed_goal)
)
	-- 使用A*算法查找路径
	

	local path = logger:func(CreatePath,{
		find_closed_start,   -- 起点（最近的网格节点）
		find_closed_goal,     -- 终点（最近的网格节点）
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
		return nil,node_grid,find_closed_start,find_closed_goal
	end

	-- 不需要平滑则返回原始路径
	if (not smooth) then
		return path, node_grid
	end

	-- 执行路径平滑并返回
	local smooth_path = SmoothPath(path)
	return smooth_path, node_grid
end
--- 需要最近的网格点作为代替
--- 通过遍历查找所有的坐标点，计算距离，然后更新最近点
---@param x number 
---@param y number
---@param t table 可用网格点
---@return table|integer 最近的元素，为0时表示没找到
function FindClosest(x, y, t)
	local closest = 99999
	local closest_item = 0
	local xe, ye, x2, y2 = 0, 0, 0, 0
	for k, v in pairs(t) do
		xe, ye, x2, y2 = x, y, v.x, v.y
		-- 检查坐标有效性（非nil且非零）
		if (xe ~= 0) and (xe ~= nil) and (ye ~= 0) and (ye ~= nil) and (x2 ~= 0) and (x2 ~= nil) and (y2 ~= 0) and (y2 ~= nil) then
			local distance = get_distance(x, y, v.x, v.y)
			if (distance < closest) then				
					closest_item = v
					closest = distance		
			end
		end
	end
	return closest_item
end
--- 作用是将寻找当前坐标最近的网格点，取该网格点作为起始点
---@param i number 坐标
---@param v number 节点距离
function nearest(i, v)
    return math.floor(i / v) * v
end
local function get_distance_squared(x1, y1, x2, y2)
	local squared_distance = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
	return squared_distance
end
function NeighborNodes(theNode, nodes, goal, solver, grid_density)
	local neighbors = {}
	for _, node in ipairs(nodes) do
		-- 调用solver函数验证节点有效性，排除自身
		if theNode ~= node and solver(theNode, node, goal, grid_density) then
			table.insert(neighbors, node)
		end
	end
	return neighbors
end
function Solver(node, neighbor, goal, node_density)
	if get_distance_squared(node.x, node.y, neighbor.x, neighbor.y) > 100 then
		return false
	end
	return not IsPointObstructed({x = neighbor.x, y = neighbor.y}, {x = node.x, y = node.y})
end


--[[
	为table表添加reverse方法（数组反转）
	将表中的元素顺序颠倒
]]
table.reverse = function(t)
    local n = #t
    local i = 1
    while i < n do
      t[i], t[n] = t[n], t[i]
      i = i + 1
      n = n - 1
    end
end

--[[
	为table表添加indexOf方法（查找元素索引）
	参数：要查找的对象
	返回：元素在表中的索引，未找到返回nil
]]
table.indexOf = function(t, object)
    if type(t) ~= "table" then error("table expected, got " .. type(t), 2) end
    for i, v in pairs(t) do
        if object == v then
            return i
        end
    end
end
--[[
	删除表中指定索引范围内的所有元素
	参数：
	- t: 目标表
	- i1: 起始索引
	- i2: 结束索引
]]
function table.removeRange(t, i1, i2)
	indexes = {}
	for k, v in pairs(t) do
		if (k >= i1 and k <= i2) then
			table.insert(indexes, k)
		end
	end
	for k, v in pairs(indexes) do
		table.remove(t, v)
	end
end
--- 路径平滑算法
---@param orig_path any
function SmoothPath(orig_path)
	local smooth_path = {}
	local path = ShallowCopy(orig_path)
	table.insert(smooth_path, path[1])  -- 保留起点
	table.remove(path, 1)
	-- table.reverse(path)  -- 反转剩余路径便于从末尾处理

	while #path > 0 do
		local lP = smooth_path[#smooth_path]  -- 上一个保留点
		local nP = path[#path]  -- 默认取最远的点

		-- 从后向前扫描，找到最远的直线可达点
		for _, p in pairs(path) do
			-- 计算两点连线方向及其左右法向量
			local dir = get_direction(lP.x, lP.y, p.x, p.y)
			local dir_offset1 = (dir + math.rad(90)) % (2 * math.pi)
			local dir_offset2 = (dir + math.rad(-90)) % (2 * math.pi)
			local vec1_x, vec1_y = rad_to_vec(dir_offset1)
			local vec2_x, vec2_y = rad_to_vec(dir_offset2)

			-- 计算左右扩展边界的起点和终点（扩展5像素用于碰撞检测）
			local start1_x = lP.x + (vec1_x * 5)
			local start1_y = lP.y + (vec1_y * 5)
			local end1_x = p.x + (vec1_x * 5)
			local end1_y = p.y + (vec1_y * 5)
			local start2_x = lP.x + (vec2_x * 5)
			local start2_y = lP.y + (vec2_y * 5)
			local end2_x = p.x + (vec2_x * 5)
			local end2_y = p.y + (vec2_y * 5)

			-- 检查三条线段（主线+左右扩展边界）是否无障碍
			if (not RaytraceSurfaces(lP.x, lP.y, p.x, p.y) and
			    not RaytraceSurfaces(start1_x, start1_y, end1_x, end1_y) and
			    not RaytraceSurfaces(start2_x, start2_y, end2_x, end2_y)) then
				nP = p
				break  -- 找到最优点，退出循环
			end
		end

		-- 将找到的优化点加入平滑路径
		table.insert(smooth_path, nP)
		-- 删除已处理的节点
		local index = table.indexOf(path, nP)
		table.removeRange(path, index, #path)
	end

	return smooth_path
end
--- 浅拷贝函数
---@param orig any
function ShallowCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else
        copy = orig
    end
    return copy
end


