
local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
--Astar模块
dofile_once(base_file .. "files/scripts/utils/astar.lua")
--记忆模块
local ME = dofile_once(base_file .. "files/scripts/memory/manager.lua")


local FM = {
    curr_chunk_key = nil , 

}


---底层移动
---@param player Player
---@param target table 目标id
local move = function (player,target)
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
---@param player Player
local Move_no_path = function (player)
    local controls = player:controls_comp()
    controls.mButtonDownDown = false
    controls.mButtonDownFly = false
    controls.mButtonDownRight = false
    controls.mButtonDownLeft  = false
end





local Big_find = {
    path  = {},
    path_index = 0,
    
}


local Small_find = {

}
function Big_find:find()
    --实现Astar

    ---@type AStarConfig
    local config= {
        
    
    }


end
--刷新区块
local function update(player)
    local x,y = player:get_pos()
    local chunk_key = ME.get_chunk_key(x,y)
    if chunk_key ~= FM.curr_chunk_key then
        local current_block,is_change =  ME.Floor_fill(x,y)
        FM.curr_chunk_key = chunk_key
    end

end





local M = {}

return M
