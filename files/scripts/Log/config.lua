local Config = {}
Config.__index = Config
function Config:new()
    local instance = setmetatable({}, self)
    
    instance.settings = {
        log_level = "DEBUG",
        log_to_file = true,
        enabled_performance_log = false,
        max_search_depth = 50,
    }
    return instance
end
function Config:get(setting_name)
    return self.settings[setting_name]
end
function Config:set(setting_name,value)
    self.settings[setting_name] = value    
end

return Config