--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Object that remembers manually set timings.
]]

local h = require("helpers")

--- Create independent manual start/end timing storage.
local function new_timings()
    local self = {
        -- nil is used for unset values. negative numbers are supported.
        ["start"] = nil,
        ["end"] = nil,
    }
    local pub = {}

    --- Return whether the boundary was explicitly set.
    function pub.is_set(position)
        h.assert_in(position, { "start", "end" })
        return self[position] ~= nil
    end

    --- Store a numeric raw timestamp at a supported boundary.
    function pub.set(position, time)
        h.assert_in(position, { "start", "end" })
        h.assert_type(time, "number")
        self[position] = time
    end

    --- Return a stored boundary or -1 when it has not been set.
    function pub.get(position)
        h.assert_in(position, { "start", "end" })
        return self[position]
    end

    return pub
end

return {
    new = new_timings,
}
