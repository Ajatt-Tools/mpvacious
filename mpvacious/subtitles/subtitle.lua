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

--- Return true if this sub and other intersect in time. Touching boundaries do not count.
function Subtitle:overlaps_in_time(other)
    return self['start'] < other['end'] and self['end'] > other['start']
end

--- Return true if this sub and other intersect or merely touch in time.
function Subtitle:overlaps_or_touches_in_time(other)
    return self['start'] <= other['end'] and self['end'] >= other['start']
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

local function sub(text, start_time, end_time)
    return Subtitle:from_text(text, start_time, end_time)
end

local function test_is_same_event()
    h.assert_equals(sub("Same line", 0, 2):is_same_event(sub("Same line", 0, 2)), true)
    h.assert_equals(sub("Same line", 0, 2):is_same_event(sub("Same line", 0.04, 2.04)), true)
    h.assert_equals(sub("Same line", 0, 2):is_same_event(sub("Same line", 0.06, 2)), false)
    h.assert_equals(sub("Same line", 0, 2):is_same_event(sub("Other line", 0, 2)), false)
end

local function test_eq_uses_same_event()
    -- __eq delegates to is_same_event: same text and timing within tolerance.
    h.assert_equals(sub("A", 0, 2) == sub("A", 0.04, 2.04), true)
    h.assert_equals(sub("A", 0, 2) == sub("A", 3, 4), false)
end

local function test_time_overlap()
    local cases = {
        -- {first, second, overlaps, overlaps_or_touches}
        { sub("A", 0, 2), sub("B", 1, 3), true, true },
        { sub("A", 0, 1), sub("B", 1, 2), false, true },
        { sub("A", 0, 1), sub("B", 1.01, 2), false, false },
        { sub("A", 0, 5), sub("B", 1, 2), true, true },
    }
    for _, case in ipairs(cases) do
        local first, second, overlaps, overlaps_or_touches = h.unpack(case)
        h.assert_equals(first:overlaps_in_time(second), overlaps)
        h.assert_equals(first:overlaps_or_touches_in_time(second), overlaps_or_touches)
    end
end

local function test_can_expand_with()
    h.assert_equals(sub("A", 0, 1):can_expand_with(sub("A", 1, 2)), true)
    h.assert_equals(sub("A", 0, 2):can_expand_with(sub("A", 1, 3)), true)
    h.assert_equals(sub("A", 0, 1):can_expand_with(sub("A", 1.01, 2)), false)
    h.assert_equals(sub("A", 1, 2):can_expand_with(sub("A", 0, 1)), false)
    h.assert_equals(sub("A", 0, 1):can_expand_with(sub("B", 0.5, 2)), false)
end

local function test_expand_end_time()
    local expanded = sub("A", 0, 1):expand_end_time(sub("A", 1, 3))
    h.assert_equals(expanded['start'], 0)
    h.assert_equals(expanded['end'], 3)
end

function Subtitle.run_tests()
    test_is_same_event()
    test_eq_uses_same_event()
    test_time_overlap()
    test_can_expand_with()
    test_expand_end_time()
end

return Subtitle
