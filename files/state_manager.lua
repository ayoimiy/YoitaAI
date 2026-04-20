



-- ============================================================================
-- 状态管理系统 (state_manager.lua)
-- 负责管理AI的全局状态和组件引用
-- ============================================================================

local state_manager = {}

-- 全局状态结构
local global_state = {
    -- 核心组件引用
    control_component = nil,
    damage_model = nil,
    data_component = nil,
    inv_component = nil,
    inv_gui_component = nil,  
    
    -- 初始化状态
    init_timer = 0,
    initialized = false,
    
    -- 武器系统
    attack_wand = nil,
    teleport_wand = nil,
    empty_wands = {},
    bad_wands = {},
    good_wands = {},
    
    -- 控制状态
    control_a = false,
    control_d = false,
    control_w = false,
    control_s = false,
    was_a = false,
    was_d = false,
    was_w = false,
    was_s = false,
    
    -- 特殊状态
    kick_mode = false,
    bathe = false,
    
    -- 系统状态
    dtype = 0,
    herd_id = nil,
}

-- 初始化状态管理器
function state_manager.init(player_entity)
    GamePrint("初始化状态管理器")
    -- 获取核心组件
    global_state.control_component = EntityGetFirstComponentIncludingDisabled(player_entity, "ControlsComponent")
    global_state.damage_model = EntityGetFirstComponentIncludingDisabled(player_entity, "DamageModelComponent")
    global_state.data_component = EntityGetFirstComponentIncludingDisabled(player_entity, "CharacterDataComponent")
    global_state.inv_component = EntityGetFirstComponentIncludingDisabled(player_entity, "Inventory2Component")
    global_state.inv_gui_component = EntityGetFirstComponentIncludingDisabled(player_entity, "InventoryGuiComponent") 
    
    -- 获取玩家阵营ID
    local genome = EntityGetFirstComponentIncludingDisabled(player_entity, "GenomeDataComponent")
    if genome ~= nil then
        global_state.herd_id = ComponentGetValue2(genome, "herd_id")
    end
    
    -- 初始化武器数据结构
    global_state.empty_wands = {}
    global_state.bad_wands = {}
    global_state.good_wands = {}
    
    -- 重置计时器
    global_state.init_timer = 0
    global_state.initialized = true
    GamePrint("初始化AI成功")
    return global_state.control_component ~= nil and 
           global_state.damage_model ~= nil and 
           global_state.data_component ~= nil

end

-- 更新控制状态
function state_manager.update_controls(control_a, control_d, control_w, control_s)
    global_state.control_a = control_a or false
    global_state.control_d = control_d or false
    global_state.control_w = control_w or false
    global_state.control_s = control_s or false
end

-- 设置移动输入 (新增函数)
function state_manager.set_movement_input(move_x, move_y)
    -- 重置所有移动状态
    global_state.control_a = false
    global_state.control_d = false
    global_state.control_w = false
    global_state.control_s = false
    
    -- 水平移动
    if move_x < 0 then
        global_state.control_a = true  -- 向左
    elseif move_x > 0 then
        global_state.control_d = true  -- 向右
    end

    -- 垂直移动（飞行能量检测）
    if move_y < 0 then
        local allow_fly = true
        -- 若有数据组件，则读取剩余飞行时间
        if global_state.data_component ~= nil then
            local fly_left = ComponentGetValue2(global_state.data_component, "fly_time_left")
            if fly_left ~= nil and fly_left <= 0 then
                allow_fly = false
                GamePrint("浮空能量不足，忽略向上飞请求")
            end
        end
        if allow_fly then
            global_state.control_w = true -- 向上/飞行
        end
    elseif move_y > 0 then
        global_state.control_s = true      -- 向下
    end
end

