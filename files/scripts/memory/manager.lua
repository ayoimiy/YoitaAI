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
local width_num = math.floor(width / node_size) + 1
local height_num = math.floor(height / node_size) + 1
local chunk_w_num = 100000


---记录区块数据
---@type table<string,Chunk>
local Chunk_data = {}
--记录所有连通分量
---@type table<number,Block>
local Block_data = {}

---取交集
---@param set1 table
---@param set2 table
---@return table inter_set,number count
local function get_inter_set(set1, set2)
    local inter_set = {}
    local count = 0 
    for k, v in pairs(set1) do
        if set2[k] ~= nil then --防止过滤值为false
            inter_set[k] = v
            count = count + 1
        end
    end
    return inter_set,count
end
local function data_class()
    local _data = {}
    _data.__index = _data
    return _data
end

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

    --#region NodeSet

---@class NodeSet
---@field nodes table<number,boolean>
---@field count number
local NodeSet = data_class()
---@return NodeSet
function NodeSet:new()
    local obj = setmetatable({
        nodes = {},
        count = 0,
    },NodeSet)
    return obj
end
function NodeSet:add(x,y,sx,sy)
    local id = NodeSet.get_id(x,y,sx,sy)
    self:add_from_id(id)
    return id
end
function NodeSet:add_from_id(id)
    self.nodes[id] = false
    self.count = self.count + 1
end
---@param id number
---@param sx number
---@param sy number
---@return number,number
function NodeSet.get_pos(id,sx,sy)
    local ix = id % width_num
    local iy = math.floor(id / width_num)
    return ix * node_size + sx, iy * node_size + sy
end
function NodeSet.get_pos2(id,chunk_id)
    local chunk = Chunk_data[chunk_id]
    local sx,sy = chunk.cx * width,chunk.cy * height
    return NodeSet.get_pos(id,sx,sy)
end

function NodeSet.get_id(x,y,sx,sy)
    local ix = math.floor((x - sx) / node_size)
    local iy = math.floor((y - sy) / node_size)
    return ix + iy * width_num
end
---@param id number
---@return boolean|nil
function NodeSet:get_state(id)
    return self.nodes[id]
end
function NodeSet:set_state(id,state)
    if self.nodes[id] ~= nil then
        self.nodes[id] = state
        return true
    else
        return false
    end
end
---@return boolean exist 是否存在该节点
function NodeSet:exist(id)
    return self.nodes[id] ~= nil
end
---@param x number
---@param y number
---@return boolean,number id 
function NodeSet:exist2(x,y,chunk_id)
    local chunk = Chunk_data[chunk_id]
    local sx,sy = chunk.cx * width, chunk.cy * height
    local id = NodeSet.get_id(x,y,sx,sy)
    return self.nodes[id] ~= nil,id
end


--曼巴顿距离
---@param id1 number
---@param id2 number
---@return number
function NodeSet.get_ditantce(id1,id2)
    local ix1 = id1 % width_num
    local iy1 = math.floor(id1 / width_num)
    local ix2 = id2 % width_num
    local iy2 = math.floor(id2 / width_num)
    return math.abs(ix1-ix2) + math.abs(iy1-iy2)
end
---获取邻居，
---@param id number
---@return number[] neighbors
function NodeSet:get_neighbors(id)
    local neighbors = {}
    local ix = id % width_num
    local iy = math.floor(id / width_num)
    for _,v in pairs(Directions) do
        local nix = ix + v.dx
        local niy = iy + v.dy
        if nix >= 0 and nix < width_num and niy >= 0 and niy < height_num then
            local nid = nix + niy * width_num
            if self.nodes[nid] ~= nil then
                table.insert(neighbors,nid)
            end
        end
    end
    return neighbors
end
---将内部 nodes 转为 {["x_y"] = boolean} 格式
---@param sx number 区块原点x
---@param sy number 区块原点y
---@return table<string,boolean>
function NodeSet:to_nodes(sx, sy)
    local out = {}
    for id, state in pairs(self.nodes) do
        local ix = id % width_num
        local iy = math.floor(id / width_num)
        out[ix * node_size + sx .. "_" .. iy * node_size + sy] = state
    end
    return out
