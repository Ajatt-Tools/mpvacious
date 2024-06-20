--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Platform-specific functions for Windows.
]]

local mp = require('mp')
local h = require('helpers')
local utils = require('mp.utils')
local base64 = require('utils.base64')
local curl_tmpfile_path = utils.join_path(os.getenv('TEMP'), 'curl_tmp.txt')
local self = { windows = true, healthy = true, clip_util="cmd", }

mp.register_event('shutdown', function()
    os.remove(curl_tmpfile_path)
end)

self.tmp_dir = function()
    return os.getenv('TEMP')
end

self.copy_to_clipboard = function(text)
    mp.commandv(
        "run", "powershell", "-NoLogo", "-NoProfile", "-WindowStyle", "Hidden", "-Command",
        string.format(
            "Set-Clipboard ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')))",
            base64.enc(text)
        )
    )
end

self.curl_request = function(url, request_json, completion_fn)
    local handle = io.open(curl_tmpfile_path, "w")
    handle:write(request_json)
    handle:close()
    local args = {
        'curl',
        '-s',
        url,
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
