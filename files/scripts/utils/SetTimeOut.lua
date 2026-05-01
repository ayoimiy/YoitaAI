--[[
定时器，执行后会在n帧时候执行函数
需要传递参数，和一张表以便后续引用
对象需要为每个加入的函数存储一个number字段，然后表主循环需要，遍历每个字段，并在字段归零时，执行某函数，
执行完了之后需要移除字段，和该函数？
]]
---@class STOut
---@field list table 待执行函数表
---@method Loop 主循环
---@method add_func 新增函数
local  STOut = {
    list = {}
}
STOut.__index = STOut
---@return STOut
function STOut:new()
    local obj = {
        list = {}
    }
    setmetatable(obj,STOut)
    return obj
end
---@param func function 函数
---@param func_param? table 函数参数
---@param frames? number 多少帧后执行
function STOut:add_func(func,frames,func_param)
    local item = {
        func = func,
        func_param = func_param or {},
        frames = frames or 60 ,
    }
    table.insert(self.list,item)
end
function STOut:Loop()
    local need_remove = {}
    -- 检查是否到期
    for i,item in ipairs(self.list) do 
        if item.frames > 0 then 
            item.frames = item.frames - 1 
        else
            -- 执行
            local unpack_func = unpack or table.unpack
            item.func(unpack_func(item.func_param))
            table.insert(need_remove,1,i)      -- 记录需要删除的元素，倒序，
        end
    end
    -- 移除指定的元素
    for _,idx in ipairs(need_remove) do
        table.remove(self.list,idx)    
    end
end

return STOut:new()