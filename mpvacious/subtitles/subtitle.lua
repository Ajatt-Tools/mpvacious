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

--- Return the selected subtitle track's delay relative to the audio track.
--- mp_api defaults to mp; tests may provide an mp-compatible stub.
local function subtitle_delay(is_secondary, mp_api)
    mp_api = mp_api or mp
    local delay_property = is_secondary and 'secondary-sub-delay' or 'sub-delay'
    return mp_api.get_property_native(delay_property) - mp_api.get_property_native('audio-delay')
end

--- Build the currently displayed primary or secondary subtitle from an mp-compatible API.
--- `delay` overrides its live track delay when a caller temporarily changes that delay.
function Subtitle:from_current(secondary, mp_api, delay)
    mp_api = mp_api or mp
    local prefix = secondary and "secondary-" or ""
    local this = self:new {
        ['text'] = mp_api.get_property(prefix .. "sub-text"),
        ['start'] = mp_api.get_property_number(prefix .. "sub-start"),
        ['end'] = mp_api.get_property_number(prefix .. "sub-end"),
        ['is_secondary'] = (secondary and true or false),
    }
    if this:is_valid() then
        return this:delay(delay == nil and subtitle_delay(secondary, mp_api) or delay)
    else
        return nil
    end
end

--- Return the currently displayed primary or secondary subtitle with mpv delays applied.
function Subtitle:now(secondary)
    return self:from_current(secondary, mp)
end

--- Return this selected subtitle plus its constituent cues clipped to its timing boundaries.
function Subtitle:timing_windows()
    local windows = { self }
    for _, cue in ipairs(self.cues or {}) do
        local start_time = math.max(cue['start'], self['start'])
        local end_time = math.min(cue['end'], self['end'])
        if end_time > start_time then
            windows[#windows + 1] = Subtitle:from_text('', start_time, end_time)
        end
    end
    return windows
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

--- Return this subtitle's duration in seconds.
function Subtitle:duration()
    return self['end'] - self['start']
end

--- Return the non-negative overlap duration with another subtitle, in seconds.
function Subtitle:overlap_duration(other)
    return math.max(0, math.min(self['end'], other['end']) - math.max(self['start'], other['start']))
end

--- Return true if this sub and other intersect in time. Touching boundaries do not count.
function Subtitle:overlaps_in_time(other)
    return self:overlap_duration(other) > 0
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

local function test_duration_and_overlap_duration()
    local first = sub("A", 0, 2)
    local cases = {
        { other = sub("B", 1, 3), expected = 1 },
        { other = sub("B", 2, 3), expected = 0 },
        { other = sub("B", 3, 4), expected = 0 },
        { other = sub("B", 0.5, 1.5), expected = 1 },
    }
    h.assert_equals(first:duration(), 2)
    for _, case in ipairs(cases) do
        h.assert_equals(first:overlap_duration(case.other), case.expected)
        h.assert_equals(case.other:overlap_duration(first), case.expected)
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

local function make_mp_stub_for_tests()
    local delays = { ['sub-delay'] = 10, ['secondary-sub-delay'] = 3, ['audio-delay'] = 1 }
    local function get_property_native(name)
        return delays[name]
    end
    return { get_property_native = get_property_native }
end

local function test_subtitle_delay()
    local mp_stub = make_mp_stub_for_tests()
    local cases = {
        { is_secondary = false, expected_start = 10, expected_end = 11 },
        { is_secondary = true, expected_start = 3, expected_end = 4 },
    }
    for _, case in ipairs(cases) do
        local shifted = sub("Line", 1, 2):delay(subtitle_delay(case.is_secondary, mp_stub))
        h.assert_equals(shifted['start'], case.expected_start)
        h.assert_equals(shifted['end'], case.expected_end)
    end
end

local function test_from_current_accepts_delay_override()
    local mp_stub = {
        get_property = function()
            return "Line"
        end,
        get_property_number = function(name)
            return ({ ['secondary-sub-start'] = 1, ['secondary-sub-end'] = 2 })[name]
        end,
    }
    local current = Subtitle:from_current('secondary', mp_stub, 4)
    h.assert_equals(current['start'], 5)
    h.assert_equals(current['end'], 6)
    h.assert_equals(current.is_secondary, true)
end

local function test_timing_windows_clips_constituent_cues()
    local selected = Subtitle:new {
        text = 'Selected',
        ['start'] = 2,
        ['end'] = 8,
        cues = {
            sub('First', 1, 4),
            sub('Second', 6, 10),
        },
    }
    local windows = selected:timing_windows()
    h.assert_equals(#windows, 3)
    h.assert_equals({ windows[2]['start'], windows[2]['end'] }, { 2, 4 })
    h.assert_equals({ windows[3]['start'], windows[3]['end'] }, { 6, 8 })
end

function Subtitle.run_tests()
    test_is_same_event()
    test_eq_uses_same_event()
    test_time_overlap()
    test_duration_and_overlap_duration()
    test_can_expand_with()
    test_expand_end_time()
    test_subtitle_delay()
    test_from_current_accepts_delay_override()
    test_timing_windows_clips_constituent_cues()
end

return Subtitle
