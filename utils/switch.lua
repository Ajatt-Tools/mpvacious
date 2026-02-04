--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Switch cycles between values in a table.
]]
local h = require('helpers')

local make_switch = function(states)
    local self = {
        states = states,
        current_state = 1
    }
    local function change_menu_item(step)
        --- step = -1 or +1
        self.current_state = self.current_state + step
        if self.current_state < 1 then
            self.current_state = #self.states
        elseif self.current_state > #self.states then
            self.current_state = 1
        end
    end
    local function bump()
        return change_menu_item(1)
    end
    local function get()
        return self.states[self.current_state]
    end
    local function set(new_state)
        for idx, value in ipairs(self.states) do
            if value == new_state then
                self.current_state = idx
            end
        end
    end
    local function set_index(index)
        self.current_state = math.max(1, math.min(index, #self.states))
    end
    local function get_index()
        return self.current_state
    end
    local function all_items()
        return self.states
    end
    local function adjacent_items(before_count, after_count)
        return h.adjacent_items(self.states, self.current_state, before_count, after_count)
    end
    return {
        bump = bump,
        get = get,
        set = set,
        set_index = set_index,
        get_index = get_index,
        change_menu_item = change_menu_item,
        all_items = all_items,
        adjacent_items = adjacent_items,
    }
end

return {
    new = make_switch
}
