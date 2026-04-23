

local Logger = {
}
Logger.__index = Logger

-- 日志级别定义（数值越小，级别越高）
Logger.Level = {
    DEBUG = 1,  -- 调试信息
    INFO  = 2,  -- 一般信息
    WARN  = 3,  -- 警告信息
    ERROR = 4,  -- 错误信息
    NONE  = 5,  -- 关闭日志
}

-- 创建新的日志实例
-- @param config 配置表，包含以下可选字段:
--   - Level: 日志级别，默认 INFO
--   - log_to_file: 是否写入文件，默认 true
--   - log_files: 日志文件夹路径
--   - enabled_performance_log: 是否启用性能监控，默认 false
-- @return Logger 实例
function Logger:new(config)
    config = config or {}

    local instance = setmetatable({}, self)
    instance.log_buffer     = ""                      -- 日志缓冲区
    instance.global_level   = config.global_level or Logger.Level.DEBUG   --全局等级
    instance.current_level  =math.max( config.Level or Logger.Level.INFO,instance.global_level)
    instance.log_to_file    = config.log_to_file ~=false
    instance.log_files       = config.log_files 
    instance.performance_data = {}               -- 性能数据存储
    instance.enabled_performance_log = config.enabled_performance_log or false
    instance.current_fore   = config.current_fore  or 0
    instance.current_pos    = config.current_pos or ""
    return instance
end

-- 设置日志级别
-- @param level 日志级别 (Logger.Level.DEBUG/INFO/WARN/ERROR/NONE)
function Logger:set_level(level)
    self.current_level = level
end
function Logger:get_fore()
    if self.current_fore < 0 then
        return ""
    end
    local str = ""
    for i = 1,self.current_fore do 
        str = str .. " "
    end
    return str 
end

function Logger:func(func,func_arrs,config)
    local unpack_func = unpack or table.unpack
    local old = {}
    config = config or {}
    for k,v in pairs(config) do
        --修改配置
        if self[k] then
            --检查全局配置
            if not (k == "current_level" and v < self.global_level ) then
                old[k] = self[k]
                self[k] = v
            end
        end
    end
    --执行函数
    local returns ={func(unpack_func(func_arrs))}
    --恢复配置
    for k,v in  pairs(old) do 
        if self[k] then
            self[k] = v 
        end
    end
   
    return unpack_func(returns)
end


-- 写入日志（内部方法）
-- @param level 日志级别
-- @param message 日志消息
function Logger:write(level,message)
    local message_fore = self:get_fore()
    if level < self.current_level then
        return
    end

    local level_str = self:_get_level_string(level)
    local timestamp = self:_get_timestamp()
    local log_entry = message_fore .. string.format("%s [%s] [%s] %s", timestamp, level_str,self.current_pos, message)

    -- 写入缓冲区而不是直接写入文件，减少IO操作
    self.log_buffer = self.log_buffer .. log_entry .. "\n"
end


-- 记录 DEBUG 级别日志
function Logger:debug(message)
    self:write(Logger.Level.DEBUG, message)
    
end

-- 记录 INFO 级别日志
function Logger:info(message)
    self:write(Logger.Level.INFO, message)
    
end

-- 记录 WARN 级别日志
function Logger:warn(message)
    self:write(Logger.Level.WARN, message)
end

-- 记录 ERROR 级别日志
function Logger:error(message)
    self:write(Logger.Level.ERROR, message)
end
--记录开始日志
function Logger:start()
    local timestamp = self:_get_timestamp()
    local log_entry = "\n\n\n\n=======日志记录开始=======\n" 
    log_entry = log_entry .. "  时间:"..string.format("%s" , timestamp) .. "\n\n"
    self.log_buffer = self.log_buffer .. log_entry .. "\n"
end


-- 保存日志缓冲区到文件
-- @param mode 文件打开模式，"a"为追加（默认），"w"为覆盖
-- 注意：此方法会将缓冲区写入文件并清空缓冲区
function Logger:save(mode)
    --检查是否能io
    if not  self:get_restrictions() then
        self.log_buffer = ""        -- 清空缓冲区
        return
    end


    if not self.log_to_file or self.log_buffer == "" then
        return
    end
    -- 添加间隔，使不同批次的日志有分隔
    self.log_buffer = self.log_buffer .. "\n"

    mode = mode or "a"


    --文件夹增加
    local file = self.log_files ..os.date("%Y-%m-%d") .. "log.txt"


    -- 使用 pcall 捕获文件操作错误
    local ok,err =  pcall(function ()
        local f = io.open(file,mode)
        if f then
            f:write(self.log_buffer)
            f:close()
        end
    end)

    if not ok then
        GamePrint("写入日志文件时出错: " .. tostring(err))
    else
        GamePrint("日志已保存")
    end
    self.log_buffer = ""        -- 清空缓冲区
end

-- 开始性能计时
-- @param name 计时器名称，用于标识不同的性能测试点
function Logger:start_timer(name)
    if not self.enabled_performance_log then
        return
    end
    self.performance_data[name] = {
        start_time = os.clock(),
        call_count = (self.performance_data[name] and self.performance_data[name].call_count or 0) + 1,
    }
end

-- 结束性能计时
-- @param name 计时器名称，必须与 start_timer 中的名称对应
function Logger:end_timer(name)
    if not self.enabled_performance_log then
        return
    end
    if self.performance_data[name] then
        local elapsed = os.clock() - self.performance_data[name].start_time
        self.performance_data[name].total_time = (self.performance_data[name].total_time or 0) + elapsed
    end

end

-- 输出性能报告
-- 将所有计时器的统计信息（调用次数、总耗时、平均耗时）写入日志
function Logger:log_performance()
    if not self.enabled_performance_log then
        return
    end
    self:info("=== 性能报告 ===")
    for name,data in pairs(self.performance_data) do
        local avg_time = data.total_time / data.call_count

        self:info(string.format("%s: 调用次数: %d, 总耗时: %.3f, 平均耗时: %.3f", name, data.call_count, data.total_time, avg_time))

    end
end

-- 私有方法：获取日志级别字符串
function Logger:_get_level_string(level)
    if level == Logger.Level.DEBUG then
        return "DEBUG"
    elseif level == Logger.Level.INFO then
        return "INFO"
    elseif level == Logger.Level.WARN then
        return "WARN"
    elseif level == Logger.Level.ERROR then
        return "ERROR"
    else
        return "UNKNOWN"
    end
end

-- 私有方法：获取当前时间戳
-- @return 格式化的时间字符串 (HH:MM:SS)
function Logger:_get_timestamp()

    if self:get_restrictions() then
        return os.date("%H:%M:%S")
    end
    return "ERROR"
   
end

-- 将表转换为可读的字符串格式
-- @param t 要打印的表
-- @param quad 缩进字符串，默认为单个空格，用于嵌套表的缩进显示
-- @return 表的字符串表示
function Logger:print_table(t,quad)
    quad = quad or " "
    if type(t) ~= "table" then
        return "输入值不是表"
    end
    local str = ""
    for k,v in pairs(t)  do
        if type(v) == "table" then
            str = str .. quad.. k .. ":[[\n" .. self:print_table(v,quad .. " ") .. quad .. "]]\n"
        else
            str = str .. quad .. k .. ":" .. tostring(v) .. "\n"
        end
    end
    return str
end
function Logger:get_restrictions()
    if io  and os  then
        return true 
    end
    return false
  
end

return Logger