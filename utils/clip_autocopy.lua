--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Clipboard autocopy send subs to the clipboard as they appear on the screen.
]]

local mp = require('mp')
local h = require('helpers')

local clip_autocopy = (function()
    local enabled = false
    local copy_to_clipboard

    local enable = function()
        mp.observe_property("sub-text", "string", copy_to_clipboard)
    end

    local disable = function()
        mp.unobserve_property(copy_to_clipboard)
    end

    local is_enabled = function()
        return enabled== true and 'enabled' or 'disabled'
    end

    local state_notify = function()
        h.notify(string.format("Clipboard autocopy has been %s.", is_enabled()))
    end

    local toggle = function()
        enabled = not enabled
        if enabled == true then
            enable()
        else
            disable()
        end
        state_notify()
    end

    local init = function(start_enabled, clipboard_fn)
        enabled = start_enabled
        copy_to_clipboard = clipboard_fn
        if enabled then
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
end)()

return clip_autocopy
