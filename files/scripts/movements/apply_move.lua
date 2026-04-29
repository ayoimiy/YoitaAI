
-- local mod_name = "YoitaAI"
-- local base_file = "mods/" .. mod_name .. "/"
-- local M = dofile_once(base_file .. "files/utils/entity-lib.lua")

-- local function get_square_distance(x1,x2,y1,y2)
--     return (x1-x2)*(x1-x2) + (y1-y2)*(y1-y2)
-- end


-- ---@class Move_Apply
-- ---@field Player Player|nil 
-- ---@field target table|nil  目标点
-- ---@field last_target table|nil  上一次目标点
-- ---@field current_index number|nil  当前索引
-- ---@field last_time_current_index_changed number|nil 上一次索引改变的时间
-- ---@field max_dist number|nil 最大距离


-- ---@param config Move_Apply
-- function  Apply_Move(config,logger)
--     local Player = config.Player
--     local target = config.target
--     -- local last_target = config.last_target
--     -- local current_index = config.current_index
--     -- local last_time_current_index_changed = config.last_time_current_index_changed
--     local max_dist = config.max_dist
--     -- 运用了
--     local controls = Player:controls_comp()
--     local x,y = Player:get_pos()
--     local target_left = target.x < x      -- 目标在左边
--     local target_above = target.y < y - 5 -- 目标在上方（留3像素容差
--     if controls then
--         -- 设置左右移动按键
--         controls.mButtonDownRight = not target_left
--         controls.mButtonDownLeft  = target_left
--         -- 上下移动
--         if target_above then                            
--             controls.mButtonDownFly = true
--             controls.mButtonDownDown = false
--             controls.mFlyingTargetY = y -100
--             GamePrint("上下移动？")
--         else
--             -- 关闭喷气背包
--             controls.mButtonDownFly = false
--             controls.mButtonDownDown = true
--         end
--         -- 检测是否在水中，设置下蹲按键
--         local in_water = RaytraceSurfacesAndLiquiform(x, y, x, y)
--         controls.mButtonDownDown = in_water and not RaytraceSurfaces(x, y, x, y)                    
--     end
--     -- 检查是否到目标点
--     local disti = get_square_distance(x, y - 4, target.x, target.y)
--     if disti < max_dist then
--         logger:info("[移动] 到达节点 " .. current_index .. ": " .. math.floor(point.x) .. ", " .. math.floor(point.y))
--         config.current_index = config.current_index + 1
--         config.last_time_current_index_changed = GameGetFrameNum()
--         config.last_target = target
--     end         
-- end



---@param Player_move Player
---path w
---current_index r/w
---last_time_current_index_changed r/w
---gui 

