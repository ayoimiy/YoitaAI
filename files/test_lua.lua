local mod_name = "YoitaAI"
local base_file = "mods/" .. mod_name .. "/"
local kick  = dofile_once(base_file .. "files/scripts/action/kick.lua" )   

GamePrint("挂载的表地址" .. tostring(kick))
