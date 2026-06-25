--#region 全局数据

local Block_id = 0 
local Component_edge_id = 0 

function Get_Block_id()
    Block_id = Block_id + 1
    return Block_id
end
function Get_Component_edge_id()
    Component_edge_id = Component_edge_id + 1
    return Component_edge_id
end

--全局数据
local width = 256
local height = 256
local node_size = 8
---记录区块数据
---@type table<string,Chunk>
local Chunk_data = {}
--记录所有连通分量
---@type table<number,Block>
local Block_data = {}

---@class Direction 
---@field dx number
---@field dy number
---@operator unm:Direction
local Direction = {}
---@return Direction
function Direction:new(dx,dy)
    local obj = {dx = dx,dy = dy}
    setmetatable(obj,Direction)
    return obj
end
Direction.__index = Direction
---@return Direction
Direction.__unm = function (t)
    return Direction:new(-t.dx, -t.dy)
end
Direction.__eq = function (dir1,dir2)
    if dir1.dx == dir2.dx and dir1.dy == dir2.dy then
        return true
    end
    return false
end
function Direction:tostring()
   return self.dx .. "_" .. self.dy
end

---@type table<string,Direction>
local Directions = {
    LEFT = Direction:new(-1,0),
    RIGHT = Direction:new(1,0),
    TOP = Direction:new(0,-1),
    BOTTOM = Direction:new(0,1)
}

--#endregion


--#region local函数(不依赖类)

--五射线检测
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
--寻找相连通的点集
---@param nodes table<string,boolean> 所有符合条件的节点集合
---@param edge_set table<string,boolean> 边节点集合
---@param start_node table 开始点
---@param node_size number 节点大小
local function bfs(nodes,edge_set,start_node,node_size)
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
        local dirs =  Directions
        --寻找邻居节点
        for k,dir in pairs(dirs) do
            local nx = node.x + dir.dx * node_size
            local ny = node.y + dir.dy * node_size
            local key = nx.."_"..ny
            local n_node = {x = nx,y = ny}
            if nodes[key] == false and raytrace5(node,n_node) then
                --检查是不是两个都是边界点
                if not (edge_set[key] and edge_set[node.x .. "_" .. node.y]) then
                    table.insert(queue,n_node)
                    nodes[key] = true
                    Component[key] = true
                    count = count + 1
                end 
            end
        end
    end
    if count < 2 then
        return nil
    end
    return Component
end

--检查某个点是否可用
---@param node_key string
local function check_node(node_key)
    local x,y = node_key:match("(-?%d+)_(-?%d+)")
    if RaytracePlatforms(x,y,x+1,y) then
       return false 
    end
    return true
end



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

---@class Chunk
---@field new fun(self,cx:number,cy:number):Chunk
---@field cx number 区块x
---@field cy number 区块y
---@field blocks number[] 连通块id列表(实际 Block 对象存于 Block_data)
local Chunk = class()
function Chunk:init(cx,cy)
    self.cx = cx
    self.cy = cy
    self.blocks = {}
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
        return (nx - start_x) / node_size              --顶边 0..32
    elseif nx == end_x and ny >= start_y and ny <= end_y then
        return 32 + (ny - start_y) / node_size          --右边 33..64
    elseif ny == end_y and nx >= start_x and nx <= end_x then
        return 64 + (end_x - nx) / node_size            --底边 65..96
    elseif nx == start_x and ny >= start_y and ny <= end_y then
        return 96 + (end_y - ny) / node_size            --左边 97..127
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

---边点集掩码 -> 点集
---当指定 edge 时返回 { [node_key] = true } 单边 set
---当不传 edge 时返回 { top={}, right={}, bottom={}, left={} } 四边结构
---@param mask string 16 字节二进制串
---@param start_x number 区块起始x
---@param start_y number 区块起始y
---@param dir Direction
---@return table<string,boolean>
local function mask_to_edge_set(mask, start_x, start_y, dir)
    local end_x = start_x + width
    local end_y = start_y + height
    local ns = node_size

    local single = dir ~= nil
    local result = {}
    for byte_idx = 1, 16 do
        local byte_val = string.byte(mask, byte_idx)
        if byte_val and byte_val > 0 then
            for bit_in_byte = 0, 7 do
                if math.floor(byte_val / (2 ^ bit_in_byte)) % 2 == 1 then
                    local bit_idx = (byte_idx - 1) * 8 + bit_in_byte
                    local edge_dir

                    if bit_idx < 32 and bit_idx > 0 then
                        edge_dir = Directions.TOP
                    elseif bit_idx < 64 and bit_idx > 32 then
                        edge_dir = Directions.RIGHT
                    elseif bit_idx < 96 and bit_idx > 64 then
                        edge_dir = Directions.BOTTOM
                    elseif bit_idx < 128 and bit_idx > 96 then
                        edge_dir = Directions.LEFT
                    end

                    --单边模式: 跳过不匹配的位
                    if single and edge_dir ~= dir then
                        goto continue
                    end

                    local nx, ny
                    if edge_dir == Directions.TOP then
                        nx = start_x + bit_idx * ns
                        ny = start_y
                    elseif edge_dir == Directions.RIGHT then
                        nx = end_x
                        ny = start_y + (bit_idx - 32) * ns
                    elseif edge_dir == Directions.BOTTOM then
                        nx = end_x - (bit_idx - 64) * ns
                        ny = end_y
                    elseif edge_dir == Directions.LEFT then
                        nx = start_x
                        ny = end_y - (bit_idx - 96) * ns
                    else
                        --如果是角点，则跳过
                        goto continue
                    end

                    if single then 
                        result[tostring(nx).."_"..tostring(ny)] = true
                    end
                end
                ::continue::
            end
        end
    end

    return result
