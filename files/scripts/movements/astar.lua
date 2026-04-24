
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
local M_utils = dofile_once(now_file .. "move_utils.lua")

---核心算法A*
---@param start any
---@param goal any
---@param _nodes table 有效节点集
---@param grid_density any
---@param valid_node_func any
---@return table|nil,table|nil 为一个数组表，存放从起点到终点的所有离散点;为所有遍历的节点
function AStar(start, goal,_nodes, grid_density, valid_node_func,logger)
	-- closed set：已评估过的节点
	local closedset = {}			--记录某个键是否被遍历  {key-->bool}
	-- open set：待评估的节点
	local openset = {}         --记录某个键是否待遍历  {key-->bool}
	-- came_from：记录每个节点的父节点
	local came_from = {}              -- {key-->key}
	local g_score = {}  --真实代价  {key-->value}
	local f_score = {}	--总代价    {key-->value}
	local nodes = _nodes or {}   --所有  {key-->point(x,y)}

	-- 根据是否提供自定义验证函数选择验证方法
	local node_function = nil
	if valid_node_func ~= nil then
		node_function = valid_node_func
		GamePrint("[AStar] 使用自定义验证函数")
	else
		node_function = nil
		GamePrint("[AStar] 使用默认验证函数 IsValidNode")
	end

	local start_key = M_utils.get_point_idx(start.x,start.y,200)
	openset[start_key] = true
	g_score[start_key] = 0
	f_score[start_key] = g_score[start_key] + HeuristicCostEstimate(start, goal)
	nodes[start_key] = start


	logger:info("[AStar] 初始f_score: " .. f_score[start_key])
	
	-- 主循环
	local iteration = 0
	while next(openset) ~=nil do
		iteration = iteration + 1
		-- 取出f_score最低的节点作为当前节点
		local curr_key = LowestFScore(openset, f_score)
		if not curr_key then
			break 
		end
		-- 找到目标，重建路径
		if get_distance_goal2(curr_key,goal.x,goal.y,nodes) < 40  then
			logger:info("[AStar] 找到目标! 迭代次数: " .. iteration)
			local path = UnwindPath({}, came_from, curr_key,nodes)
			table.insert(path, nodes[curr_key])  -- 添加终点
			logger:info("[AStar] 路径重建完成，共 " .. #path .. " 个节点")
			return path,nodes
		end
		-- 将当前节点从open set移到closed set
		openset[curr_key] = nil 
		closedset[curr_key] = true
		-- 遍历所有有效邻居节点
		local neighbors = Get_neighbors(nodes[curr_key],start,goal,nil,grid_density)
		logger:debug("有效邻居信息")
		-- 每10次迭代打印一次进度
		if iteration % 1 == 0 and curr_key then
			logger:debug("[AStar] 迭代: " .. iteration .. " | open: " .. #openset .. " | closed: " .. #closedset .. " | neighbors: " .. #neighbors)
			-- logger:debug("       当前节点: " .. tostring(nodes[current].x) .. ", " .. tostring(nodes[current].y))
			-- logger:info("邻居为" .. logger:print_table(neighbors))
		end
		
		for _, neighbor in ipairs(neighbors) do
			-- 跳过已在closed set中的节点
			local key = M_utils.get_point_idx(neighbor.x,neighbor.y,200)
			if not  nodes[key]  then
				nodes[key] = neighbor
			end

			if (not closedset[key] ) then
				-- 计算经过当前节点到邻居的g值
				local tentative_g_score = g_score[curr_key] + DistanceBetween(nodes[curr_key], neighbor) + Loss_Wall(neighbor)

				-- 如果是更好的路径或邻居不在open set中
				if (not openset[key]) or tentative_g_score < g_score[key] then
					-- 更新路径记录
					came_from[key] = curr_key
					-- logger:info("更新come_from" .. logger:print_table(came_from))
					g_score[key] = tentative_g_score
					f_score[key] = g_score[key] + HeuristicCostEstimate(neighbor, goal)

					-- 如果邻居不在open set中，添加进去
					if (not openset[key]) then
						openset[key] = true
					end
				end
			end
		end
		
		-- 防止无限循环（超过2000次迭代）
		if iteration > 2000 then
			logger:warn("[AStar] 警告: 迭代次数超过5000，强制退出")
			break
		end
	end

	-- 未找到路径
	logger:warn("[AStar] 未找到路径! 迭代次数: " .. iteration)
	logger:warn("       open set剩余: " .. #openset .. " | closed set: " .. #closedset)
	return nil,nodes
end
--- 默认预估函数(采用欧几里得算法)
---@param nodeA table 
---@param nodeB table
function HeuristicCostEstimate(nodeA,nodeB)
	if nodeA.x and nodeA.y and nodeB.x and nodeB.y then
		return M_utils.get_distance(nodeA.x, nodeA.y, nodeB.x, nodeB.y)
	else
		return 0
	end
end


local infinity = 1/0
--- 找到最低的函数
---@param set any
---@param f_score table
---@return number|nil
function LowestFScore(set, f_score)
	local lowest, bestNode = infinity, nil
	for key,_ in pairs(set) do
		local score = f_score[key]
		if score < lowest then
			lowest, bestNode = score, key
		end
	end
	return bestNode
end
--- 移除节点，本质是与最后的节点交换位置，然后函数最后一位节点
---@param set any
---@param theNode any
function RemoveNode(set, theNode)
	for i, node in ipairs(set) do
		if node == theNode then
			set[i] = set[#set]
			set[#set] = nil
			break
		end
	end
end
--- 回溯路径？
---@param flat_path any
---@param map any
---@param curr_key number 当前路径节点
function UnwindPath(flat_path, map, curr_key,t)
	if map[curr_key] then
		-- 每次递归将父节点插入路径数组开头
		table.insert(flat_path, 1, t[map[curr_key]])
		return UnwindPath(flat_path, map, map[curr_key],t)
	else
		return flat_path
	end
end
--- 获取节点的有效邻居
--- 通过射线检测来验证有效性
--- 对新增节点取整处理
---@param current_node table 子节点
---@param goal table  目标节点
---@param solver function|nil 暂无，预计为自定义检测函数
---@param grid_density number 网格宽度
function Get_neighbors(current_node,start, goal, solver, grid_density)
	local neighbors =  {}
	local pre_neighbors = {}
	local dd = {grid_density,0,-grid_density}
	-- 八向节点
	for _,dx in ipairs(dd) do 
		for _,dy in ipairs(dd) do 
			local x = current_node.x +dx
			local y = current_node.y +dy
			if dx~= 0 or dy~=0 then
				table.insert(pre_neighbors,{x=x,y=y})
			end
		end
	end
	-- 检查是否合适
	for _,v in ipairs(pre_neighbors) do
		if (Is_safe(current_node,v) 
			and v.x	<=	start.x	+256
			and v.x	>= 	start.x	-256
			and v.y <= 	start.y +256
			and v.y >= 	start.y -256
		) then
			table.insert(neighbors,v)
		end
	end
	return neighbors
end


local d = 5
--- 验证两点可以通过
---@param point any
---@param curr any
---@return boolean
function Is_safe(point, curr)
	-- 两点直接有无碰撞
    if (RaytraceSurfaces(curr.x, curr.y, point.x, point.y)) then
        return false
    end
	local dx  = point.x-curr.x
	local dy =  point.y -curr.y
	local n = 2   --子节点个数

	local last_x1 = 0 
	local last_x2 = 0 
	local last_y1 = 0 
	local last_y2 = 0 

	-- 处理y，保真宽度
	if (dx ==0 ) then 
		for i = 1,n do 
			local b1,x1,y1  = RaytracePlatforms(curr.x-6,curr.y+i*dy/(n+1),curr.x,curr.y+i*dy/(n+1))
			local b2,x2,y2 = RaytracePlatforms(curr.x,curr.y+i*dy/(n+1),curr.x+6,curr.y+i*dy/(n+1))
			if (i>1) then
				if math.max(x1-last_x1,last_x2-x2,y1-last_y1,last_y2-y2) >d then
					return false
				end
			end
			last_x1 = x1
			last_x2 = x2 
			last_y1 = y1 
			last_y2 = y2

			if (b1 or b2) and (x2-x1<6) then
				return false
			end
		end
	end
	local dx1 = 0 
	local dy1 = 0 
	-- 处理x,保证高度
	if (dy ==0 ) then 
		for i = 1,n do 
			local b1,x1,y1 = RaytracePlatforms(curr.x+i*dx/(n+1),curr.y-16,curr.x+i*dx/(n+1),curr.y)
			local b2,x2,y2 = RaytracePlatforms(curr.x+i*dx/(n+1),curr.y,curr.x+i*dx/(n+1),curr.y+16)

			if (i>1) then
				if math.max(x1-last_x1,last_x2-x2,y1-last_y1,last_y2-y2) >d then
					return false
				end
			end
			last_x1 = x1
			last_x2 = x2 
			last_y1 = y1 
			last_y2 = y2


			if (b1 or b2) and (y2-y1)<16 then
				return false
			end
		end
	end
	-- 处理斜向
	if(dx~=0 and dy~=0) then
		for i = 1,n do	
			local new_x = curr.x+i*dx/(n+1)
			local new_y = curr.y+i*dy/(n+1)
			local b1,x1,y1 = RaytracePlatforms(new_x,new_y,new_x-6,new_y-16)
			local b2,x2,y2 = RaytracePlatforms(new_x,new_y,new_x+6,new_y+16)
			if (i>1) then
				if math.max(x1-last_x1,last_x2-x2,y1-last_y1,last_y2-y2) >d then
					return false
				end
			end
			last_x1 = x1
			last_x2 = x2 
			last_y1 = y1 
			last_y2 = y2
			if (b1 or b2) and ( x2-x1 <6 or y2-y1<16  ) then
				return false
			end
		end
	end
    return true
end
--- 节点是否在集合里面？
---@param set table 集合
---@param theNode table 待求结点
---@return boolean 
function NotIn(set, theNode)
	for _, node in ipairs(set) do
		if node == theNode then return false end
	end
	return true
end
---获取平方距离？
---@param nodeA table
---@param nodeB table
---@return number
function DistanceBetween(nodeA,nodeB,t )

	return M_utils.get_distance(nodeA.x, nodeA.y, nodeB.x, nodeB.y)
end

function get_distance_goal2(nodeA_idx,goal_x,goal_y,t )
	local nodeA = t[nodeA_idx]
	return M_utils.get_distance2(nodeA.x, nodeA.y,goal_x, goal_y)
end

function Loss_Wall(nodeA)
	--检测碰墙的损失
	local b1,x1,y1  = RaytracePlatforms(nodeA.x,nodeA.y,nodeA.x-20,nodeA.y)
	local b2,x2,y2  = RaytracePlatforms(nodeA.x,nodeA.y,nodeA.x+20,nodeA.y)
	local b3,x3,y3  = RaytracePlatforms(nodeA.x,nodeA.y,nodeA.x,nodeA.y-20)
	local b4,x4,y4  = RaytracePlatforms(nodeA.x,nodeA.y,nodeA.x,nodeA.y+20)
	local dist = 0 
	if not (b1 or b2 or b3 or b4) then
		return 0 
	else
		dist=math.min(nodeA.x-x1,x2-nodeA.x,nodeA.y-y3,y4 -nodeA.y)
		if dist > 15.0 then return 0 end
		return 20.0 * (1-dist/10.0)
	end
end