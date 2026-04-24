local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
local gui = GuiCreate()
local M = dofile_once(base_file .. "files/utils/entity.lua")

local targetX,targetY
local Player 
local target = true
local path = nil
local path_true = nil
local node_grid = nil
local current_index = 1
local last_time_current_index_changed = 0
local frame_counter = 0

-- 日志系统
local Logger = dofile_once(base_file .. "files/scripts/Log/log.lua")
local logger = Logger:new({
    global_level = Logger.Level.INFO,
    log_to_file = true,
    log_files = base_file,
    current_pos = "Init",
})
logger:start()

dofile_once(base_file .. "files/scripts/movements/ai_movement_utilities.lua")
function OnPlayerSpawned(entity)
    Player = M.Player:new(entity)
    local comp = Player:control_comp()
    comp.enabled = false
end
function world_2_ui_pos(x,y)
    local _, _, cw, ch = GameGetCameraBounds()
    local cx, cy = GameGetCameraPos()
    cw = cw - 4
    local cx = cx-cw/2
    local cy = cy-ch/2
    local  gw, gh = GuiGetScreenDimensions(gui)
    return (x-cx)*gw/cw+1.0, (y-cy)*gh/ch -5
end
function ui_2_world(x,y)
    local _, _, cw, ch = GameGetCameraBounds()
    local cx, cy = GameGetCameraPos()
    cw = cw - 4
    local cx = cx-cw/2
    local cy = cy-ch/2
    local  gw, gh = GuiGetScreenDimensions(gui)

    return (x-1.0)*cw/gw+cx, (y+5)*ch/gh+cy 
end
local last_vx  = 0 
local last_vy = 0 
-- 计算两点之间的平方距离（用于距离比较，避免开方运算提高性能）
local function get_square_distance(x1, y1, x2, y2)
	local squared_distance = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
	return squared_distance
end
-- 平台碰撞
local function node_func(n, neigh, goal, density)
    -- -- 非目标节点需要检查与周围平台的碰撞
    -- if neigh ~= goal then
    --     for dx = -d, d, d do
    --         for dy = -d, d, d do
    --             if RaytracePlatforms(neigh.x, neigh.y, neigh.x + dx, neigh.y + dy) then return false end
    --         end
    --     end
    -- end
    -- 确保当前节点到邻居节点路径无障碍
    -- logger:debug("是否是存在障碍？")
    return not RaytracePlatforms(neigh.x, neigh.y, n.x, n.y)
