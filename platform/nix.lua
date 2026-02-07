--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Platform-specific functions for *nix systems.
]]

local h = require('helpers')
local self = { healthy = true, clip_util = "", clip_cmd = "", }

if h.is_mac() then
    self.clip_util = "pbcopy"
    self.clip_cmd = "LANG=en_US.UTF-8 " .. self.clip_util
elseif h.is_wayland() then
    local function is_wl_copy_installed()
        local handle = h.subprocess { args = { 'wl-copy', '--version' } }
        return handle.status == 0 and handle.stdout:match("wl%-clipboard") ~= nil
    end

    self.clip_util = "wl-copy"
    self.clip_cmd = self.clip_util
    self.healthy = is_wl_copy_installed()
else
    local function is_xclip_installed()
        local handle = h.subprocess { args = { 'xclip', '-version' } }
        return handle.status == 0 and handle.stderr:match("xclip version") ~= nil
    end

    self.clip_util = "xclip"
    self.clip_cmd = self.clip_util .. " -i -selection clipboard"
    self.healthy = is_xclip_installed()
end

self.tmp_dir = function()
    return os.getenv("TMPDIR") or '/tmp'
end

self.copy_to_clipboard = function(text)
    local handle = io.popen(self.clip_cmd, 'w')
    handle:write(text)
    handle:close()
end

--- Parameters: args (args to curl), completion_fn, suppress_log
self.curl_request = function(o)
    o.args = h.join_lists({ 'curl' }, o.args)
    return h.subprocess(o)
end

--- Parameters: url, request_json, completion_fn, suppress_log
self.json_curl_request = function(o)
    local args = { '-s', o.url, '-X', 'POST', '-d', o.request_json }
    return self.curl_request { args = args, completion_fn = o.completion_fn, suppress_log = o.suppress_log }
end

return self