end

---获取区块pos
---@param x number
---@param y number
---@return number cx, number cy
function Chunk.get_pos(x,y)
    local cx = math.floor(x/width)
    local cy = math.floor(y/height)
    return cx,cy
end
--获取区块key   
---@param x number
---@param y number
---@return string chunk_key 区块key
function Chunk.get_key(x,y)
    local cx,cy = Chunk.get_pos(x,y)
    local chunk_key = tostring(cx).."_"..tostring(cy)
    return chunk_key
end

--获取边节点
---@return table<string,table<string,boolean>>
function Chunk:get_edge_nodes()
    local sx,sy = self.cx * width,self.cy * height
    local Edge = {
        LEFT = {sx,sy,sx,sy+height},
        RIGHT = {sx+width,sy,sx+width,sy+height},
        TOP = {sx,sy,sx+width,sy},
        BOTTOM = {sx,sy+height,sx+width,sy+height}
    }
    local nodes = {}
    for k,v in pairs(Edge) do
        local dir = Directions[k]:tostring()
        nodes[dir] = {}
        for x = v[1],v[3],node_size do
            for y = v[2],v[4],node_size do
                nodes[dir][tostring(x).."_"..tostring(y)] = true
            end
        end
    end
    return nodes
end
---将区块内的点转化为节点集
function Chunk:to_nodes()
    local sx = self.cx * width
    local sy = self.cy * height
    local nodes = {}
    for y = sy,sy + height,node_size do 
        for x = sx,sx + width,node_size do
            local node_key = x .. "_" .. y
            if check_node(node_key) then
                nodes[node_key] = false
            end
        end
    end
    return nodes
end
---将区块切分成内部连通的点集
---@param edge_set table 边节点集
function Chunk:get_nodes(edge_set)
    local comps = {}
    local nodes = self:to_nodes()
    local sx,sy = self.cx * width,self.cy * height
    --只遍历内部点，边界点由内部点bfs获取
    for y = sy + node_size,sy + height - node_size,node_size do 
        for x = sx + node_size,sx + width - node_size,node_size do
            if nodes[ tostring(x).."_"..tostring(y)] == false then
               local comp = bfs(nodes,edge_set,{x = x,y = y},node_size)
               if comp ~= nil then
                    table.insert(comps,comp)
               end
            end  
        end
    end
    return comps
end
--获取边集key
---@param edge_set table 区块的边节点集
---@param nodes table 尚未分配的节点集
---@return string key 边节点mask
function Chunk:nodes_get_edge_key(edge_set,nodes)
    local sx = self.cx * width
    local sy = self.cy * height
    local edge_nodes = {}
    for node,_ in pairs(nodes) do 
        for _,dir in pairs(Directions) do 
            local edge = dir:tostring()
            if edge_set[edge][node] then
                --若节点在边集内
                edge_nodes[node] = true
            end
        end
    end
    local key = edge_set_to_mask(edge_nodes,sx,sy)
    return key
end


---@class Block 连通块
---@field new fun(self,hash_key:string,chunk_key:string):Block
---@field id number 连通块id
---@field hash_key string 连通块hash值，用于检测是否发生的变化
---@field chunk_key string 所属区块
---@field neighbors table<number|string,boolean>  邻居id集合
local Block = class()
---@param chunk_key string 所属区块
---@param hash_key string 哈希掩码
function Block:init(hash_key,chunk_key)
    self.hash_key = hash_key or ""
    self.chunk_key = chunk_key
    self.id = Get_Block_id()
    self.neighbors = {}
