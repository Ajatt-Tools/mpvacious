--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Clipboard autocopy send subs to the clipboard as they appear on the screen.
]]

local mp = require('mp')
local h = require('helpers')
local self = {
    config = nil,
    copy_to_clipboard = nil,
    subs_observer = nil,
}

local external_command_args = function(lookup_word)
    local args = {}
    for arg in string.gmatch(self.config.autoclip_command, "%S+") do
        table.insert(args, arg)
    end
    table.insert(args, lookup_word)
    return args
end

local on_external_finish = function(success, result, error)
    print(success, result, error)
end

local call_autocopy_command = function()
    local text = self.subs_observer.recorded_or_current_text()
    if h.is_empty(text) then
        return
    end
    -- If autoclip command is not set, copy to the clipboard.
    -- If it is set, run the external command.
    if h.is_empty(self.config.autoclip_command) then
        self.copy_to_clipboard("autocopy action", text)
    else
        h.subprocess(external_command_args(text), on_external_finish)
    end
end

local copy_current_text_to_clipboard = function()
    if self.copy_to_clipboard and self.subs_observer then
        call_autocopy_command()
    end
end

local enable = function()
    mp.observe_property("sub-text", "string", copy_current_text_to_clipboard)
end

local disable = function()
    mp.unobserve_property(copy_current_text_to_clipboard)
end

local is_enabled = function()
    return self.config.autoclip == true and 'enabled' or 'disabled'
end

local state_notify = function()
    h.notify(string.format("Clipboard autocopy has been %s.", is_enabled()))
end

local toggle = function()
    self.config.autoclip = not self.config.autoclip
    if self.config.autoclip == true then
        enable()
    else
        disable()
    end
    state_notify()
end

local init = function(config, clipboard_fn, subs_observer)
    self.config = config
    self.copy_to_clipboard = clipboard_fn
    self.subs_observer = subs_observer

    if self.config.autoclip then
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
