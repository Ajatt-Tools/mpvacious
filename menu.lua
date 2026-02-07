--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Menu for mpvacious
]]

local mp = require('mp')
local msg = require('mp.msg')
local h = require('helpers')

local Menu = {
    name = "base menu",
    active = false,
    keybindings = {},
    overlay = mp.create_osd_overlay and mp.create_osd_overlay('ass-events'),
    menu_controller = nil,
}

function Menu:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Menu:with_update(params)
    return function(...)
        local to_call = h.combine_lists(params, { ... })
        local status, error = pcall(h.unpack(to_call))
        if not status then
            msg['error'](error)
        end
        return self:update()
    end
end

function Menu:make_osd()
    error("not implemented.")
end

function Menu:update()
    if self.active == false then
        return false
    end
    self.overlay.data = self:make_osd():get_text()
    self.overlay:update()
    return true
end

function Menu:make_key_bindings()
    error("not implemented.")
end

function Menu:add_key_bindings(keybindings)
    for _, val in pairs(keybindings) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end
end

function Menu:open()
    if self.overlay == nil then
        h.notify("OSD overlay is not supported in " .. mp.get_property("mpv-version"), "error", 5)
        return false
    end

    if self.active == true then
        self:close()
        return false
    end

    if self.menu_controller then
        self.menu_controller.request_seat(self)
    end

    if h.is_empty(self.keybindings) then
        self.keybindings = self:make_key_bindings()
    end
    self:add_key_bindings(self.keybindings)
    self.active = true
    self:update()
    return true
end

function Menu:remove_key_bindings(keybindings)
    for _, val in pairs(keybindings) do
        mp.remove_key_binding(val.key)
    end
end

function Menu:close()
    if self.active == false then
        return false
    end
    self:remove_key_bindings(self.keybindings)
    self.overlay:remove()
    self.active = false
    return true
end

return Menu
