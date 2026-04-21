local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
local gui = GuiCreate()
local M = dofile_once(base_file .. "files/utils/entity.lua")
local SM = dofile_once(base_file .. "files/state_manager.lua")
local targetX,targetY
local Player 
local target = true
local path = nil
local path_true = nil
local node_grid = nil
local current_index = 1
local last_time_current_index_changed = 0
local frame_counter = 0

dofile_once(base_file .. "files/scripts/movements/ai_movement_utilities.lua")
function OnPlayerSpawned(entity)
    Player = M.Player:new(entity)
    local init_ok = SM.init(entity)
    if init_ok then
        GamePrint("[Init] 状态管理器初始化成功!")
    else
        GamePrint("[Init] 状态管理器初始化失败!")
    end
end

 


-- 计算两点之间的平方距离（用于距离比较，避免开方运算提高性能）
local function get_square_distance(x1, y1, x2, y2)
	local squared_distance = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
	return squared_distance
end
local function node_func(n, neigh, goal, density)
    local d = 5
    local dist = get_square_distance(n.x, n.y, neigh.x, neigh.y)
    -- 检查邻居距离是否超过密度阈值
    if dist > density * density then return false end
    -- 非目标节点需要检查与周围平台的碰撞
    if neigh ~= goal then
        for dx = -d, d, d do
            for dy = -d, d, d do
                if RaytracePlatforms(neigh.x, neigh.y, neigh.x + dx, neigh.y + dy) then return false end
            end
        end
    end
    -- 确保当前节点到邻居节点路径无障碍
    return not RaytracePlatforms(neigh.x, neigh.y, n.x, n.y)
end
-- function OnWorldPreUpdate()   
--     frame_counter = frame_counter + 1
--     GuiStartFrame(gui)
--     if gui == nil then
--         gui = GuiCreate()
--     end
--     if Player then
--         local controls = Player:control_comp()
--         -- controls.mButtonDownLeft  = true
--         ComponentSetValue2(controls:get_id(),"mButtonDownLeft",true)
--         GamePrint(tostring(controls.mButtonDownLeft))
--     end

--     if true then
--         return
--     end
--     if Player then
--         local mx,my = Player:get_mouse_pos()
--         local x,y = Player:get_pos()
        
--         -- 显示目标点标记
--         if targetX and targetY then
--             GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", targetX, targetY, true, 0, 0, 2, true )
--         end
        
--         local lukki = false
--         local mx_screen,my_screen  = Player:get_mouse_pos_in_screen(gui)
        
--         -- 每60帧（约1秒）输出一次玩家状态
--         if frame_counter % 60 == 0 then
--             GamePrint("[Frame " .. frame_counter .. "] 玩家位置: " .. math.floor(x) .. ", " .. math.floor(y))
--             GamePrint("[Frame " .. frame_counter .. "] 鼠标位置: " .. math.floor(mx) .. ", " .. math.floor(my))
--             GamePrint("[Frame " .. frame_counter .. "] 路径状态: " .. (path and "有路径" or "无路径"))
--             if path then
--                 GamePrint("[Frame " .. frame_counter .. "] 路径节点: " .. #path .. " | 当前索引: " .. current_index)
--             end
--             if targetX and targetY then
--                 GamePrint("[Frame " .. frame_counter .. "] 目标位置: " .. math.floor(targetX) .. ", " .. math.floor(targetY))
--             end
--         end
        
--         if GuiButton(gui,1145,mx_screen,my_screen,"    ") then
--             -- 设置目标坐标
--             targetX,targetY = mx,my
--             GamePrint("[点击] 设置目标点: " .. math.floor(targetX) .. ", " .. math.floor(targetY))
--             GamePrint("[点击] 玩家位置: " .. math.floor(x) .. ", " .. math.floor(y))
            
--             -- 查找路径
--             -- 如果位置和目标都有效，执行路径查找
--             if x and y and targetX and targetY then
--                 GamePrint("[点击] 开始寻路...")
--                 path_true, node_grid = FindPath(x, y, targetX, targetY, false, node_func)
--                 path = path_true
--                 current_index = 1  -- 当前路径点索引
                
--                 if path_true then
--                     GamePrint("[点击] 寻路成功! 路径节点数: " .. #path_true)
--                     GamePrint("[点击] 节点网格大小: " .. (node_grid and #node_grid or 0))
--                 else
--                     GamePrint("[点击] 寻路失败! 未找到路径")
--                 end
--             else
--                 GamePrint("[点击] 坐标无效，无法寻路")
--             end
--         else
--             -- 实际移动
--             local controls = Player:control_comp()
--             -- EntitySetComponentIsEnabled(Player:get_id(),controls:get_id(),false)
--             if path and target then
--                 if current_index > #path then
--                     GamePrint("[移动] 路径走完!")
--                     path = nil
--                 else
--                     local point = path[current_index]
--                     local dx, dy = point.x - x, point.y - y

--                     if controls then
--                         local jetpack_enabled = false
--                         local target_left = point.x < x      -- 目标在左边
--                         local target_above = point.y < y - 3 -- 目标在上方（留3像素容差）

--                         -- 设置左右移动按键
--                         controls.mButtonDownRight = not target_left
--                         controls.mButtonDownLeft  = target_left

--                         -- 处理垂直移动
--                         if target_above then
--                                 -- 普通实体使用喷气背包上升
--                             EntitySetComponentsWithTagEnabled(Player:get_id(), "jetpack", true)
--                         elseif lukki then
--                             -- Lukki实体向下移动
--                             controls.mButtonDownUp = false
--                             controls.mButtonDownDown = true
--                             EntitySetComponentsWithTagEnabled(Player:get_id(), "jetpack", false)
--                         else
--                             -- 关闭喷气背包
--                             EntitySetComponentsWithTagEnabled(Player:get_id(), "jetpack", false)
--                         end

--                         -- 检测是否在水中，设置下蹲按键
--                         local in_water = RaytraceSurfacesAndLiquiform(x, y, x, y)
--                         controls.mButtonDownDown = in_water and not RaytraceSurfaces(x, y, x, y)
--                     end

--                     -- 检查是否到达当前路径点（容差范围25像素）
--                     local disti = get_square_distance(x, y - 3, point.x, point.y)
--                     if disti < 25 then
--                         GamePrint("[移动] 到达节点 " .. current_index .. ": " .. math.floor(point.x) .. ", " .. math.floor(point.y))
--                         current_index = current_index + 1
--                         last_time_current_index_changed = GameGetFrameNum()
--                     end
                    
--                     -- 每10帧输出一次移动状态
--                     if frame_counter % 10 == 0 then
--                         GamePrint("[移动] 目标节点 " .. current_index .. "/" .. #path .. ": " .. math.floor(point.x) .. ", " .. math.floor(point.y))
--                         GamePrint("[移动] 距离: " .. math.floor(math.sqrt(disti)) .. " 像素")
--                     end
--                 end
--             elseif not path then
--                 -- 没有有效路径时切换到基础移动系统
--             end
--         end 
--     end


--     if GuiButton(gui,11,150,200,"开始寻路？") then
--     end
-- end

function OnWorldPostUpdate()
    if Player and SM.is_initialized() then
        -- 持续向左移动
        SM.update_controls(true, false, false, false)
        SM.apply_controls()
    end
end



