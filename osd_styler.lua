--[[
A helper class for styling OSD messages
http://docs.aegisub.org/3.2/ASS_Tags/

Copyright (C) 2021 Ren Tatsumoto

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

local OSD = {}
OSD.__index = OSD

function OSD:new()
    return setmetatable({ messages = {} }, self)
end

function OSD:append(s)
    table.insert(self.messages, tostring(s))
    return self
end

function OSD:newline()
    return self:append([[\N]])
end

function OSD:tab()
    return self:append([[\h\h\h\h]])
end

function OSD:size(size)
    return self:append('{\\fs'):append(size):append('}')
end

function OSD:font(name)
    return self:append('{\\fn'):append(name):append('}')
end

function OSD:align(number)
    return self:append('{\\an'):append(number):append('}')
end

function OSD:get_text()
    return table.concat(self.messages)
end

function OSD:color(code)
    return self:append('{\\1c&H')
               :append(code:sub(5, 6))
               :append(code:sub(3, 4))
               :append(code:sub(1, 2))
               :append('&}')
end

function OSD:text(text)
    return self:append(text)
end

function OSD:new_layer()
    return self:append('\n')
end

function OSD:bold(s)
    return self:append('{\\b1}'):append(s):append('{\\b0}')
end

function OSD:italics(s)
    return self:append('{\\i1}'):append(s):append('{\\i0}')
end

function OSD:submenu(text)
    return self:color('ffe1d0'):bold(text):color('ffffff')
end

function OSD:item(text)
    return self:color('fef6dd'):bold(text):color('ffffff')
end

function OSD:selected(text)
    return self:color('48a868'):bold(text):color('ffffff')
end

function OSD:red(text)
    return self:color('ff0000'):bold(text):color('ffffff')
end

return OSD
