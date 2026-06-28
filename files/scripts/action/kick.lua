-- 踢板skill
---@class YoitaAI.Kick
local Kick = {
    count = 30,
    controls_enabled = false
}
--[[
    调用时，每tick调用update
    替班调用 kick()
]]
---@param player Player
function Kick:update(player)
    local controls = player:controls_comp()
    if not controls then return nil end
    self.controls_enabled = controls.enabled
    if count == 0 then
        controls.enabled = false
        -- 踢击
        controls.mButtonDownKick = true
        controls.mButtonFrameKick = GameGetFrameNum()
    elseif count == 1 then
        controls.mButtonDownKick = false
    elseif count == 5 then
        local x,y = player:get_pos()
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
    elseif count == 6 then
        controls.mButtonDownThrow = false
    elseif count == 30 then
        controls.enabled = self.controls_enabled
    end
    if count < 31 then
        count = count + 1
        return
    end
end
function Kick:kick()
    self.count = 0
end
return Kick