end

function NodeSet:to_nodes2(chunk_id)
    local out = {}
    local chunk = Chunk_data[chunk_id]
    local sx,sy = chunk.cx * width, chunk.cy * height
    for id, state in pairs(self.nodes) do
        local ix = id % width_num
        local iy = math.floor(id / width_num)
        out[ix * node_size + sx .. "_" .. iy * node_size + sy] = state
    end
    return out
end


local edge = {
    {dir = Directions.BOTTOM, offset = {1 , height_num - 1, width_num - 2, height_num -1 }}, 
    {dir = Directions.RIGHT, offset = {width_num - 1, 1, width_num - 1, height_num - 2}},
    {dir = Directions.TOP, offset = {1, 0, width_num - 2, 0}},
    {dir = Directions.LEFT, offset = {0, 1, 0, height_num - 2}},
}
---@return NodeSet
function NodeSet:get_edges_nodes()
    local out = NodeSet:new()
    for i,v in ipairs(edge) do 
        local offset = v.offset
        for x = offset[1], offset[3] do
            for y = offset[2], offset[4] do
                local id = x + y * width_num
                if self:exist(id) then
                    out:add_from_id(id)
                end
            end
        end
    end
    return out
end

function NodeSet:get_inner_nodes()
    local out = NodeSet:new()
    for x = 1, width_num- 2 do
        for y = 1, height_num - 2 do
            local id = x + y * width_num
            if self:exist(id) then
                out:add_from_id(id)
            end
        end
    end
    return out
end
---@param nodes NodeSet
---@return string key
local function encode_edge_key(nodes)
    local bytes = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    local count = 0
    for i,v in ipairs(edge) do 
        local offset = v.offset
        for x = offset[1], offset[3] do
            for y = offset[2], offset[4] do
                local id = x + y * width_num
                local byte_idx = math.floor(count / 8) + 1  --1~16
                local byte_bit = count % 8    -- 0~7
                if nodes:exist(id) then
                    bytes[byte_idx] = bytes[byte_idx] + 2^byte_bit
                end
                count = count + 1
            end
        end
    end
    if count == 0 then
        return ""
    end
    return string.char(bytes[1],bytes[2],bytes[3],bytes[4],
                       bytes[5],bytes[6],bytes[7],bytes[8],
                       bytes[9],bytes[10],bytes[11],bytes[12],
                       bytes[13],bytes[14],bytes[15],bytes[16])
end
---@param key string
---@param dir? Direction 若不传则全部解码
---@return NodeSet
local function decode_edge_key(key,dir)
    local edge_nodes = NodeSet:new()
    local count = 0
    for i,v in ipairs(edge) do 
        local offset = v.offset
        for x = offset[1], offset[3] do
            for y = offset[2], offset[4] do
                if dir == nil or dir == v.dir then
                    local id = x + y * width_num
                    local byte_idx = math.floor(count / 8) + 1  --1~16
                    local byte_bit = count % 8    -- 0~7                
                    local char = string.byte(key,byte_idx)
                    if (math.floor(char / 2^byte_bit) % 2 == 1) then
                        edge_nodes:add_from_id(id)
                    end
                end
                count = count + 1
            end
        end
    end
    return edge_nodes
end
    --#endregion
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
---@param nodes NodeSet 所有符合条件的节点集合
---@param edge_set NodeSet 边节点集合
---@param start_node number 开始点id
---@param sx number 区块原点x
---@param sy number 区块原点y
---@return NodeSet comp 连通点集
local function bfs(nodes,edge_set,start_node,sx,sy)
    local Component = NodeSet:new()
    -- 创建队列
    local queue = {}
    -- 从起点出发
    table.insert(queue,start_node)

    nodes:set_state(start_node, true)
    Component:add_from_id(start_node)
    while #queue > 0 do
        --取出一个节点
        local node = table.remove(queue,1)
        local neighbors = nodes:get_neighbors(node)
        local x,y = NodeSet.get_pos(node,sx,sy)
        --寻找邻居节点
        for k,n_node in pairs(neighbors) do
            local nx,ny = NodeSet.get_pos(n_node,sx,sy) 
            if nodes:get_state(n_node) == false  and raytrace5({x=x,y=y},{x=nx,y=ny}) then
                --检查是不是两个都是边界点
                if not (edge_set:exist(node) and edge_set:exist(n_node)) then
                    table.insert(queue,n_node)
                    nodes:set_state(n_node,true)
                    Component:add_from_id(n_node)
                end
            end
        end
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


