--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Object that remembers manually set timings.
]]

local new_timings = function()
    local self = { ['start'] = -1, ['end'] = -1, }
    local is_set = function(position)
        return self[position] >= 0
    end
    local set = function(position, time)
        self[position] = time
    end
    local get = function(position)
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
