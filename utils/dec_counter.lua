--[[
Copyright: Ajatt-Tools and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Set a counter, decrease it, run a callback when the counter hits zero.
]]

local make_counter = function(initial_value)
    local value = initial_value
    local on_finish_fn
    local self = {}
    self.decrease = function()
        -- Decrease counter.
        value = value - 1
        if type(on_finish_fn) == 'function' and value <= 0 then
            on_finish_fn()
            on_finish_fn = nil
        end
        return self
    end
    self.on_finish = function(fn)
        -- Set callback.
        on_finish_fn = fn
        return self
    end
    return self
end

return {
    new = make_counter
}
