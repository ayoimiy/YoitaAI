--[[
    存储与ai计算移动有关的函数

]]
-- 引入通用工具库
dofile_once("data/scripts/lib/utilities.lua")

local M = {
}

local W = 200
--[[
处理点映射
]]
-- 将二维点映射到一维
---@param x number
---@param y number
---@param x_num number
function M.get_point_idx(x,y,x_num)
    return x + y * W + 1
end
--- 寻找邻居
---@param idx number
---@param x_num number
---@param t table 按idx存储节点的表
---@return table 存储节点的数组
function M.get_neighbors(idx,x_num,t)
    local nei_idx ={-1,1,W,-W,W+1,W-1,-W+1,-W-1}
    local neighbors = {}
    for _,dx in ipairs(nei_idx) do 
        if (t[idx+dx]) then
            table.insert(neighbors,idx+dx)
        end
    end
    return neighbors
end

--- 作用是将寻找当前坐标最近的网格点，取该网格点作为起始点
---@param i number 坐标
---@param v number 节点距离
function M.nearest(i, v)
    return math.floor(i / v) * v
end

--- 需要最近的网格点作为代替
--- 通过遍历查找所有的坐标点，计算距离，然后更新最近点
---@param x number 
---@param y number
---@param t table 可用网格点
---@return number|nil  最近元素的序号，为-1表示没找到
function M.findClosest(x, y, t)
	local closest = 99999
	local closest_item = -1
	for k, v in pairs(t) do
        if type(v.x) == "number" and type(v.y) == "number" then 
			local distance = M.get_distance2(x, y, v.x, v.y)
			if (distance < closest) then				
					closest_item = k 
					closest = distance		
			end
		end
	end
	return closest_item
end




---距离算法
function M.get_distance(x1, y1, x2, y2)
	return  math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 )
    
end

function M.get_distance2(x1, y1, x2, y2)
	return  (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
end



return M