
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





---记录区块数据
Chunk_data = {

}
---记录区块指纹(用于变更检测): chunk_key -> { [comp_id] = fingerprint_string }
Chunk_fingerprints = {

}
---记录区块各边的覆盖指纹: chunk_key -> { [edge_key] = fingerprint_string }
Chunk_edge_fps = {

}
---记录边数据
Edge_data = {

}
--连通分量边
Component_edges = {

}
--所有连通分量的边点子集（全局,仅用于跨区块边连接查询），id -> {["x_y"] = true, ...}
All_Components = {

}
--#endregion

--#region 对象

local function class()
    local _class = {}
    _class.__index = _class
    _class.__newindex = function (t,key,value)
        if rawget(_class,key) ~= nil then
            error("Cannot assign to a read-only field")
        else
            rawset(t,key,value)
        end      
    end
    _class.new = function (self,...)
        local obj = setmetatable({},_class)
        if obj.init then obj:init(...) end
        return obj
    end
    return _class
end
---节点 key -> 周长位索引 (0..127)
---周长线性化(128位): 顶边(0..32) | 右边去顶角(33..64) | 底边去右角(65..96) | 左边去底角和顶角(97..127)
---@param key string "x_y"
---@param start_x number 区块起始x
---@param start_y number 区块起始y
---@return number bit_index 0..127
local function node_to_bit(key, start_x, start_y)
    local nx, ny = key:match("(-?%d+)_(-?%d+)")
    nx, ny = tonumber(nx), tonumber(ny)
    local end_x = start_x + width
    local end_y = start_y + height
    if ny == start_y and nx >= start_x and nx <= end_x then
        return (nx - start_x) / node_size               --顶边 0..32
    elseif nx == end_x and ny >= start_y and ny <= end_y then
        return 32 + (ny - start_y) / node_size           --右边 33..64
    elseif ny == end_y and nx >= start_x and nx <= end_x then
        return 64 + (end_x - nx) / node_size             --底边 65..96
    elseif nx == start_x and ny >= start_y and ny <= end_y then
        return 96 + (end_y - ny) / node_size             --左边 97..127
    end
    return -1   --非周长节点
end

---边点子集 -> 16 字节二进制位掩码(128位周长)
---@param edge_set table { [node_key] = true }
---@param start_x number 区块起始x
---@param start_y number 区块起始y
---@return string 16 字节二进制串
local function edge_set_to_mask(edge_set, start_x, start_y)
    local bytes = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    for key in pairs(edge_set) do
        local bit_idx = node_to_bit(key, start_x, start_y)
        if bit_idx >= 0 and bit_idx < 128 then   --守卫:跳过非周长节点
            local byte_idx = math.floor(bit_idx / 8) + 1
            local bit_in_byte = bit_idx % 8
            bytes[byte_idx] = bytes[byte_idx] + (2 ^ bit_in_byte)
        end
    end
    return string.char(bytes[1],bytes[2],bytes[3],bytes[4],
                       bytes[5],bytes[6],bytes[7],bytes[8],
                       bytes[9],bytes[10],bytes[11],bytes[12],
                       bytes[13],bytes[14],bytes[15],bytes[16])
end





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



---测试位掩码中某位是否被置位
---@param mask string 16 字节二进制串
---@param bit_idx number 0..127
---@return boolean
local function mask_bit_test(mask, bit_idx)
    local byte_idx = math.floor(bit_idx / 8) + 1
    local bit_in_byte = bit_idx % 8
    local byte_val = string.byte(mask, byte_idx)
    return math.floor(byte_val / (2 ^ bit_in_byte)) % 2 == 1
end

---给一个边点子集算稳定指纹(128位位掩码, 输出32 hex字符, 零碰撞)
---@param edge_set table { [node_key] = true }
---@param start_x number 区块起始x
---@param start_y number 区块起始y
---@return string 32 hex 字符
local function hash_component(edge_set, start_x, start_y)
    local mask = edge_set_to_mask(edge_set, start_x, start_y)
    local hex = ""
    for i = 1, 16 do
        hex = hex .. string.format("%02x", string.byte(mask, i))
    end
    return hex
end

---从连通分量中提取位于区块4条边上的节点子集
---All_Components 仅用于跨区块边连接查询,内部节点无需持久化,可大幅缩减内存
---@param comp table { [node_key] = true }
---@param start_x number 区块起始x
---@param start_y number 区块起始y
---@return table 边点子集 { [node_key] = true }
local function extract_edge_nodes(comp, start_x, start_y)
    local subset = {}
    local end_x = start_x + width
    local end_y = start_y + height
    for key in pairs(comp) do
        local sx, sy = key:match("(-?%d+)_(-?%d+)")
        local nx, ny = tonumber(sx), tonumber(sy)
        if nx == start_x or nx == end_x or ny == start_y or ny == end_y then
            subset[key] = true
        end
    end
    return subset