end
---@param dir Direction
---@return table<string,boolean>nodes 
function Block:get_edge(dir)
    local chunk_key = self.chunk_key
    local chunk = Chunk_data[chunk_key]
    return mask_to_edge_set(self.hash_key,chunk.cx * width,chunk.cy * height,dir)
end


--#endregion

--#region 实际运行

--负责清理所有旧块残余
local function Clean_old_blocks(block_id)
    local block = Block_data[block_id]
    --清理Block_data的数据
    Block_data[block_id] = nil
    local chunk_key = block.chunk_key
    local chunk = Chunk_data[chunk_key]
    --清理邻居节点中的连接
    for _,v in pairs(Directions) do 
        local cx = chunk.cx + v.dx
        local cy = chunk.cy + v.dy
        local key = tostring(cx).."_"..tostring(cy)
        local nchunk = Chunk_data[key]
        if nchunk then
            for _,nblock_id in ipairs(nchunk.blocks) do 
                local nblock = Block_data[nblock_id]
                if nblock.neighbors[block_id] ~= nil then
                    nblock.neighbors[block_id] = nil
                end
            end
        end
    end
end

--负责创建新块，并更新连接关系
---@param block_fps string
---@param chunk_key string
---@return Block block
local function Create_new_blocks(block_fps,chunk_key)
    local block = Block:new(block_fps, chunk_key)
    Block_data[block.id] = block
    --更新连接关系
    local chunk = Chunk_data[chunk_key]
    for _,dir in pairs(Directions) do 
        local cx = chunk.cx + dir.dx
        local cy = chunk.cy + dir.dy
        local key = tostring(cx).."_"..tostring(cy)
        local nchunk = Chunk_data[key]
        if nchunk then 
            local nblocks = nchunk.blocks
            for _,nblock_id in ipairs(nblocks) do 
                local nblock = Block_data[nblock_id]
                local nedge_set = nblock:get_edge(-dir)
                local edge_set = block:get_edge(dir)
                --取交集
                local count = 0 
                
                for node,_ in pairs(edge_set) do 
                    if nedge_set[node] then
                        count = count + 1
                    end
                end
                if count > 0 then
                   --建立连接关系
                    block.neighbors[nblock.id] = true
                    nblock.neighbors[block.id] = true
                    --清理占位
                    --同理，当块已存在时，不应该还残存旧块的占位
                    nblock.neighbors[chunk_key] = nil
                end
            end
            --当区块已存在时，不应该还残存旧块的占位
            block.neighbors[key] = nil
        elseif next(block:get_edge(dir)) ~= nil then
            --检查边界点是否可以进入该区块
            local edge_set = block:get_edge(dir)
            local count = 0
            for node_key in pairs(edge_set) do 
                if check_node(node_key) then
                    count = count + 1
                end
            end
            if count > 0 then
                --建立连接关系
                block.neighbors[key] = true
            end

        end
    end
    return block
end


---@param chunk_key string 区间key
---@return  table blocks_nodes,boolean is_change
local function floor_fill(chunk_key)
    --获取区块
    local chunk = Chunk_data[chunk_key]
    if chunk == nil then
        local cx,cy = chunk_key:match("(-?%d+)_(-?%d+)")
        chunk = Chunk:new(cx,cy)
        Chunk_data[chunk_key] = chunk
    end
    local is_change = false
    local edge_set = chunk:get_edge_nodes()
    local comps = chunk:get_nodes(edge_set)
    --记录新连通点集的边指纹
    local comps_fps = {}
    for i, comp in ipairs(comps) do 
        comps_fps[i] = chunk:nodes_get_edge_key(edge_set,comp)
    end
    --获取旧连通块id列表
    local block_ids = chunk.blocks
    --匹配: temp_idx -> 旧 block 在 block_ids 中的索引 j
    local matched = {}
    local used_old = {}

    for i,fp in ipairs(comps_fps) do
        for j,block_id in ipairs(block_ids) do
            local block = Block_data[block_id]
            if block and not used_old[j] and fp == block.hash_key then
                matched[i] = j
                used_old[j] = true
                break
            end
        end
    end

    --清理未匹配的旧block: 从Block_data中移除,并清理邻居引用
    for j,old_block_id in ipairs(block_ids) do
        if not used_old[j] then
            Clean_old_blocks(old_block_id)
            is_change = true
        end
    end

    --创建新block: 未匹配到旧block的新连通分量; 匹配上的复用旧 id
    local new_block_ids = {}
    local blocks_nodes = {}

    --刷新分量块，顺便匹配玩家坐标
    for i,v in ipairs(comps) do
        local block_id
        if matched[i] then
            --匹配上的保留旧block id
            block_id = block_ids[matched[i]]
        else
            --未匹配上的创建新block
            local block = Create_new_blocks(comps_fps[i], chunk_key)
            block_id = block.id
            is_change = true
        end
        
        new_block_ids[i] = block_id
        blocks_nodes[block_id] = v
    end
    chunk.blocks = new_block_ids

    return  blocks_nodes, is_change

