-- 踢板skill
local Kick = {}
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local M = dofile_once(base_file .. "files/utils/entity-lib.lua")
---@param player Player
---@param sTout STOut
function Kick.Kick_book(player,sTout)
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

---360度踢
function Kick.kick_book360(player,sTout)
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





return Kick