---将区块内的点转化为节点集
---@return NodeSet nodes
function Chunk:to_nodes()
    local sx = self.cx * width
    local sy = self.cy * height
    local nodes = NodeSet:new()
    for y = sy,sy + height,node_size do 
        for x = sx,sx + width,node_size do
            local node_key = x .. "_" .. y
            if check_node(node_key) then
                nodes:add(x,y,sx,sy)
            end
        end
    end
    return nodes
end
---将区块切分成内部连通的点集
---@return NodeSet[] comps
function Chunk:get_nodes()
    local comps = {}
    local sx,sy = self.cx * width,self.cy * height
    local nodes = self:to_nodes()
    local edge_set = nodes:get_edges_nodes()
    local inner_set = nodes:get_inner_nodes()
    for node_id in pairs(inner_set.nodes) do
        if nodes:get_state(node_id) == false then
            local comp = bfs(nodes,edge_set,node_id,sx,sy)
            if comp.count > 1 then
                table.insert(comps,comp)
            end
        end 
    end
    return comps
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

                local nedge_set =  decode_edge_key(nblock.hash_key,-dir)
                local edge_set = decode_edge_key(block.hash_key,dir)

                local inter_set,count = get_inter_set(nedge_set:to_nodes(cx * width,cy * height),edge_set:to_nodes(chunk.cx * width,chunk.cy * height))
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
        else    
            local edge_set = decode_edge_key(block.hash_key,dir)
            
            if edge_set.count > 0 then 
                    --检查边界点是否可以进入该区块
                local count = 0

                local nodes_set = edge_set:to_nodes(chunk.cx,chunk.cy)
                for node_key in pairs(nodes_set) do 
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
    end
    return block
end


---@param chunk_key string 区间key
---@return  table<number,NodeSet> blocks_nodes,boolean is_change
local function floor_fill(chunk_key)
    --获取区块
    local chunk = Chunk_data[chunk_key]
    if chunk == nil then
        local cx,cy = chunk_key:match("(-?%d+)_(-?%d+)")
        chunk = Chunk:new(cx,cy)
        Chunk_data[chunk_key] = chunk
    end

    local is_change = false
    local comps = chunk:get_nodes()
    --记录新连通点集的边指纹
    local comps_fps = {}
    for i, comp in ipairs(comps) do 
        comps_fps[i] = encode_edge_key(comp)
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
        print("not found,block_id:" .. tostring(block_id))
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
            edge_set = decode_edge_key(block1.hash_key,dir):to_nodes(chunk1.cx * width,chunk1.cy * height)
        elseif  type(to_node) == "number" then
            --说明其是block
            local block2 = Block_data[to_node]
            local chunk2 = Chunk_data[block2.chunk_key]
            local dir = Direction:new(chunk2.cx - chunk1.cx, chunk2.cy - chunk1.cy)

            local edge_set1 = decode_edge_key(block1.hash_key,dir):to_nodes(chunk1.cx * width,chunk1.cy * height)
            local edge_set2 = decode_edge_key(block2.hash_key,-dir):to_nodes(chunk2.cx * width,chunk2.cy * height)
            local inter_set = get_inter_set(edge_set1,edge_set2)
            for k in pairs(inter_set) do
                local x,y = k:match("(-?%d+)_(-?%d+)")
                x,y = tonumber(x),tonumber(y)
                x,y = x + dir.dx,y + dir.dy
                local key = x .. "_" .. y
                if check_node(key) then
                    edge_set[k] = true
                end
            end
        else
            print("[get_block_edge] to_node type error")
        end
        return edge_set
    end
}
return M
