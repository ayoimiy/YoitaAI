
--#region Chunk
local width = 256
local height = 256
local node_size = 8  --节点间距


local Component_id = 0 
local Component_edge_id = 0 

function Get_Component_id()
    Component_id = Component_id + 1
    return Component_id
end
function Get_Component_edge_id()
    Component_edge_id = Component_edge_id + 1
    return Component_edge_id
end

--获取区块key   
---@param x number
---@param y number
---@return string chunk_key 区块key
function Get_chunk_key(x,y)
    local cx = math.floor(x/width)
    local cy = math.floor(y/height)
    local chunk_key = tostring(cx).."_"..tostring(cy)
    return chunk_key
end
---获取区块相对坐标
---@param chunk_key string
function Get_chunk_pos(chunk_key)
    local cx,cy = chunk_key:match("(%d+)_(%d+)")
    return cx,cy
end



---记录区块数据
local Chunk_data = {

}

---记录边数据
local Edge_data = {

}
--连通分量边
local Component_edges = {

}
--所有连通分量的节点集（全局），id -> {["x_y"] = true, ...}
local All_Components = {

}
--#endregion

--@region 连通分量检测

---五射线检查
local function raytrace5(nodeA,nodeB)
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
    if count >= 3 then
        return false
    end
    return true
end

--剔除只有一个节点的连通分量
local function bfs(nodes,start_node)
    local Component = {}
    -- 创建队列
    local queue = {}
    -- 从起点出发
    table.insert(queue,start_node)
    local s_key = start_node.x.."_"..start_node.y
    nodes[s_key] = true
    Component[s_key] = true

    local count = 0

    while #queue > 0 do
        --取出一个节点
        local node = table.remove(queue,1)
        local directions = {{0,node_size},{0,-node_size},{node_size,0},{-node_size,0}}
        --寻找邻居节点
        for _,dir in ipairs(directions) do
            local nx = node.x + dir[1]
            local ny = node.y + dir[2]
            local key = nx.."_"..ny
            local n_node = {x = nx,y = ny}
            if nodes[key] == false and raytrace5(node,n_node) then
                table.insert(queue,n_node)
                nodes[key] = true
                Component[key] = true
                count = count + 1
            end           
        end    
    end 

    if count < 2 then
        return nil
    end
    return Component
end
--获取连通分量
---@param cx number 
---@param cy number
function Floor_fill(cx,cy)
    local nodes = {}
    local Components = {}   -- 连通分量集
    local start_x = cx * width
    local start_y = cy * height
    for y = start_y,start_y + height,node_size do 
        for x = start_x,start_x + width,node_size do
            if not RaytracePlatforms(x,y,x+1,y) then
                nodes[tostring(x).."_"..tostring(y)] = false
            end
        end
    end
    local size = 0 
    for key,value in pairs(nodes) do
        if value == false then
            size = size + 1
        end
    end
    GamePrint("连通分量数量:"..tostring(size))
    --获取新的联通分量
    for y = start_y,start_y + height,node_size do 
        for x = start_x,start_x + width,node_size do
            if nodes[tostring(x).."_"..tostring(y)] == false then
                local new_component = bfs(nodes,{x = x,y = y}) 
                --剔除太少的节点
                if new_component ~= nil then 
                    --给其添加一个id
                    local id  = Get_Component_id()
                    Components[id] = new_component
                end              
            end
        end
    end
  
    local chunk_key = cx.."_"..cy
    --进行联通检测
    if Chunk_data[chunk_key] == nil then
        --未初始化，直接分配id
        Chunk_data[chunk_key] = {}
        for k,_ in pairs(Components) do 
            table.insert(Chunk_data[chunk_key],k) 
            All_Components[k] = Components[k]
        end 

    else
        --进行匹配检测
    end

    return Components 
end