end

--清理单个旧连通分量本体(边数据由 update_edge 的边级指纹负责清理)
local function Cleanup_component(old_comp_id)
    All_Components[old_comp_id] = nil
end

--计算某条边上本端各连通分量的覆盖指纹(与遍历顺序无关)
--返回指纹字符串(空串表示该边无本端分量覆盖)
--位掩码编码: 节点在 sorted edge_nodes 中的位置(0-based)作为位索引, 每分量输出定长 hex
---@param edge_nodes string[]  边点集合
---@param Components table{ [id] = { [node_key] = true } }  本区块所有的连通分量
local function hash_edge_side(edge_nodes, Components)
    local n = #edge_nodes
    if n == 0 then return "" end
    --排序确保位置编码与遍历顺序无关
    table.sort(edge_nodes)
    local num_bytes = math.ceil(n / 8)
    --各分量 -> 字节数组
    local comp_bytes = {}
    local comp_ids_set = {}
    for pos, node_key in ipairs(edge_nodes) do  --pos 1-based
        for comp_id, component in pairs(Components) do
            if component[node_key] then
                local byte_idx = math.floor((pos - 1) / 8) + 1
                local bit_in_byte = (pos - 1) % 8
                if not comp_bytes[comp_id] then
                    comp_bytes[comp_id] = {}
                    comp_ids_set[comp_id] = true
                end
                comp_bytes[comp_id][byte_idx] = (comp_bytes[comp_id][byte_idx] or 0) + (2 ^ bit_in_byte)
                break
            end
        end
    end
    --按 comp_id 排序输出 "id1:hex1|id2:hex2|..."
    local comp_ids = {}
    for id in pairs(comp_ids_set) do table.insert(comp_ids, id) end
    table.sort(comp_ids)
    local parts = {}
    for _, id in ipairs(comp_ids) do
        local bytes = comp_bytes[id]
        local hex = ""
        for i = 1, num_bytes do
            hex = hex .. string.format("%02x", bytes[i] or 0)
        end
        table.insert(parts, id .. ":" .. hex)
    end
    return table.concat(parts, "|")
end

--清理某条边上"本端"若干分量的 entry 及其涉及的 edge_id
--side_comp_ids: 本端要清理的分量 id 集合 { [id] = true }
--会删除: Edge_data[edge_key][id] 的 entry,
--        以及该 entry 涉及的 Component_edges[edge_id] 和同边上其他分量 edges 数组中的引用
--(邻居侧 entry 也在同一条 Edge_data[edge_key] 中,会一并被清理)
---@param edge_key string 边 key
---@param side_comp_ids table{ [id] = true }
local function Clear_edge_side_entries(edge_key, side_comp_ids)
    local Edge = Edge_data[edge_key]
    if not Edge then return end
    --收集所有要清理的 edge_id(涉及 side 中任一分量的 table entry)
    local dead_edges = {}
    for comp_id in pairs(side_comp_ids) do
        local entry = Edge[comp_id]
        if type(entry) == "table" and entry.edges then
            for _, eid in ipairs(entry.edges) do
                dead_edges[eid] = true
            end
        end
    end
    --删除 Component_edges 记录,并从同边上所有其他分量的 edges 数组中移除
    for eid in pairs(dead_edges) do
        Component_edges[eid] = nil
        for other_id, other_entry in pairs(Edge) do
            if type(other_entry) == "table" and other_entry.edges then
                for i = #other_entry.edges, 1, -1 do
                    if other_entry.edges[i] == eid then
                        table.remove(other_entry.edges, i)
                    end
                end
            end
        end
    end
    --删除 side 中各分量的 entry(字符串形态或 table 形态)
    for comp_id in pairs(side_comp_ids) do
        Edge[comp_id] = nil
    end
end

local update_edge  --前向声明(定义在 Floor_fill 之后)

