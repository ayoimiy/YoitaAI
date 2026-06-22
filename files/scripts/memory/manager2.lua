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

---记录区块数据
Chunk_data = {}
--记录所有连通分量
Block_data = {}

--#region 函数

--剔除只有一个节点的连通分量


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
local function bfs(nodes,start_node,node_size)
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
---@field hash_key string 区块hash值，用于检测是否发生的变化
---@field cx number 区块x
---@field cy number 区块y
---@field blocks Block[] 连通块列表
Chunk = class()
--Chunk的静态变量定义
Chunk.width = 256
Chunk.height = 256
Chunk.node_size = 8
function Chunk:init() 
    self.hash_key = ""
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
    local end_x = start_x + Chunk.width
    local end_y = start_y + Chunk.height
    if ny == start_y and nx >= start_x and nx <= end_x then
        return (nx - start_x) / Chunk.node_size               --顶边 0..32
    elseif nx == end_x and ny >= start_y and ny <= end_y then
        return 32 + (ny - start_y) / Chunk.node_size           --右边 33..64
    elseif ny == end_y and nx >= start_x and nx <= end_x then
        return 64 + (end_x - nx) / Chunk.node_size             --底边 65..96
    elseif nx == start_x and ny >= start_y and ny <= end_y then
        return 96 + (end_y - ny) / Chunk.node_size             --左边 97..127
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
local function bit_to_node()
    
end
local function mask_to_edge_set()
    
end

---获取区块pos
---@param x number
---@param y number
---@return number cx, number cy
function Chunk.get_pos(x,y)
    local cx = math.floor(x/Chunk.width)
    local cy = math.floor(y/Chunk.height)
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
function Chunk:get_edge_nodes()
    local nodes = {
        left = {},
        right = {},
        top = {},
        bottom = {}
    }
    return nodes
end
---将区块内的点转化为节点集
function Chunk:to_nodes()
    local sx = self.cx * self.width
    local sy = self.cy * self.height
    local nodes = {}
    for y = sy,sy + self.height,self.node_size do 
        for x = sx,sx + self.width,self.node_size do
            if not RaytracePlatforms(x,y,x+1,y) then
                nodes[tostring(x).."_"..tostring(y)] = true
            end
        end
    end
    return nodes
end
---将区块切分成内部连通的点集
function Chunk:get_nodes()
    local comps = {}
    local nodes = self:to_nodes()
    local sx,sy = self.cx * self.width,self.cy * self.height
    for y = sy,sy + self.height,self.node_size do 
        for x = sx,sx + self.width,self.node_size do
            if nodes[ tostring(x).."_"..tostring(y)] == false then
               local comp = bfs(nodes,{x = x,y = y},self.node_size)
               if comp ~= nil then
                    table.insert(comps,comp)
               end
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
---@field neighbors number[] 邻居id集合
local Block = class()
---@param chunk_key string 所属区块
---@param hash_key string 哈希掩码
function Block:init(hash_key,chunk_key)
    self.hash_key = hash_key or ""
    self.chunk_key = chunk_key
    self.id = Get_Block_id()
end

--获取边集
---@param edge_set table 区块的边节点集
---@param nodes table 尚未分配的节点集
---@return string key 边节点mask
function Block.get_edge_nodes(edge_set,nodes,cx,cy)
    local edge_nodes = {}
    for node,_ in pairs(nodes) do 
        for _,edge in pairs({"left","right","top","bottom"}) do 
            if edge_set[edge][node] then
                --若节点在边集内
                edge_nodes[node] = true
            end
        end
    end
    local key = edge_set_to_mask(edge_nodes,cx * Chunk.width, cy * Chunk.height)
    return key
end

--#endregion

--#region 实际运行
---@param chunk Chunk
function Floor_fill(chunk)
    local comps = chunk:get_nodes()
    local edge_set = chunk:get_edge_nodes()
    --记录新连通点集的边指纹
    local comps_fps = {}
    for i, comp in ipairs(comps) do 
        comps_fps[i] = Block.get_edge_nodes(edge_set, comp,chunk.cx,chunk.cy)
    end
    --获取旧连通块
    local blocks = chunk.blocks
    --匹配
    local matched = {}     -- temp_idx -> old_comp_id
    local used_old = {}

    for i,fp in ipairs(comps_fps) do 
        for j,block in ipairs(blocks) do 
            local old_fp = block.hash_key
            if not used_old[j] and fp == old_fp then 
                matched[i] = j
                used_old[j] = true
                break
            end
        end
    end

    --检查匹配结果
    --清理未匹配的旧block: 从Block_data中移除
    for j,block in ipairs(blocks) do
        if not used_old[j] then
            Block_data[block.id] = nil
        end
    end

    --创建新block: 未匹配到旧block的新连通分量
    local new_blocks = {}
    local chunk_key = tostring(chunk.cx).."_"..tostring(chunk.cy)

    for i,_ in ipairs(comps) do
        local block
        if matched[i] then
            --匹配上的保留旧block
            block = blocks[matched[i]]
        else
            --未匹配上的创建新block
            block = Block:new(comps_fps[i], chunk_key)
            Block_data[block.id] = block
        end
        new_blocks[i] = block
    end

    chunk.blocks = new_blocks
end



