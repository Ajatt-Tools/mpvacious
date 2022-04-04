--[[
Menu for mpvacious

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
local help = require('helpers')

local Menu = {
    active = false,
    keybindings = {},
    overlay = mp.create_osd_overlay and mp.create_osd_overlay('ass-events'),
}

function Menu:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Menu:with_update(params)
    return function()
        pcall(help.unpack(params))
        self:update()
    end
end

function Menu:make_osd()
    return nil
end

function Menu:update()
    if self.active == false then return end
    self.overlay.data = self:make_osd():get_text()
    self.overlay:update()
end

function Menu:open()
    if self.overlay == nil then
        help.notify("OSD overlay is not supported in " .. mp.get_property("mpv-version"), "error", 5)
        return
    end

    if self.active == true then
        self:close()
        return
    end

    for _, val in pairs(self.keybindings) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end

    self.active = true
    self:update()
end

function Menu:close()
    if self.active == false then
        return
    end

    for _, val in pairs(self.keybindings) do
        mp.remove_key_binding(val.key)
    end

    self.overlay:remove()
    self.active = false
end

return Menu
