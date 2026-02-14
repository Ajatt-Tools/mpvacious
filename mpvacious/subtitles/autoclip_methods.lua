--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local switch = require('utils.switch')
local h = require('helpers')

local function new_autoclip_method_selector()
    local methods = { 'clipboard', 'goldendict', 'custom_command', }
    local handlers = {}
    local current_method = switch.new(methods)
    local self = {
        get = current_method.get,
        bump = current_method.bump,
        set = current_method.set,
    }

    function self.register_handler(method, handler)
        handlers[method] = handler
    end

    function self.call(current_subtitle_lines)
        -- current_subtitle_lines = {
        --     get_prepared = function()
        --         return {
        --             primary = "some text",
        --             secondary = "some text"
        --         }
        --     end,
        --     raw = {
        --         primary = "some text",
        --         secondary = "some text"
        --     }
        -- }

        if h.is_empty(current_subtitle_lines) then
            return
        else
            handlers[current_method.get()](current_subtitle_lines)
        end
    end

    return self
end

return {
    new = new_autoclip_method_selector,
}
