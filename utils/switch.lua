--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Switch cycles between values in a table.
]]

local make_switch = function(states)
    local self = {
        states = states,
        current_state = 1
    }
    local bump = function()
        self.current_state = self.current_state + 1
        if self.current_state > #self.states then
            self.current_state = 1
        end
    end
    local get = function()
        return self.states[self.current_state]
    end
    local set = function(new_state)
        for idx, value in ipairs(self.states) do
            if value == new_state then
                self.current_state = idx
            end
        end
    end
    return {
        bump = bump,
        get = get,
        set = set,
    }
end

return {
    new = make_switch
}