local function update_edge(cx,cy,start_x,start_y,Components)
    local edges = {{width/2,0,0,-1},{0, height/2,-1,0},{width,height/2,1,0},{width/2,height,0,1}}
    local new_components = {}    --当前区间联通分量集
    for _,v in ipairs(edges) do 
        --计算边坐标
        local x = start_x + v[1]
        local y = start_y + v[2]
        --创建边
        local key = x.."_"..y
        if Edge_data[key] == nil then
            Edge_data[key] = {
            }
        end
        --得到边节点集
        for dx = start_x,x,node_size do 
            for dy = start_y,y,node_size do 
                local edge_node_key = dx.."_"..dy
                for k,component in pairs(Components) do 
                    if component[edge_node_key]~= nil  then
                        new_components[key] = new_components[key] or {}
                        table.insert(new_components[key],edge_node_key)
                        break
                    end
                end
            end
        end 
        -- 生成分量边
        -- 查找另一个区块
        local neighbor_chunk = cx + v[3] .. "_" .. cy + v[4]
        if Chunk_data[neighbor_chunk] ~= nil then
            --区块已定义，进行连通分量匹配
            local Edge = Edge_data[key]
            local current_chunk_id = cx .. "_" .. cy
            local edge_nodes = new_components[key] or {}

            --当前区块各连通分量在边上的点集
            local current_comp_nodes = {}   -- key -> node_keys  连通分量 对应 一个点集
            for _, node_key in ipairs(edge_nodes) do
                for comp_id, component in pairs(Components) do
                    if component[node_key] then
                        current_comp_nodes[comp_id] = current_comp_nodes[comp_id] or {}
                        table.insert(current_comp_nodes[comp_id], node_key)
                        break
                    end
                end
            end

            --邻居区块各连通分量在边上的点集,邻居联通分量 key --> node_keys
            local neighbor_comp_nodes = {}
            for _, neighbor_comp_id in ipairs(Chunk_data[neighbor_chunk]) do
                local neighbor_component = All_Components[neighbor_comp_id]
                if neighbor_component then
                    for _, node_key in ipairs(edge_nodes) do
                        if neighbor_component[node_key] then
                            neighbor_comp_nodes[neighbor_comp_id] = neighbor_comp_nodes[neighbor_comp_id] or {}
                            table.insert(neighbor_comp_nodes[neighbor_comp_id], node_key)
                        end
                    end
                end
            end

            --对当前/邻居连通分量对取交集
            for cur_comp_id, cur_nodes in pairs(current_comp_nodes) do
                for neigh_comp_id, neigh_nodes in pairs(neighbor_comp_nodes) do
                    local cur_set = {}
                    for _, n in ipairs(cur_nodes) do cur_set[n] = true end
                    local intersection = {}   --交集 
                    for _, n in ipairs(neigh_nodes) do
                        if cur_set[n] then
                            table.insert(intersection, n)
                        end
                    end
                    if #intersection > 0 then
                        --新增连通分量边id
                        local edge_id = Get_Component_edge_id()
                        Component_edges[edge_id] = intersection
                        --为两边的分量id各建立/更新 Edge[id] -> table
                        for _, comp_id in ipairs({cur_comp_id, neigh_comp_id}) do
                            if type(Edge[comp_id]) ~= "table" then
                                local prev_chunk = Edge[comp_id]
                                Edge[comp_id] = {
                                    chunk = prev_chunk or (comp_id == cur_comp_id and current_chunk_id or neighbor_chunk),
                                    edges = {}
                                }
                            end
                            table.insert(Edge[comp_id].edges, edge_id)
                        end
                    end
                end
            end
        else
            --区块未定义
            local Edge = Edge_data[key]
            local chunk_id = cx .. "_" .. cy
            local edge_nodes = new_components[key]
            if edge_nodes then
                for _, node_key in ipairs(edge_nodes) do
                    for comp_id, component in pairs(Components) do
                        if component[node_key] then
                            Edge[comp_id] = chunk_id
                            break
                        end
                    end
                end
            end
        end
    end
    return new_components
end





