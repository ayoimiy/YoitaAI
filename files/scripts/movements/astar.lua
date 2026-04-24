
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
local M_utils = dofile_once(now_file .. "move_utils.lua")

---核心算法A*
---@param start any
---@param goal any
---@param nodes table 有效节点集
---@param grid_density any
---@param valid_node_func any
---@return table|nil 为一个数组表，存放从起点到终点的所有离散点
function AStar(start, goal, nodes, grid_density, valid_node_func,logger)


	-- closed set：已评估过的节点
	local closedset = {}
	-- open set：待评估的节点
	local openset = {start}
	-- came_from：记录每个节点的父节点
	local came_from = {}

	-- 根据是否提供自定义验证函数选择验证方法
	local node_function = nil
	if valid_node_func ~= nil then
		node_function = valid_node_func
		GamePrint("[AStar] 使用自定义验证函数")
	else
		node_function = IsValidNode
		GamePrint("[AStar] 使用默认验证函数 IsValidNode")
	end

	-- g_score：从起点到当前节点的实际成本
	-- f_score：g_score + 启发式估算
	local g_score, f_score = {}, {}
	g_score[start] = 0
	f_score[start] = g_score[start] + HeuristicCostEstimate(start, goal,nodes)
	
	logger:info("[AStar] 初始f_score: " .. f_score[start])
	

	-- 主循环
	local iteration = 0
	while #openset > 0 do
		iteration = iteration + 1
		-- 取出f_score最低的节点作为当前节点
		local current = LowestFScore(openset, f_score)

		-- 找到目标，重建路径
		if current == goal then
			logger:info("[AStar] 找到目标! 迭代次数: " .. iteration)
			local path = UnwindPath({}, came_from, goal)
			table.insert(path, goal)  -- 添加终点
			logger:info("[AStar] 路径重建完成，共 " .. #path .. " 个节点")
			return path
		end

		-- 将当前节点从open set移到closed set
		RemoveNode(openset, current)
		table.insert(closedset, current)

		








		-- 遍历所有有效邻居节点
		local neighbors = {}
		for _,v in ipairs(M_utils.get_neighbors(current,65,nodes)) do 
			if (node_function(nodes[current],nodes[v],nodes[goal],grid_density)) then
				table.insert(neighbors,v)
			end			
		end		
		logger:debug("有效邻居信息")
		-- 每10次迭代打印一次进度
		if iteration % 1 == 0 and current then
			logger:debug("[AStar] 迭代: " .. iteration .. " | open: " .. #openset .. " | closed: " .. #closedset .. " | neighbors: " .. #neighbors)
			logger:debug("       当前节点: " .. tostring(nodes[current].x) .. ", " .. tostring(nodes[current].y))
			-- logger:info("邻居为" .. logger:print_table(neighbors))
		end
		
		for _, neighbor in ipairs(neighbors) do
			-- 跳过已在closed set中的节点
			if NotIn(closedset, neighbor) then
				-- 计算经过当前节点到邻居的g值
				local tentative_g_score = g_score[current] + DistanceBetween(current, neighbor,nodes)

				-- 如果是更好的路径或邻居不在open set中
				if NotIn(openset, neighbor) or tentative_g_score < g_score[neighbor] then
					-- 更新路径记录
					came_from[neighbor] = current
					-- logger:info("更新come_from" .. logger:print_table(came_from))
					g_score[neighbor] = tentative_g_score
					f_score[neighbor] = g_score[neighbor] + HeuristicCostEstimate(neighbor, goal,nodes)

					-- 如果邻居不在open set中，添加进去
					if NotIn(openset, neighbor) then
						table.insert(openset, neighbor)
					end
				end
			end
		end
		
		-- 防止无限循环（超过5000次迭代）
		if iteration > 5000 then
			logger:warn("[AStar] 警告: 迭代次数超过5000，强制退出")
			break
		end
	end

	-- 未找到路径
	logger:warn("[AStar] 未找到路径! 迭代次数: " .. iteration)
	logger:warn("       open set剩余: " .. #openset .. " | closed set: " .. #closedset)
	return nil
end
--- 默认预估函数(采用欧几里得算法)
---@param nodeA_idx table 
---@param nodeB_idx table
function HeuristicCostEstimate(nodeA_idx, nodeB_idx,nodes)
	local nodeA = nodes[nodeA_idx]
	local nodeB = nodes[nodeB_idx]
	if nodeA.x and nodeA.y and nodeB.x and nodeB.y then
		return M_utils.get_distance(nodeA.x, nodeA.y, nodeB.x, nodeB.y)
	else
		return 0
	end
end
--- 默认节点验证函数
--- 若节点与领居节点之间存在障碍物或者距离大于10像素，则返回false
---@param node any
---@param neighbor any
---@param goal any
---@param node_density any
---@return boolean
function IsValidNode(node, neighbor, goal, node_density)
	if M_utils.get_distance2(node.x, node.y, neighbor.x, neighbor.y) > 100 then
		return false
	end
	return not IsPointObstructed({x = neighbor.x, y = neighbor.y}, {x = node.x, y = node.y})
end
--- 验证两点直接是否有障碍物
---@param point any
---@param curr any
---@return boolean
function IsPointObstructed(point, curr)
    if (RaytraceSurfaces(curr.x, curr.y, point.x, point.y)) then
        return true
    end
    return false
end
local infinity = 1/0
--- 找到最低的函数
---@param set any
---@param f_score any
---@return number
function LowestFScore(set, f_score)
	local lowest, bestNode = infinity, nil
	for _, node in ipairs(set) do
		local score = f_score[node]
		if score < lowest then
			lowest, bestNode = score, node
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
---@param current_node any
function UnwindPath(flat_path, map, current_node)
	if map[current_node] then
		-- 每次递归将父节点插入路径数组开头
		table.insert(flat_path, 1, map[current_node])
		return UnwindPath(flat_path, map, map[current_node])
	else
		return flat_path
	end
end
--- 获取节点的有效邻居
---@param theNode any
---@param nodes any
---@param goal any
---@param solver any
---@param grid_density any
function NeighborNodes(theNode, nodes, goal, solver, grid_density)
	local neighbors =  {}
	for _, node in ipairs(nodes) do
		-- 调用solver函数验证节点有效性，排除自身
		if theNode ~= node and solver(nodes[theNode], nodes[node], goal, grid_density) then
			table.insert(neighbors, node)
		end
	end
	return neighbors
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
---@param nodeA_idx number
---@param nodeB_idx number 
---@return number
function DistanceBetween(nodeA_idx, nodeB_idx,nodes)
	local nodeA = nodes[nodeA_idx]
	local nodeB = nodes[nodeB_idx]
	return M_utils.get_distance(nodeA.x, nodeA.y, nodeB.x, nodeB.y)
end