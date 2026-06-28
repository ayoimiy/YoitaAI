-- lua_c_runner.lua — Lua→C bridge: calls pathfind_c.dll via require
-- args: input.bin output.bin
local pf = require("pathfind_c")
local len, ms = pf.find(arg[1], arg[2])