--获取连通分量
---@param cx number
---@param cy number
function Floor_fill(cx,cy)
    ---将区块转化为可用点集合
    local nodes = {}
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
    GamePrint("区域节点个数:"..tostring(size))

    --BFS 扫描新连通分量(暂存为数组,稍后再分配/复用 id)
    local new_comps_temp = {}
    for y = start_y,start_y + height,node_size do
        for x = start_x,start_x + width,node_size do
            if nodes[tostring(x).."_"..tostring(y)] == false then
                local new_component = bfs(nodes,{x = x,y = y})
                if new_component ~= nil then
                    table.insert(new_comps_temp, new_component)
                end
            end
        end
    end

    local chunk_key = cx.."_"..cy
    local old_fps = Chunk_fingerprints[chunk_key] or {}

    --计算新分量指纹(基于边点子集,与 All_Components 持久化内容一致)
    --边集指纹的语义:仅在边连接拓扑变化时才判定分量变化,内部节点变化不触发边重建
    local new_fps = {}
    local new_edge_sets = {}    --预计算边点子集,供指纹计算与 All_Components 持久化复用
    for i, comp in ipairs(new_comps_temp) do
        local edge_set = extract_edge_nodes(comp, start_x, start_y)
        new_edge_sets[i] = edge_set
        new_fps[i] = hash_component(edge_set, start_x, start_y)
    end

    --与原连通分量进行匹配检测(按指纹 1-to-1 匹配,命中则复用旧 id)
    local matched = {}      -- temp_idx -> old_comp_id
    local used_old = {}
    for i, fp in ipairs(new_fps) do
        for old_id, old_fp in pairs(old_fps) do
            if not used_old[old_id] and old_fp == fp then
                matched[i] = old_id
                used_old[old_id] = true
                break
            end
        end
    end

    --判断区块是否完全未变(所有分量指纹都匹配上,且数量一致)
    local old_count = 0
    for _ in pairs(old_fps) do old_count = old_count + 1 end
    local all_matched = (#new_comps_temp == old_count)
    if all_matched then
        for i in ipairs(new_comps_temp) do
            if not matched[i] then all_matched = false break end
        end
    end

    --清理未匹配上的旧连通分量本体(边数据由 update_edge 的边级指纹负责清理)
    for old_id in pairs(old_fps) do
        if not used_old[old_id] then
            Cleanup_component(old_id)
        end
    end

    --分配最终 id:匹配上的复用旧 id,未匹配的分配新 id
    local Components = {}    --现有连通分量
    local final_fps = {}    --新分量指纹
    Chunk_data[chunk_key] = {}
    for i, comp in ipairs(new_comps_temp) do
        local final_id = matched[i] or Get_Component_id()    --最终使用的联通分量id 
        Components[final_id] = comp
        --All_Components 持久化为 16 字节位掩码 + 所属 chunk 起始坐标(跨区块边连接查询用)
        All_Components[final_id] = {
            mask = edge_set_to_mask(new_edge_sets[i], start_x, start_y),
            sx = start_x,
            sy = start_y,
        }
        final_fps[final_id] = new_fps[i]   -- id --> 分量哈希
        table.insert(Chunk_data[chunk_key], final_id)
    end
    Chunk_fingerprints[chunk_key] = final_fps     --区间指纹

    --区块有变化时重建跨区块边(完全未变则跳过,保留原有边数据)
    if not all_matched then
        update_edge(cx, cy, start_x, start_y, Components)
    end

    return Components, all_matched
end

update_edge = function(cx,cy,start_x,start_y,Components)
    local edges = {{width/2,0,0,-1},{0, height/2,-1,0},{width,height/2,1,0},{width/2,height,0,1}}
    local new_components = {}    --当前区间联通分量集
    local chunk_key = cx.."_"..cy
    Chunk_edge_fps[chunk_key] = Chunk_edge_fps[chunk_key] or {}

    for _,v in ipairs(edges) do
        --计算边坐标
        local x = start_x + v[1]
        local y = start_y + v[2]
        local key = x.."_"..y

        --得到本端在边上的节点集(沿共享边 1D 遍历)
        --v[3],v[4] 为邻居方向: 据此判定本端是哪条边(顶/底 y固定, 左/右 x固定)
        local edge_nodes = {}
        local ndx, ndy = v[3], v[4]
        if ndy ~= 0 then
            --顶/底边: y 固定, x 沿 width 方向遍历
            local fixed_y = start_y + (ndy < 0 and 0 or height)
            for fx = start_x, start_x + width, node_size do
                local edge_node_key = fx.."_"..fixed_y
                for _,component in pairs(Components) do
                    if component[edge_node_key] ~= nil then
                        table.insert(edge_nodes, edge_node_key)
                        break
                    end
                end
            end
        else
            --左/右边: x 固定, y 沿 height 方向遍历
            local fixed_x = start_x + (ndx < 0 and 0 or width)
            for fy = start_y, start_y + height, node_size do
                local edge_node_key = fixed_x.."_"..fy
                for _,component in pairs(Components) do
                    if component[edge_node_key] ~= nil then
                        table.insert(edge_nodes, edge_node_key)
                        break
                    end
                end
            end
        end
        new_components[key] = edge_nodes

        --计算本端在该边上的覆盖指纹,与旧指纹对比
        local new_fp = hash_edge_side(edge_nodes, Components)
        local old_fp = Chunk_edge_fps[chunk_key][key]

        if old_fp == new_fp then
            --指纹相同:跳过该边,保留原有 edge_id(邻居无感)
        else
            --指纹变化:重建该边
            if Edge_data[key] == nil then
                Edge_data[key] = {}
            end
            local Edge = Edge_data[key]  --当前边

            --收集本端在该边上的所有旧 entry(字符串形态或 table 且 chunk==本区块)
            --并清理它们,为重建腾出空间(邻居侧 entry 的 edges 数组引用会一并清掉)
            local side_comp_ids = {}
            for comp_id, entry in pairs(Edge) do
                if type(entry) == "string" then
                    side_comp_ids[comp_id] = true
                elseif type(entry) == "table" and entry.chunk == chunk_key then
                    side_comp_ids[comp_id] = true
                end
            end
            Clear_edge_side_entries(key, side_comp_ids)

            --查找另一个区块
            local neighbor_chunk = cx + v[3] .. "_" .. cy + v[4]
            local current_chunk_id = cx .. "_" .. cy

            if Chunk_data[neighbor_chunk] ~= nil then
                --区块已定义,进行连通分量匹配
                --当前区块各连通分量在边上的点集
                local current_comp_nodes = {}
                for _, node_key in ipairs(edge_nodes) do
                    for comp_id, component in pairs(Components) do
                        if component[node_key] then
                            current_comp_nodes[comp_id] = current_comp_nodes[comp_id] or {}
                            table.insert(current_comp_nodes[comp_id], node_key)
                            break
                        end
                    end
                end

                --邻居区块各连通分量在边上的点集
                local neighbor_comp_nodes = {}
                for _, neighbor_comp_id in ipairs(Chunk_data[neighbor_chunk]) do
                    local neighbor_component = All_Components[neighbor_comp_id]
                    if neighbor_component then
                        --用邻居所属 chunk 坐标计算位索引(共享边节点落在邻居周长正确位置)
                        for _, node_key in ipairs(edge_nodes) do
                            local bit_idx = node_to_bit(node_key, neighbor_component.sx, neighbor_component.sy)
                            -- 仅处理落在邻居周长有效位(0-127)的节点，过滤非共享边上的矩形区域节点
                            if bit_idx >= 0 and bit_idx < 128 and mask_bit_test(neighbor_component.mask, bit_idx) then
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
                        local intersection = {}
                        for _, n in ipairs(neigh_nodes) do
                            if cur_set[n] then
                                table.insert(intersection, n)
                            end
                        end
                        if #intersection > 0 then
                            local edge_id = Get_Component_edge_id()
                            --结构化记录: 端点分量对 + 共享节点 + 所在边
                            --使 Get_component_neighbors 可 O(度数) 反向查邻居,无需线性扫描 Edge_data
                            Component_edges[edge_id] = {
                                nodes     = intersection,   --共享节点(寻路时作为跨chunk"门"坐标)
                                a         = cur_comp_id,    --端点 A
                                b         = neigh_comp_id,  --端点 B
                                edge_key  = key,            --所在共享边
                            }
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
                --区块未定义:本端是先扫描的,写入字符串形态占位
                local chunk_id = cx .. "_" .. cy
                for _, node_key in ipairs(edge_nodes) do
                    for comp_id, component in pairs(Components) do
                        if component[node_key] then
                            Edge[comp_id] = chunk_id
                            break
                        end
                    end
                end
            end

            --更新该边的指纹
            Chunk_edge_fps[chunk_key][key] = new_fp
        end
    end
    return new_components
end

---查询某连通分量的所有邻居分量(及其连接信息)
---复杂度: O(该分量的度数), 不再线性扫描 Edge_data
---@param comp_id number 连通分量 id
---@return table { [neighbor_comp_id] = {nodes=string[], edge_id=number, edge_key=string}, ... }
function Get_component_neighbors(comp_id)
    local info = All_Components[comp_id]
    if not info then return {} end
    --该分量所属 chunk 的 4 条共享边中点 key
    local edge_keys = {
        (info.sx + width/2).."_"..info.sy,                 --顶
        (info.sx + width/2).."_"..(info.sy + height),      --底
        info.sx.."_"..(info.sy + height/2),                --左
        (info.sx + width).."_"..(info.sy + height/2),      --右
    }
    local result = {}
    for _, ek in ipairs(edge_keys) do
        local edge_tbl = Edge_data[ek]
        if edge_tbl then
            local entry = edge_tbl[comp_id]
            if type(entry) == "table" and entry.edges then
                for _, eid in ipairs(entry.edges) do
                    local ce = Component_edges[eid]
                    --ce 可能已被 Clear_edge_side_entries 置 nil,需判空
                    if ce and ce.a and ce.b then
                        local other = (ce.a == comp_id) and ce.b or ce.a
                        --同一对分量在同一条共享边上至多产生一个 edge_id,取首次命中即可
                        if not result[other] then
                            result[other] = { nodes = ce.nodes, edge_id = eid, edge_key = ek }
                        end
                    end
                end
            end
        end
    end
    return result
end