end

--#endregion

---@class Manager
---@field node_size number 节点步长(8px)，对齐Chunk.node_size
---@field Floor_fill fun(chunk_key:string):table,boolean 扫描并更新区块连通分量
---@field get_chunk_key fun(x:number,y:number):string 世界坐标转区块key
---@field get_block_chunk_key fun(block_id:number):string block id → 所属区块key
---@field get_block_distant fun(chunk_key1:string,chunk_key2:string):number 两区块间的曼哈顿距离(单位:chunk)
---@field get_block_neighbors fun(block_id:number):table<number, number|string> 返回邻居列表(number=block id, string=未知chunk)
---@field get_block_edge fun(from_node:string|number,to_node:string|number):table<string,boolean> 两block共享边上的节点交集
local M = {
    node_size = node_size,
    Floor_fill = floor_fill,
    ---世界坐标转区块key
    ---@param x number 世界坐标x
    ---@param y number 世界坐标y
    ---@return string chunk_key 格式 "cx_cy"
    get_chunk_key = function (x,y)
        return Chunk.get_key(x,y)
    end,
    ---通过 block id 获取所属区块key
    ---@param block_id number 连通块id
    ---@return string chunk_key 格式 "cx_cy"，
    get_block_chunk_key = function (block_id)
        if Block_data[block_id] then
            return Block_data[block_id].chunk_key
        end
        print("block_id not found")
        return "0_0"
    end,
    ---计算两个区块间的曼哈顿距离(单位:chunk)
    ---@param chunk_key1 string 区块key "cx_cy"
    ---@param chunk_key2 string 区块key "cx_cy"
    ---@return number dist 曼哈顿距离 |cx1-cx2|+|cy1-cy2|
    get_block_distant = function (chunk_key1,chunk_key2)
        local x1,y1 = chunk_key1:match("(-?%d+)_(-?%d+)")
        x1,y1 = tonumber(x1),tonumber(y1)
        local x2,y2 = chunk_key2:match("(-?%d+)_(-?%d+)")
        x2,y2 = tonumber(x2),tonumber(y2)
        return math.abs(x1-x2) + math.abs(y1-y2)
    end,
    ---获取block的邻居列表
    ---@param block_id number
    ---@return table<number, number|string> neighbors
    ---元素类型可能为 number(已连接的邻居block id) 或 string(尚未扫描的邻居chunk_key)
    get_block_neighbors = function (block_id)
        local block = Block_data[block_id]
        local neighbors = {}
        for nblock_id,_ in pairs(block.neighbors) do
            table.insert(neighbors,nblock_id)
        end
        return neighbors
    end,
    ---获取两个连通块在共享边上的交点(即两个block实际相邻的节点)
    ---用于确定跨block移动时的"门"位置
    ---@param from_node number|string 连通块1 id
    ---@param to_node number|string 连通块2 id
    ---@return table<string, boolean> edge_set 共享边节点集，key="x_y"
    get_block_edge = function (from_node,to_node)
        if type(from_node) ~= "number" then
            print("[get_block_edge] from_node type error:" .. tostring(from_node))
            return {}
        end
        local block1 = Block_data[from_node]
        
        local chunk1 = Chunk_data[block1.chunk_key]
        local edge_set = {}
        if type(to_node) == "string" then
            --说明其是区块
            local cx,cy = to_node:match("(-?%d+)_(-?%d+)")
            cx,cy = tonumber(cx),tonumber(cy)
            local dir = Direction:new(cx - chunk1.cx, cy - chunk1.cy)
            edge_set = block1:get_edge(dir)
        elseif  type(to_node) == "number" then
            --说明其是block
            local block2 = Block_data[to_node]
            local chunk2 = Chunk_data[block2.chunk_key]
            local dir = Direction:new(chunk2.cx - chunk1.cx, chunk2.cy - chunk1.cy)
            local edge_set1 = block1:get_edge(dir)
            local edge_set2 = block2:get_edge(-dir)   
            for k,_ in pairs(edge_set1) do
                --检查区块上存在，并且临近点存在
                if edge_set2[k] and check_node then
                    local x,y = k:match("(-?%d+)_(-?%d+)")
                    x,y = tonumber(x),tonumber(y)
                    x,y = x + dir.dx,y + dir.dy
                    local key = x .. "_" .. y
                    if check_node(key) then
                        edge_set[k] = true
                    end
                end
            end
        else
            print("[get_block_edge] to_node type error")
        end
        return edge_set
    end
}
return M
