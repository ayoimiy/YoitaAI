
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local Heap = dofile_once(base_file .. "files/scripts/utils/Heap.lua")



--自带的looger
local Logger = {}
Logger.warn = function(self,msg)
	print("[YoitaAI] " .. msg)
end
Logger.info = function(self,msg)
	print("[YoitaAI] " .. msg)
end


---核心算法A*
---@class AStarConfig table 
---@field start  any 起点（最近的网格节点）
---@field get_node_key fun(node): string   获取节点的key，参数为 node 
---@field get_h_func fun(node): number    获取启发函数
---@field get_neighbors_func fun(node) : table    获取邻居节点
---@field get_cost fun(from_node, to_node) : number 获取边代价g值
---@field is_goal fun(node): boolean  是否是目标节点
---@field logger  table?   日志，默认为print	
---@field max_count number? 最大迭代次数，默认5000
AStarConfig = {}
AStarConfig.__index = AStarConfig

---@return AStarConfig
function AStarConfig:new()
	local obj = setmetatable({
		max_count = 5000,
	}, self)
	return obj
end



---@param config AStarConfig 配置
---@return table|nil,table|nil 为一个数组表，存放从起点到终点的所有离散点;为所有遍历的节点
function AStar(config)
	local start = config.start 

	local logger = config.logger or Logger
	local get_node_key = config.get_node_key
	local get_h_func = config.get_h_func
	local get_neighbors_func = config.get_neighbors_func
	local get_cost = config.get_cost
	local is_goal = config.is_goal
	local max_count = config.max_count or 5000

	local open_set = Heap:new()
	local closed_set = {}
	local path_set = {}
	local g_score = {}
	local f_score = {}
	local nodes_set = {}

	local start_key = get_node_key(start)
	g_score[start_key] = 0 
	f_score[start_key] = g_score[start_key] + get_h_func(start)
	open_set:push(f_score[start_key],start_key)
	nodes_set[start_key] = start

	logger:info("[AStar] init f_score: " .. f_score[start_key])
	-- 主循环
	local count = 0
	while open_set:is_empty() == false do
		count = count + 1
		if count > max_count then
			logger:warn("[AStar] max iterations exceeded: " .. max_count)
			break
		end

		-- 取出f_score最低的节点作为当前节点
		local curr_key = open_set:pop()
		if not curr_key then
			break 
		end
		if closed_set[curr_key] then 
			goto continue
		end
		if is_goal(nodes_set[curr_key]) then 
			logger:info("[AStar] goal found, iters: " .. count)
			local path = {}
			local key = curr_key 
			while key do 
				table.insert(path,1,nodes_set[key])
				key = path_set[key]
			end
			logger:info("[AStar] path rebuilt, len=" .. #path)
			return path,nodes_set
		end
		closed_set[curr_key] = true
		local neighbors = get_neighbors_func(nodes_set[curr_key])
		for _,neighbor in ipairs(neighbors) do 
			local key = get_node_key(neighbor)
			if not nodes_set[key] then 
				nodes_set[key] = neighbor
			end
			if not closed_set[key] then
				local g = g_score[curr_key] + get_cost(nodes_set[curr_key],neighbor)
				if (not g_score[key] or g < g_score[key]) then					
					path_set[key] = curr_key
					g_score[key] = g
					f_score[key] = g + get_h_func(neighbor)
					open_set:push(f_score[key],key)
					-- logger:info("[AStar] 添加新节点: " .. key .. " f_score: " .. f_score[key])
				end
			end
		end
		::continue ::
	end
	-- 未找到路径
	logger:warn("[AStar] no path found, iters: " .. count)
	return nil,nodes_set
end




