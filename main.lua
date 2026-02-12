-- For compatibility, allow running mpvacious
-- by placing the project folder in mpv's scripts directory (e.g. ~/.config/mpv/scripts).
-- Recommended only for mpvacious contributors.

local mp = require('mp')
local utils = require('mp.utils')
local mpvacious_root = utils.join_path(mp.get_script_directory(), "mpvacious")

-- Add mpvacious subfolder to Lua search path
package.path = string.format("%s/?.lua;%s", mpvacious_root, package.path)
print("new package path", package.path)

-- Run the main script
dofile(utils.join_path(mpvacious_root, "main.lua"))
