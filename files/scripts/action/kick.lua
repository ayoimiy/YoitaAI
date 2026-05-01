local Kick = {}
Kick.__index = Kick
function Kick:new()
    local obj = {
       last_time = -1 ,
       is_kick = false
    }
    setmetatable(obj,self)
    return obj
end
---@param Player Player
function Kick:kick(Player)
    if Player and Player:is_living() then
        local controls = Player:controls_comp()         
        controls.mButtonDownKick = true 
        controls.mButtonFrameKick = GameGetFrameNum()
        self.is_kick = true
        self.last_time = 10
    end
end
---@param Player Player
function Kick:run_per_frame(Player)
    local controls = Player:controls_comp()  
    if self.is_kick ==true then        
        controls.mButtonDownKick = false
        self.is_kick = false 
    end
    if self.last_time >0 then
        self.last_time = self.last_time-1
    elseif self.last_time == 0 then
        -- 扔石板
        controls.mButtonDownLeftClick = true
        self.last_time = self.last_time-1
    else
        controls.mButtonDownLeftClick = false
    end
end

return Kick:new()