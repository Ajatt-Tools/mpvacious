--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Object that remembers manually set timings.
]]

local h = require("helpers")

local new_timings = function()
    local self = { ["start"] = -1, ["end"] = -1 }
    local is_set = function(position)
        h.assert_in(position, { "start", "end" })
        return self[position] >= 0
    end
    local set = function(position, time)
        h.assert_in(position, { "start", "end" })
        self[position] = time
    end
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
