--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Clipboard autocopy send subs to the clipboard as they appear on the screen.
]]

local mp = require('mp')
local h = require('helpers')
local self = {
    enabled = false,
    copy_to_clipboard = nil,
}

local enable = function()
    mp.observe_property("sub-text", "string", self.copy_to_clipboard)
end

local disable = function()
    mp.unobserve_property(self.copy_to_clipboard)
end

local is_enabled = function()
    return self.enabled == true and 'enabled' or 'disabled'
end

local state_notify = function()
    h.notify(string.format("Clipboard autocopy has been %s.", is_enabled()))
end

local toggle = function()
    self.enabled = not self.enabled
    if self.enabled == true then
        enable()
    else
        disable()
    end
    state_notify()
end

local init = function(start_enabled, clipboard_fn)
    self.enabled = start_enabled
    self.copy_to_clipboard = clipboard_fn
    if self.enabled then
        enable()
    end
end

return {
    init = init,
    enable = enable,
    disable = disable,
    toggle = toggle,
    is_enabled = is_enabled,
}
