--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Platform-specific functions for Windows.
]]

local mp = require('mp')
local h = require('helpers')
local utils = require('mp.utils')
local curl_tmpfile_path = utils.join_path(os.getenv('TEMP'), 'curl_tmp.txt')
local self = { windows = true, }

mp.register_event('shutdown', function()
    os.remove(curl_tmpfile_path)
end)

self.tmp_dir = function()
    return os.getenv('TEMP')
end

self.copy_to_clipboard = function(text)
    text = text:gsub("&", "^^^&"):gsub("[<>|]", "")
    local _, quote_count = text:gsub("\"", "")
    if quote_count % 2 ~= 0 then
        text = text:gsub("\"", "'")
    end
    mp.commandv("run", "cmd.exe", "/d", "/c", string.format("@echo off & chcp 65001 >nul & echo %s|clip", text))
end

self.curl_request = function(request_json, completion_fn)
    local handle = io.open(curl_tmpfile_path, "w")
    handle:write(request_json)
    handle:close()
    local args = {
        'curl',
        '-s',
        '127.0.0.1:8765',
        '-H',
        'Content-Type: application/json; charset=UTF-8',
        '-X',
        'POST',
        '--data-binary',
        table.concat { '@', curl_tmpfile_path }
    }
    return h.subprocess(args, completion_fn)
end

return self

