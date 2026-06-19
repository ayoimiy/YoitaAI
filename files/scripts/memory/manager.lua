
--#region Chunk
local width = 256
local height = 256
local node_size = 4  --节点间距


local Component_id = 0 
function Get_Component_id()
    Component_id = Component_id + 1
    return Component_id
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

--
local function bfs(nodes,start_node)
    local Component = {}
    -- 创建队列
    local queue = {}
    -- 从起点出发
    table.insert(queue,start_node)
    local s_key = start_node.x.."_"..start_node.y
    nodes[s_key] = true
    Component[s_key] = true

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
            end           
        end    
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
                table.insert(Components,new_component)
            end
        end
    end
    GamePrint("连通分量数量:"..tostring(#Components))
    return Components 
end







