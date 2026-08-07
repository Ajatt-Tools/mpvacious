--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle class provides methods for storing and comparing subtitle lines.
]]

local mp = require('mp')
local h = require('helpers')

local SAME_EVENT_TIME_TOLERANCE_SECONDS = 0.05

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

function Subtitle:from_text(text, start_time, end_time)
    return self:new { ['text'] = text, ['start'] = start_time, ['end'] = end_time }
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

local function is_near(first, second)
    return math.abs(first - second) <= SAME_EVENT_TIME_TOLERANCE_SECONDS
end

function Subtitle:is_same_event(other)
    return self['text'] == other['text'] and is_near(self['start'], other['start']) and is_near(self['end'], other['end'])
end

-- Same text and overlapping (or touching) in time. Strict: a real gap is a real gap.
-- Forward-only: other must not start before self, so expanding never
-- decreases start and the recorded list stays sorted.
function Subtitle:can_expand_with(other)
    return self['text'] == other['text'] and other['start'] >= self['start'] and other['start'] <= self['end']
end

-- Expand this event's end time to cover other. Start is unchanged (forward expansion).
function Subtitle:expand_end_time(other)
    self['end'] = math.max(self['end'], other['end'])
    return self
end

Subtitle.__eq = function(lhs, rhs)
    return lhs:is_same_event(rhs)
end

Subtitle.__lt = function(lhs, rhs)
    if lhs['start'] == rhs['start'] then
        return lhs['end'] < rhs['end']
    else
        return lhs['start'] < rhs['start']
    end
end

function Subtitle.run_tests()
    h.assert_equals(Subtitle:from_text("Same line", 0, 2):is_same_event(Subtitle:from_text("Same line", 0, 2)), true)
    h.assert_equals(Subtitle:from_text("Same line", 0, 2):is_same_event(Subtitle:from_text("Same line", 0.04, 2.04)), true)
    h.assert_equals(Subtitle:from_text("Same line", 0, 2):is_same_event(Subtitle:from_text("Same line", 0.06, 2)), false)
    h.assert_equals(Subtitle:from_text("Same line", 0, 2):is_same_event(Subtitle:from_text("Other line", 0, 2)), false)

    -- __eq delegates to is_same_event: same text and timing within tolerance.
    h.assert_equals(Subtitle:from_text("A", 0, 2) == Subtitle:from_text("A", 0.04, 2.04), true)
    h.assert_equals(Subtitle:from_text("A", 0, 2) == Subtitle:from_text("A", 3, 4), false)
end

return Subtitle
