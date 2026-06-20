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

local FindPath = dofile_once(base_file .. "files/scripts/movements/ai_movement_utilities.lua")
local move = dofile_once(base_file .. "files/scripts/action/move.lua")

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

local path_old,nodes_finded_old 

local Kick  = dofile_once(base_file .. "files/scripts/action/kick.lua" ) 
local memory = dofile_once(base_file .. "files/scripts/memory/manager.lua")
function OnWorldPreUpdate() 
    
    sTout:Loop()

    frame_counter = frame_counter + 1
    GuiStartFrame(gui)
    if gui == nil then
        gui = GuiCreate()
    end

       
    if not Player or not Player:is_living() then return nil end 
    local controls = Player:controls_comp()
   
    -- 按p设置
    if InputIsKeyJustDown(19) then
        controls.enabled = not controls.enabled 
    end
    if InputIsKeyJustDown(18) then
        -- controls.mButtonDownLeftClick = true
        -- Kick.Kick_book(Player,sTout)            
        
        --测试记忆系统
        local components = Floor_fill(1,0)[2]
    
        local nodes = {}
        for k,v in pairs(components) do 
            local cx,cy = k:match("(%d+)_(%d+)")
            table.insert(nodes,{x = cx,y = cy})
        end
        GamePrint("节点数量:"..#nodes)
        path_old = nodes
    end
    Display_pos_table(path_old)

    Display_path(path_old,nodes_finded_old)
    local mx_screen,my_screen  = Player:get_mouse_pos_in_screen(gui)
    local mx,my = Player:get_mouse_pos()
    local x,y = Player:get_pos()
    -- if GuiButton(gui,1145,mx_screen,my_screen,"aa    ") then
    --     -- 返回节点路径
    --     local path, nodes_finded=logger:func(FindPath,
    --         {x, y, mx, my, false,nil,nil,logger}
    --         ,{
    --             current_fore = logger.current_fore + 1,
    --             current_pos =  "FindPath",                               
    --     })   
    --     path = path or {}
    --     move:get_path(path)            

    --     path_old = path
    --     nodes_finded_old = nodes_finded
    -- else
    --     --开始寻路
    --     move:start(Player)
    -- end
    
    -- 显示现在的值？
    GuiText(gui,100,220,string.format("当前位置:%.2f,%.2f",x,y))
    local current_index = move:get_current_idx()
    if path_old == nil or #path_old <1 then
        return
    end
    local node = path_old[current_index]
    if node == nil  then
        return
    end
    GuiText(gui,100,240,string.format("当前目标位置:%.2f,%.2f",node.x,node.y))
    GuiText(gui,100,260,string.format("终点位置:%.2f,%.2f",path_old[#path_old].x,path_old[#path_old].y))
end

function OnWorldPostUpdate()
end

local a = 0
function Display_path(path,nodes_finded)
    if InputIsKeyJustDown(13) then
        a = (a+1) %3
    end
    if a==0 then 
        Display_pos_table(path)
    elseif a== 1 then 
        Display_pos_table(nodes_finded)
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

function Display_pos_table(t)
    for i,v in ipairs(t or {}) do 
        GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
    end
end

