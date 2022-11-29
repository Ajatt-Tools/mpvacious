--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Platform-specific functions for *nix systems.
]]

local h = require('helpers')
local self = {}
local clip = (function()
    if h.is_mac() then
        return 'LANG=en_US.UTF-8 pbcopy'
    elseif h.is_wayland() then
        return 'wl-copy'
    else
        return 'xclip -i -selection clipboard'
    end
end)()

self.tmp_dir = function()
    return os.getenv("TMPDIR") or '/tmp'
end

self.copy_to_clipboard = function(text)
    local handle = io.popen(clip, 'w')
    handle:write(text)
    handle:close()
end

self.curl_request = function(request_json, completion_fn)
    local args = { 'curl', '-s', '127.0.0.1:8765', '-X', 'POST', '-d', request_json }
    return h.subprocess(args, completion_fn)
end

return self
