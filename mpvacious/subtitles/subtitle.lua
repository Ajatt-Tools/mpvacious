--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle class provides methods for storing and comparing subtitle lines.
]]

local mp = require('mp')

local Subtitle = {
    ['text'] = '',
    ['secondary'] = '',
    ['start'] = -1,
    ['end'] = -1,
    ['is_secondary'] = false,
}

function Subtitle:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Subtitle:now(secondary)
    local prefix = secondary and "secondary-" or ""
    local this = self:new {
        ['text'] = mp.get_property(prefix .. "sub-text"),
        ['start'] = mp.get_property_number(prefix .. "sub-start"),
        ['end'] = mp.get_property_number(prefix .. "sub-end"),
        ['is_secondary'] = (secondary and true or false),
    }
    if this:is_valid() then
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

function Subtitle:is_valid()
    return self['start'] and self['end'] and self['start'] >= 0 and self['end'] > self['start']
end

Subtitle.__eq = function(lhs, rhs)
    return lhs['text'] == rhs['text']
end

Subtitle.__lt = function(lhs, rhs)
    if lhs['start'] == rhs['start'] then
        return lhs['end'] < rhs['end']
    else
        return lhs['start'] < rhs['start']
    end
end

return Subtitle
