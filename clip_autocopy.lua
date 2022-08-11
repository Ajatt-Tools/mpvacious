--[[
Clipboard autocopy send subs to the clipboard as they appear on the screen.

Copyright (C) 2022 Ren Tatsumoto

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
