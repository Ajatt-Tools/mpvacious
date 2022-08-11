--[[
Subtitle class provides methods for comparing subtitle lines.

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
local Subtitle = {
    ['text'] = '',
    ['secondary'] = '',
    ['start'] = -1,
    ['end'] = -1,
}

function Subtitle:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Subtitle:now()
    local this = self:new {
        ['text'] = mp.get_property("sub-text"),
        ['secondary'] = mp.get_property("secondary-sub-text"),
        ['start'] = mp.get_property_number("sub-start"),
        ['end'] = mp.get_property_number("sub-end"),
    }
    if this:valid() then
        return this:delay(mp.get_property_native("sub-delay") - mp.get_property_native("audio-delay"))
    else
        return nil
    end
end

function Subtitle:delay(delay)
    self['start'] = self['start'] + delay
    self['end'] = self['end'] + delay
    return self
end

function Subtitle:valid()
    return self['start'] and self['end'] and self['start'] >= 0 and self['end'] > 0
end

Subtitle.__eq = function(lhs, rhs)
    return lhs['text'] == rhs['text']
end

Subtitle.__lt = function(lhs, rhs)
    return lhs['start'] < rhs['start']
end

return Subtitle
