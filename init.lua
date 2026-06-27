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
local sTout = dofile_once(base_file ..  "files/scripts/utils/SetTimeOut.lua")

local Kick  = dofile_once(base_file .. "files/scripts/action/kick.lua" ) 
local FindPath = dofile_once(base_file .. "files/scripts/memory/FindPath.lua")

local display_mode = 0
function OnWorldPreUpdate() 
    sTout:Loop()

    -- frame_counter = frame_counter + 1
    GuiStartFrame(gui)
    if gui == nil then
        gui = GuiCreate()
    end


    --寻路启动！
    if not Player or not Player:is_living() then return nil end 
    local controls = Player:controls_comp()
   
    
    FindPath.update(Player)
    local debug = FindPath.debug

    -- 按p设置
    if InputIsKeyJustDown(19) then
        controls.enabled = not controls.enabled 
    end
    if InputIsKeyJustDown(18) then
        Player:set_max_hp(1000000)
        Player:set_hp(1000000)
        FindPath.is_finding = not FindPath.is_finding
        print("FindPath: " .. (FindPath.is_finding and "ON" or "OFF") )
    end

    local x,y = Player:get_pos()

    local display_mode_name = {
        [0] = "路径节点",
        [1] = "目标节点",
        [2] = "所有节点",
    }

    GuiText(gui,100,180,"[寻路信息] 按O键切换寻路状态，按P键切换玩家操作状态")
    GuiText(gui,100,200,"显示模式(按J键切换): ".. display_mode_name[display_mode] )
    GuiText(gui,100,220,string.format("Pos: %.2f, %.2f",x,y  ))
   

    local chunk_key = debug.curr_chunk_key()
    local small_path = debug.path_nodes()
    local small_index = debug.index()
    local big_path = debug.big_path()
    local big_index = debug.big_index()

    GuiText(gui,100,240,"当前Chunk: " .. chunk_key)
    GuiText(gui,200,240,"当前block_id:" .. (debug.curr_block_id() or "none" ))
    GuiText(gui,100,260,"FindPath: " .. (FindPath.is_finding and "ON" or "OFF"))
    GuiText(gui,100,280,"小寻路: " .. (#small_path > 0 and (small_index .. "/" .. #small_path) or "none"))
    GuiText(gui,120,300, "当前节点；" .. (small_path[small_index] and string.format("%.2f, %.2f",small_path[small_index].x,small_path[small_index].y) or "none" ) )
    GuiText(gui,220,300,"下一个节点；" .. (small_path[small_index+1] and string.format("%.2f, %.2f",small_path[small_index+1].x,small_path[small_index+1].y) or "none" ) )
    GuiText(gui,320,300, "目标节点；" .. (small_path[#small_path] and string.format("%.2f, %.2f",small_path[#small_path].x,small_path[#small_path].y) or "none" ) )
    GuiText(gui,100,320,"大寻路: " .. (#big_path > 0 and (big_index .. "/" .. #big_path) or "none" ))
    GuiText(gui,120,340, "当前节点；" .. (( big_path[big_index] and big_path[big_index]) or "none" ))
    GuiText(gui,220,340,"下一个节点；" .. (( big_path[big_index+1] and big_path[big_index+1]) or "none" ) )
    GuiText(gui,320,340, "目标节点；" .. (( big_path[#big_path] and big_path[#big_path]) or "none" ) )

    -- GuiText(gui,100,300,"LittlePath: " .. (#FindPath.path_nodes() > 0 and (FindPath.get_index() .. "/" .. #FindPath.path_nodes()) or "none"))


    -- 显示切换：Enter 键切换模式
    if InputIsKeyJustDown(13) then
        display_mode = (display_mode + 1) % 3
    end
    if display_mode == 0 then
        Display_pos_table(debug.path_nodes())
    elseif display_mode == 1 then
        Display_pos_table(debug.target_nodes())
    else 
        Display_pos_table(debug.all_nodes(x,y))
    end
    if true then return end
end

function OnWorldPostUpdate()
end
function Display_pos_table(t)
    for i,v in ipairs(t or {}) do 
        GameCreateSpriteForXFrames( "data/particles/radar_enemy_strong.png", v.x, v.y, true, 0, 0, 2, true )
    end
end