end
local max_dist = 75
local g_start,g_end 
local a = 0
local tick  =0
function OnWorldPreUpdate()   
    frame_counter = frame_counter + 1
    GuiStartFrame(gui)
    if gui == nil then
        gui = GuiCreate()
    end
    if Player and Player:is_living() then
        local mx,my = Player:get_mouse_pos()
        local x,y = Player:get_pos()
        -- 米娜速度和加速度显示
        local velocity_comp = Player:get_comp("VelocityComponent")
        local vx,vy = ComponentGetValue2(velocity_comp:get_id(),"mVelocity")
        logger:debug(string.format("速度:%.2f,%.2f,",vx,vy))
        logger:debug(string.format("加速度:%.2f,%.2f,",vx-last_vx,vy-last_vy ))
        last_vx = vx 
        last_vy = vy 
        -- 显示目标点标记
        if targetX and targetY then
            
        end
        
        local lukki = false
        local mx_screen,my_screen  = Player:get_mouse_pos_in_screen(gui)
        
        -- 每60帧（约1秒）输出一次玩家状态
        if frame_counter % 60 == 0 then
            GamePrint("[Frame " .. frame_counter .. "] 玩家位置: " .. math.floor(x) .. ", " .. math.floor(y))
            GamePrint("[Frame " .. frame_counter .. "] 鼠标位置: " .. math.floor(mx) .. ", " .. math.floor(my))
            GamePrint("[Frame " .. frame_counter .. "] 路径状态: " .. (path and "有路径" or "无路径"))
            if path then
                GamePrint("[Frame " .. frame_counter .. "] 路径节点: " .. #path .. " | 当前索引: " .. current_index)
            end
            if targetX and targetY then
                GamePrint("[Frame " .. frame_counter .. "] 目标位置: " .. math.floor(targetX) .. ", " .. math.floor(targetY))
            end
        end
        
        if a==0 then 
             for i,v in ipairs(path_true or {}) do
                GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
                -- local vx,vy = world_2_ui_pos(v.x,v.y)
                -- GuiText(gui,vx,vy,string.format("序号:%.0f(%.0f,%.0f)",i,v.x,v.y))
            end
        elseif a== 1 then 
            if g_start and g_end then
                for i,v in ipairs({g_start,g_end} or {}) do
                    GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
                    -- local vx,vy = world_2_ui_pos(v.x,v.y)
                    -- GuiText(gui,vx,vy,string.format("序号:%.0f(%.0f,%.0f)",i,v.x,v.y))
                end
            end
        elseif a == 2 then
            for k,v in pairs(node_grid or {}) do
                GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
                -- local vx,vy = world_2_ui_pos(v.x,v.y)
                -- GuiText(gui,vx,vy,string.format("序号:%.0f(%.0f,%.0f)",i,v.x,v.y))              
            end
        end
       
        if  InputIsKeyJustDown(13) then
            a = (a+1) %3
        end
        if GuiButton(gui,1145,mx_screen,my_screen,"aa    ") then
            -- 设置目标坐标
            targetX,targetY = mx,my
            logger:info("[点击] 设置目标点: " .. math.floor(targetX) .. ", " .. math.floor(targetY))
            logger:info("[点击] 玩家位置: " .. math.floor(x) .. ", " .. math.floor(y))  
            -- 查找路径
            -- 如果位置和目标都有效，执行路径查找
            if x and y and targetX and targetY then
                logger:info("[点击] 开始寻路...")
                -- path_true, node_grid = FindPath(x, y, targetX, targetY, false, node_func)
                
                path_true, node_grid,g_start,g_end =logger:func(FindPath,
                    {x, y, targetX, targetY, false, node_func,nil,logger}
                    ,{
                        current_fore = logger.current_fore + 1,
                        current_pos =  "FindPath",                               
                })   
                path = path_true
                current_index = 1  -- 当前路径点索引
                
                if path_true then
                    logger:info("[点击] 寻路成功! 路径节点数: " .. #path_true)
                    logger:info("[点击] 节点网格大小: " .. (node_grid and #node_grid or 0))
                    last_time_current_index_changed = GameGetFrameNum()

                else
                    logger:warn("[点击] 寻路失败! 未找到路径")
                end
            else
                logger:warn("[点击] 坐标无效，无法寻路")
            end
            logger:save("w")
        else
            
            -- if true then 
            --     return
            -- end

            -- 实际移动
            local controls = Player:control_comp()
            -- EntitySetComponentIsEnabled(Player:get_id(),controls:get_id(),false)
            if path and target then
                if current_index > #path then
                    logger:info("已经完成路径")
                    path = nil
                else
                    local point = path[current_index]
                    local dx, dy = point.x - x, point.y - y
                    GuiText(gui,150,200,"当前坐标" .. string.format("%.0f|%.0f",x,y) )
                    GuiText(gui,150,220,"目标坐标" .. string.format("%.0f|%.0f",point.x,point.y) )
                    GuiText(gui,150,240,"最终坐标" .. string.format("%.0f|%.0f",targetX,targetY) )
                
                    if controls then
                        local jetpack_enabled = false
                        local target_left = point.x < x      -- 目标在左边
                        local target_above = point.y < y - 5 -- 目标在上方（留3像素容差）
                        -- 设置左右移动按键
                        controls.mButtonDownRight = not target_left
                        controls.mButtonDownLeft  = target_left

                        -- 处理垂直移动
                        if target_above then
                            
                            controls.mButtonDownFly = true
                            controls.mButtonDownDown = false
                            controls.mFlyingTargetY = y - 100 
                            -- EntitySetComponentsWithTagEnabled(Player:get_id(), "jetpack", true)
                        else
                            -- 关闭喷气背包
                            -- EntitySetComponentsWithTagEnabled(Player:get_id(), "jetpack", false)
                            controls.mButtonDownFly = false
                            controls.mButtonDownDown = true
                        end

                        -- 检测是否在水中，设置下蹲按键
                        local in_water = RaytraceSurfacesAndLiquiform(x, y, x, y)
                        controls.mButtonDownDown = in_water and not RaytraceSurfaces(x, y, x, y)
                    end

                    -- 检查是否长时间停留在固定点
                    if GameGetFrameNum() - last_time_current_index_changed > 100  then
                        if   tick ==0  then
                            logger:info("[点击] 设置目标点: " .. math.floor(targetX) .. ", " .. math.floor(targetY))
                            logger:info("[点击] 玩家位置: " .. math.floor(x) .. ", " .. math.floor(y))  
                            -- 查找路径
                            -- 如果位置和目标都有效，执行路径查找
                            if x and y and targetX and targetY then
                                logger:info("[点击] 开始寻路...")
                                -- path_true, node_grid = FindPath(x, y, targetX, targetY, false, node_func)
                                
                                path_true, node_grid,g_start,g_end =logger:func(FindPath,
                                    {x, y, targetX, targetY, false, node_func,nil,logger}
                                    ,{
                                        current_fore = logger.current_fore + 1,
                                        current_pos =  "FindPath",                               
                                })   
                                path = path_true
                                current_index = 1  -- 当前路径点索引
                                
                                if path_true then
                                    logger:info("[点击] 寻路成功! 路径节点数: " .. #path_true)
                                    logger:info("[点击] 节点网格大小: " .. (node_grid and #node_grid or 0))
                                    last_time_current_index_changed = GameGetFrameNum()

                                else
                                    logger:warn("[点击] 寻路失败! 未找到路径")
                                end
                            else
                                logger:warn("[点击] 坐标无效，无法寻路")
                            end
                            tick = 100
                            
                        else
                            tick = tick -1 
                        end
                    else
                        -- max_dist = 75 
                    end
                    -- 检查是否到达当前路径点（容差范围5像素）
                    local disti = get_square_distance(x, y - 4, point.x, point.y)
                    if disti < max_dist then
                        logger:info("[移动] 到达节点 " .. current_index .. ": " .. math.floor(point.x) .. ", " .. math.floor(point.y))
                        current_index = current_index + 1
                        last_time_current_index_changed = GameGetFrameNum()
                    end                            
                    -- 每10帧输出一次移动状态
                    if frame_counter % 10 == 0 then
                        logger:info("[移动] 目标节点 " .. current_index .. "/" .. #path .. ": " .. math.floor(point.x) .. ", " .. math.floor(point.y))
                        logger:info("[移动] 距离: " .. math.floor(math.sqrt(disti)) .. " 像素")             
                    end
                end
            elseif not path then
                -- 没有有效路径时切换到基础移动系统
                controls.mButtonDownDown = false
                controls.mButtonDownFly = false
                controls.mButtonDownRight = false
                controls.mButtonDownLeft  = false
            end
        end 
    end
    if GuiButton(gui,11,150,110,"保存日志") then
        
    end
end

function OnWorldPostUpdate()
 
end



