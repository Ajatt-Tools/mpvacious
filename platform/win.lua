--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Platform-specific functions for Windows.
]]

local mp = require('mp')
local h = require('helpers')
local utils = require('mp.utils')
local base64 = require('utils.base64')
local self = { windows = true, healthy = true, clip_util = "cmd", }
local tmp_files = {}

mp.register_event('shutdown', function()
    for _, file in ipairs(tmp_files) do
        os.remove(file)
    end
end)

self.tmp_dir = function()
    return os.getenv('TEMP')
end

self.copy_to_clipboard = function(text)
    local args = {
        "powershell", "-NoLogo", "-NoProfile", "-WindowStyle", "Hidden", "-Command",
        string.format(
                "Set-Clipboard ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')))",
                base64.enc(text)
        )
    }
    return h.subprocess_detached(
            args,
            function()
            end
    )
end

self.gen_random_tmp_file_path = function()
    return utils.join_path(self.tmp_dir(), string.format('curl_tmp_%d.txt', math.random(10 ^ 9)))
end

self.gen_unique_tmp_file_path = function()
    local curl_tmpfile_path = self.gen_random_tmp_file_path()
    while h.file_exists(curl_tmpfile_path) do
        curl_tmpfile_path = self.gen_random_tmp_file_path()
    end
    return curl_tmpfile_path
end

self.curl_request = function(url, request_json, completion_fn)
    local curl_tmpfile_path = self.gen_unique_tmp_file_path()
    local handle = io.open(curl_tmpfile_path, "w")
    handle:write(request_json)
    handle:close()
    table.insert(tmp_files, curl_tmpfile_path)
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
