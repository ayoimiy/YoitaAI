local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local now_file = base_file .. "files/scripts/movements/"
local gui = GuiCreate()
local M = dofile_once(base_file .. "files/utils/entity-lib.lua")

local Player

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
    local comp = Player:controls_comp()
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

--引入kick
local kick  = dofile_once(base_file .. "files/scripts/action/kick.lua" )    
local sTout = dofile_once(base_file ..  "files/scripts/utils/SetTimeOut.lua")

--[[
显示逻辑
 - 速度模块，需要读取米娜的当前速度和上一帧速度
  -  60f/s,输出一次玩家状态
  - 路径显示模块 获取path，在地图上实时显示当前路径节点
  
  - 寻路模块
  - 具体移动模块
]]
---@class find_path 
---@field target table{x,y}
---@field path  table|nil
---@field path_true table|nil
---@field node_grid table
---@field current_index number
---@field last_time_current_index_changed number
---@field max_dist number
local find_path={
    target = {
        x = nil,
        y = nil ,
    },
    path = nil,
    path_true = nil,
    nodes_finded = {},
    current_index = 1,
    last_time_current_index_changed = 0,
    max_dist = 75 
}
local frame_counter = 0
local kick_time = 0 
function OnWorldPreUpdate() 
    
    sTout:Loop()

    frame_counter = frame_counter + 1
    GuiStartFrame(gui)
    if gui == nil then
        gui = GuiCreate()
    end
    GuiText(gui,100,200,"表地址" .. tostring(kick))

    local _kick  = dofile_once(base_file .. "files/scripts/action/kick.lua" )    
    -- GamePrint("表地址：" .. tostring(_kick))

