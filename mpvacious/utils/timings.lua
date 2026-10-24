--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Object that remembers manually set timings.
]]

local h = require("helpers")

--- Create independent manual start/end timing storage.
local new_timings = function()
    local self = { ["start"] = -1, ["end"] = -1 }
    --- Report whether the selected timing boundary has been set.
    local is_set = function(position)
        h.assert_in(position, { "start", "end" })
        return self[position] >= 0
    end
    --- Store a numeric timing at one supported boundary, including negative unset values.
    local set = function(position, time)
        h.assert_in(position, { "start", "end" })
        h.assert_type(time, "number")
        self[position] = time
    end
    --- Return the selected timing boundary.
    local get = function(position)
        h.assert_in(position, { "start", "end" })
        return self[position]
    end
    return {
        is_set = is_set,
        set = set,
        get = get,
    }
end

return {
    new = new_timings,
}