-- 应用控制到游戏
function state_manager.apply_controls()
    
    -- 如果没有控制组件，跳过其他控制逻辑
    if global_state.control_component == nil then
        GamePrint("警告：控制组件为空，无法应用控制")
        return false
    end
    
    -- 应用左右移动
    ComponentSetValue2(global_state.control_component, "mButtonDownLeft", global_state.control_a)
    if global_state.control_a and not global_state.was_a then
        ComponentSetValue2(global_state.control_component, "mButtonFrameLeft", GameGetFrameNum() + 1)
    end
    global_state.was_a = global_state.control_a

    ComponentSetValue2(global_state.control_component, "mButtonDownRight", global_state.control_d)
    if global_state.control_d and not global_state.was_d then
        ComponentSetValue2(global_state.control_component, "mButtonFrameRight", GameGetFrameNum() + 1)
    end
    global_state.was_d = global_state.control_d

    -- 应用上下移动
    ComponentSetValue2(global_state.control_component, "mButtonDownDown", global_state.control_s and not global_state.control_w)
    ComponentSetValue2(global_state.control_component, "mButtonDownUp", global_state.control_w)
    ComponentSetValue2(global_state.control_component, "mButtonDownFly", global_state.control_w)
    
    if global_state.control_w and not global_state.was_w then
        ComponentSetValue2(global_state.control_component, "mButtonFrameUp", GameGetFrameNum() + 1)
        ComponentSetValue2(global_state.control_component, "mButtonFrameFly", GameGetFrameNum() + 1)
    end
    if global_state.control_s and not global_state.control_w and not global_state.was_s then
        ComponentSetValue2(global_state.control_component, "mButtonFrameDown", GameGetFrameNum() + 1)
    end
    
    global_state.was_s = global_state.control_s and not global_state.control_w
    global_state.was_w = global_state.control_w
    
    -- 设置飞行目标
    local player_entity = EntityGetWithTag("player_unit")[1]
    if player_entity ~= nil then
        local _, y_n = EntityGetTransform(player_entity)
        ComponentSetValue2(global_state.control_component, "mFlyingTargetY", y_n - 10)
    end
    
    return true
end

-- 禁用玩家控制
function state_manager.disable_player_control()
    if global_state.control_component ~= nil then
        ComponentSetValue2(global_state.control_component, "enabled", false)
    end
end

-- 获取游戏状态信息
function state_manager.get_game_state(player_entity)
    if global_state.data_component == nil then
        return nil
    end
    
    local game_state = {
        -- 基础状态
        mana = ComponentGetValue2(global_state.data_component, "mana"),
        max_mana = ComponentGetValue2(global_state.data_component, "max_mana"),
        air_level = ComponentGetValue2(global_state.data_component, "mAirInLungs"),
        max_air = ComponentGetValue2(global_state.data_component, "mAirInLungsMax"),
        flying_time_left = ComponentGetValue2(global_state.data_component, "fly_time_left"),
        
        -- 位置信息
        x = 0,
        y = 0,
        
        -- 血量信息
        hp = 0,
        max_hp = 0,
    }
    
    -- 获取位置
    game_state.x, game_state.y = EntityGetTransform(player_entity)
    
    -- 获取血量
    if global_state.damage_model ~= nil then
        game_state.hp = ComponentGetValue2(global_state.damage_model, "hp")
        game_state.max_hp = ComponentGetValue2(global_state.damage_model, "max_hp")
    end
    
    return game_state
end

-- 更新武器状态
function state_manager.update_weapon_state(attack_wand, teleport_wand, empty_wands, bad_wands, good_wands)
    global_state.attack_wand = attack_wand
    global_state.teleport_wand = teleport_wand
    global_state.empty_wands = empty_wands or {}
    global_state.bad_wands = bad_wands or {}
    global_state.good_wands = good_wands or {}
end

-- 获取武器状态
function state_manager.get_weapon_state()
    return {
        attack_wand = global_state.attack_wand,
        teleport_wand = global_state.teleport_wand,
        empty_wands = global_state.empty_wands,
        bad_wands = global_state.bad_wands,
        good_wands = global_state.good_wands,
    }
end

-- 更新特殊状态
function state_manager.update_special_state(kick_mode, bathe)
    global_state.kick_mode = kick_mode or false
    global_state.bathe = bathe or false
end

