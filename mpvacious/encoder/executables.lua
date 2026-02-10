--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local utils = require('mp.utils')

local self = {}

local function alt_path_dirs()
    return {
        '/opt/homebrew/bin',
        '/usr/local/bin',
        utils.join_path(os.getenv("HOME") or "~", '.local/bin'),
    }
end

--- Try to find name in alternative locations.
--- If not found, return name as is to use executable in PATH.
function self.find_exec(name)
    local path, info
    for _, alt_dir in pairs(alt_path_dirs()) do
        path = utils.join_path(alt_dir, name)
        info = utils.file_info(path)
        if info and info.is_file then
            return path
        end
    end
    return name
end

self.mpv = self.find_exec("mpv")
self.ffmpeg = self.find_exec("ffmpeg")

return self
