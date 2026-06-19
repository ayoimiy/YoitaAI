local Move = {}
Move.__index = Move

--[[
使用:
local move = dofile_once("move.lua")
-- 设置路径
move:get_path(path)
--具体移动
move:start(entity)
]]

function Move:new()
    local obj ={
        path = nil,
        finding = false,   
        current_index = 1,
        last_time_current_index_changed = 0,
        max_dist = 75 
    }
    setmetatable(obj, self)
    return obj
end
---@param path table {x,y}  -- 输入路径，会自动进行寻路配置
function Move:get_path(path)
    if path == nil then
        error("path is nil")
    end
    self.path = path
    self.finding = true
    self.current_index = 1
    self.last_time_current_index_changed = GameGetFrameNum()    
end
---@param entity Entity
function Move:start(entity)
    local x,y = entity:get_pos()
    if not (x and y) then 
        error("entity has no pos")
    end

    if self.finding then
        if #self.path == 0 then
            self.finding = false
        end
        if self.current_index > #self.path then
            self.finding = false
            return
        end
        local target = self.path[self.current_index]
        if target == nil then
            self.finding = false
            error("can't find target")
            return
        end
        self:Move(entity,target)
        local dist =   (x-target.x)^2 + (y-4-target.y)^2
        if dist < self.max_dist then
            self.current_index = self.current_index + 1
            self.last_time_current_index_changed = GameGetFrameNum()
        end
    else
        self:Move_no_path(entity)
    end
   
end

function Move:Move_no_path(player)
    local controls = player:controls_comp()
    controls.mButtonDownDown = false
    controls.mButtonDownFly = false
    controls.mButtonDownRight = false
    controls.mButtonDownLeft  = false
end
function Move:Move(player,target)   
    local controls = player:controls_comp()
    local x,y = player:get_pos()
    if controls then
        local target_left = target.x < x      -- 目标在左边
        local target_above = target.y < y - 5 -- 目标在上方（留3像素容差）
        -- 设置左右移动按键
        controls.mButtonDownRight = not target_left
        controls.mButtonDownLeft  = target_left
        -- 处理垂直移动
        if target_above then                    
            controls.mButtonDownFly = true
            controls.mButtonDownDown = false
            controls.mFlyingTargetY = y - 100             
        else
            -- 关闭喷气背包
            controls.mButtonDownFly = false
            controls.mButtonDownDown = true
        end
        -- 检测是否在水中，设置下蹲按键
        local in_water = RaytraceSurfacesAndLiquiform(x, y, x, y)
        controls.mButtonDownDown = in_water and not RaytraceSurfaces(x, y, x, y)
    end
end
function Move:get_current_idx()
    return self.current_index
end



return Move:new()