-- 获取特殊状态
function state_manager.get_special_state()
    return {
        kick_mode = global_state.kick_mode,
        bathe = global_state.bathe,
    }
end

-- 更新初始化计时器
function state_manager.update_init_timer()
    global_state.init_timer = global_state.init_timer + 1
    return global_state.init_timer
end

-- 获取初始化时间
function state_manager.get_init_time()
    return global_state.init_timer
end

-- 检查是否已初始化
function state_manager.is_initialized()
    return global_state.initialized
end

-- 获取核心组件
function state_manager.get_components()
    return {
        control_component = global_state.control_component,
        damage_model = global_state.damage_model,
        data_component = global_state.data_component,
        inv_component = global_state.inv_component,
        inv_gui_component = global_state.inv_gui_component,
    }
end

-- 设置鼠标位置
function state_manager.set_mouse_position(x, y)
    if global_state.control_component ~= nil then
        ComponentSetValue2(global_state.control_component, "mMousePosition", x, y)
        return true
    end
    GamePrint("错误：无法设置鼠标位置，控制组件为空")
    return false
end

-- 设置射击输入
function state_manager.set_fire_input(should_fire)
    if global_state.control_component ~= nil then
        ComponentSetValue2(global_state.control_component, "mButtonDownFire", should_fire)
        ComponentSetValue2(global_state.control_component, "mButtonDownFire2", should_fire)
        
        if should_fire then
            local current_frame = GameGetFrameNum()
            ComponentSetValue2(global_state.control_component, "mButtonFrameFire", current_frame + 1)
            ComponentSetValue2(global_state.control_component, "mButtonFrameFire2", current_frame + 1)
        end
        return true
    end
    GamePrint("错误：无法设置射击输入，控制组件为空")
    return false
end

-- 获取玩家阵营ID
function state_manager.get_herd_id()
    return global_state.herd_id
end

-- 设置伤害类型
function state_manager.set_damage_type(dtype)
    global_state.dtype = dtype or 0
end

-- 获取伤害类型
function state_manager.get_damage_type()
    return global_state.dtype
end

-- 检查组件是否有效
function state_manager.validate_components()
    return global_state.control_component ~= nil and 
           global_state.damage_model ~= nil and 
           global_state.data_component ~= nil and
           global_state.inv_gui_component ~= nil  
end

-- 获取完整状态
function state_manager.get_full_state()
    return {
        -- 组件状态
        components_valid = state_manager.validate_components(),
        initialized = global_state.initialized,
        init_timer = global_state.init_timer,
        
        -- 控制状态
        control_a = global_state.control_a,
        control_d = global_state.control_d,
        control_w = global_state.control_w,
        control_s = global_state.control_s,
        
        -- 武器状态
        attack_wand = global_state.attack_wand,
        teleport_wand = global_state.teleport_wand,
        empty_wands_count = #global_state.empty_wands,
        bad_wands_count = #global_state.bad_wands,
        good_wands_count = #global_state.good_wands,
        
        -- 特殊状态
        kick_mode = global_state.kick_mode,
        bathe = global_state.bathe,
        
        -- 系统状态
        dtype = global_state.dtype,
        herd_id = global_state.herd_id,
    }
end

-- 重置状态管理器
function state_manager.reset()
    global_state = {
        -- 核心组件引用
        control_component = nil,
        damage_model = nil,
        data_component = nil,
        inv_component = nil,
        inv_gui_component = nil,  
        
        -- 初始化状态
        init_timer = 0,
        initialized = false,
        
        -- 武器系统
        attack_wand = nil,
        teleport_wand = nil,
        empty_wands = {},
        bad_wands = {},
        good_wands = {},
        
        -- 控制状态
        control_a = false,
        control_d = false,
        control_w = false,
        control_s = false,
        was_a = false,
        was_d = false,
        was_w = false,
        was_s = false,
        
        -- 特殊状态
        kick_mode = false,
        bathe = false,
        
        -- 系统状态
        dtype = 0,
        herd_id = nil,
    }
end

return state_manager 