--    if Player and Player:is_living() then
--         kick:run_per_frame(Player)
--         if frame_counter %120 == 0  then            
--             kick:kick()
--         end
--     end
    local dy = 10 
    if not Player or not Player:is_living() then return nil end 
    local controls = Player:controls_comp()
   
    -- 按p设置
    if InputIsKeyJustDown(19) then
        controls.enabled = not controls.enabled 
    end
    if InputIsKeyJustDown(18) then
        -- controls.mButtonDownLeftClick = true
        Kick_book(Player,sTout)

       
 
        
    end
    -- 显示某个值
    -- GuiText(gui,100,220, "左键点击"  ..  tostring(controls.mButtonDownLeftClick))
    GuiText(gui,100,220, "左键点击"  ..  tostring(controls.mButtonDownThrow))
    GuiText(gui,100,240, "左键点击"  ..  tostring(controls.mButtonFrameThrow))

    -- 记录踢板时间
    if controls.mButtonDownKick == true then
        kick_time = GameGetFrameNum()
    end
    if kick_time~=0 and controls.mButtonDownThrow == true then
        GamePrint("踢击时间" .. tostring(GameGetFrameNum() - kick_time))
        kick_time = 0 
    end




    if true then return end 
    
    if Player and Player:is_living() then
        Log_Speed(Player,logger)
        
        local mx_screen,my_screen  = Player:get_mouse_pos_in_screen(gui)
        local mx,my = Player:get_mouse_pos()
        local x,y = Player:get_pos()
     
        local tx =  find_path.path and #find_path.path>0 and find_path.path[#find_path.path].x 
        local ty = find_path.path and #find_path.path>0 and find_path.path[#find_path.path].y
  
        Display_path(find_path.path,{x=x,y=y},{x=tx,y=ty},find_path.nodes_finded)
        if GuiButton(gui,1145,mx_screen,my_screen,"aa    ") then
            logger:info("[点击] 设置目标点: " .. math.floor(mx) .. ", " .. math.floor(my))
            logger:info("[点击] 玩家位置: " .. math.floor(x) .. ", " .. math.floor(y))  
            find_path.target.x = mx
            find_path.target.y = my
            Init_Find_Path(x,y,mx,my,find_path)
        else
            if find_path.path then                
                if  find_path.current_index > #find_path.path then
                    logger:info("已经完成路径")
                    find_path.path = nil
                else
                    local point = find_path.path[ find_path.current_index]
                    if not point then
                        logger:info("出现异常错误")
                        return
                    end
                    local target  = {
                        x = find_path.path[#find_path.path].x,
                        y = find_path.path[#find_path.path].y
                    }
                    GuiText(gui,150,200,"当前坐标" .. string.format("%.0f|%.0f",x,y) )
                    GuiText(gui,150,220,"目标坐标" .. string.format("%.0f|%.0f",point.x,point.y) )
                    GuiText(gui,150,240,"最终坐标" .. string.format("%.0f|%.0f",target.x,target.y) )
                    Apply_Move(Player,point)
                    -- 检查是否到目标点
                    local disti = (x-point.x)^2 + (y-4-point.y)^2
                    if disti < find_path.max_dist then
                        logger:info("[移动] 到达节点 " .. find_path.current_index .. ": " .. math.floor(point.x) .. ", " .. math.floor(point.y))
                        find_path.current_index =  find_path.current_index + 1
                        find_path.last_time_current_index_changed = GameGetFrameNum()
                    end                                
                end
            else
                Apply_Move_No_Path(Player)
            end
        end 
    end
end

function OnWorldPostUpdate()
 
end

local a = 0
function Display_path(path_disp,start_disp,end_disp,nodes_disp)
    if  InputIsKeyJustDown(13) then
        a = (a+1) %3
    end
    if a==0 then 
            for i,v in ipairs(path_disp or {}) do
            GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
            -- local vx,vy = world_2_ui_pos(v.x,v.y)
            -- GuiText(gui,vx,vy,string.format("序号:%.0f(%.0f,%.0f)",i,v.x,v.y))
        end
    elseif a== 1 then 
        if start_disp and end_disp then
            for i,v in ipairs({start_disp,end_disp} or {}) do
                GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
                -- local vx,vy = world_2_ui_pos(v.x,v.y)
                -- GuiText(gui,vx,vy,string.format("序号:%.0f(%.0f,%.0f)",i,v.x,v.y))
            end
        end
    elseif a == 2 then
        -- 显示节点
        for k,v in pairs(nodes_disp or {}) do
            GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
            -- local vx,vy = world_2_ui_pos(v.x,v.y)
            -- GuiText(gui,vx,vy,string.format("序号:%.0f(%.0f,%.0f)",i,v.x,v.y))              
        end
    end
end
-- 显示速度
local last_vx  = 0 
local last_vy = 0 
---@param Player_disp Player
function Log_Speed(Player_disp,logger)
    -- 米娜速度和加速度显示
    local velocity_comp = Player_disp:get_comp("VelocityComponent")
    if not velocity_comp then return end 
    local vx,vy = ComponentGetValue2(velocity_comp:get_id(),"mVelocity")
    logger:debug(string.format("速度:%.2f,%.2f,",vx,vy))
    logger:debug(string.format("加速度:%.2f,%.2f,",vx-last_vx,vy-last_vy ))
    last_vx = vx  or 0 
    last_vy = vy or 0 
end

---@param config  find_path
function Init_Find_Path(start_X,start_Y,targetX,targetY,config)
    local x,y = start_X,start_Y
    -- 查找路径
    -- 如果位置和目标都有效，执行路径查找
    if x and y and targetX and targetY then
        logger:info("[点击] 开始寻路...")
        local f_path_true, nodes_finded=logger:func(FindPath,
            {x, y, targetX, targetY, false,nil,nil,logger}
            ,{
                current_fore = logger.current_fore + 1,
                current_pos =  "FindPath",                               
        })   
        config.path = f_path_true
        config.path_true = f_path_true
        config.nodes_finded = nodes_finded
        config.current_index = 1  -- 当前路径点索引    
        if f_path_true then
            logger:info("[点击] 寻路成功! 路径节点数: " .. #f_path_true)
            config.last_time_current_index_changed = GameGetFrameNum()
        else
            logger:warn("[点击] 寻路失败! 未找到路径")
        end
    else
        logger:warn("[点击] 坐标无效，无法寻路")
    end
    logger:save("w")
end
function Apply_Move(_player,_point)
    local player = _player
    local point = _point
   
    local controls = player:controls_comp()
    local x,y = player:get_pos()
    if controls then
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
function Apply_Move_No_Path(player)
    local controls = player:controls_comp()
    controls.mButtonDownDown = false
    controls.mButtonDownFly = false
    controls.mButtonDownRight = false
    controls.mButtonDownLeft  = false
end

-- 踢板skill
---@param player Player
---@param sTout STOut
function Kick_book(player,sTout)
    local controls = player:controls_comp()
    if not controls then return nil end 
    local controls_enabled = controls.enabled
    controls.enabled = false
    -- 踢击
    controls.mButtonDownKick = true
    controls.mButtonFrameKick = GameGetFrameNum()
    sTout:add_func(function ()
        controls.mButtonDownKick = false
    end,1)
    
    -- 修改某个键值
    sTout:add_func(function (_player)        
        local x,y = _player:get_pos()
        -- 寻找最近的生物
        local entities = EntityGetInRadiusWithTag(x,y,100,"hittable")
        local tx,ty =0,0 
        for _,v in ipairs(entities or {}) do
            local entity  = M.Animals:new(v)
            if entity:get_herd_id()~=nil and entity:get_herd_id()~=0 and    not entity:has_tag("player_unit") then
                tx,ty = entity:get_pos()
                break  
            end
        end
        if tx~=0 and ty ~=0 then
                -- 修改鼠标位置？
            ComponentSetValueVector2(controls:get_id(),"mMousePosition",tx,ty)
            ComponentSetValueVector2(controls:get_id(),"mAimingVector",tx-x,ty-y)
            -- 修改相对位置
            ComponentSetValueVector2(controls:get_id(),"mAimingVectorNormalized",(tx-x)/100,(ty-y)/100)
        end
        -- 扔出石板
        controls.mButtonDownThrow = true
        controls.mButtonFrameThrow = GameGetFrameNum()+1            
    end,5,{player})
    -- 修改某个键值
    sTout:add_func(function ()
        -- controls.mButtonDownLeftClick = false
        controls.mButtonDownThrow = false
        -- controls.enabled = controls_enabled
    end,6)
    sTout:add_func(function ()
        -- controls.mButtonDownLeftClick = false
        -- controls.mButtonDownThrow = false
        controls.enabled = controls_enabled
    end,30)
end

