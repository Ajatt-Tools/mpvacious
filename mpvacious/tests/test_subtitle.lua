--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle class provides methods for storing and comparing subtitle lines.
]]

local h = require('helpers')
local subtitle = require('subtitles.subtitle')

local function test_is_same_event()
    h.assert_equals(subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Same line", 0, 2)), true)
    h.assert_equals(subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Same line", 0.04, 2.04)), true)
    h.assert_equals(subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Same line", 0.06, 2)), false)
    h.assert_equals(subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Other line", 0, 2)), false)
end

local function test_eq_uses_same_event()
    -- __eq delegates to is_same_event: same text and timing within tolerance.
    h.assert_equals(subtitle.make_subtitle("A", 0, 2) == subtitle.make_subtitle("A", 0.04, 2.04), true)
    h.assert_equals(subtitle.make_subtitle("A", 0, 2) == subtitle.make_subtitle("A", 3, 4), false)
end

local function test_time_overlap()
    local cases = {
        -- {first, second, overlaps, overlaps_or_touches}
        { subtitle.make_subtitle("A", 0, 2), subtitle.make_subtitle("B", 1, 3), true, true },
        { subtitle.make_subtitle("A", 0, 1), subtitle.make_subtitle("B", 1, 2), false, true },
        { subtitle.make_subtitle("A", 0, 1), subtitle.make_subtitle("B", 1.01, 2), false, false },
        { subtitle.make_subtitle("A", 0, 5), subtitle.make_subtitle("B", 1, 2), true, true },
    }
    for _, case in ipairs(cases) do
        local first, second, overlaps, overlaps_or_touches = h.unpack(case)
        h.assert_equals(first:overlaps_in_time(second), overlaps)
        h.assert_equals(first:overlaps_or_touches_in_time(second), overlaps_or_touches)
    end
end

local function test_duration_and_overlap_duration()
    local first = subtitle.make_subtitle("A", 0, 2)
    local cases = {
        { other = subtitle.make_subtitle("B", 1, 3), expected = 1 },
        { other = subtitle.make_subtitle("B", 2, 3), expected = 0 },
        { other = subtitle.make_subtitle("B", 3, 4), expected = 0 },
        { other = subtitle.make_subtitle("B", 0.5, 1.5), expected = 1 },
    }
    h.assert_equals(first:duration(), 2)
    for _, case in ipairs(cases) do
        h.assert_equals(first:overlap_duration(case.other), case.expected)
        h.assert_equals(case.other:overlap_duration(first), case.expected)
    end
end

local function test_can_expand_with()
    h.assert_equals(subtitle.make_subtitle("A", 0, 1):can_expand_with(subtitle.make_subtitle("A", 1, 2)), true)
    h.assert_equals(subtitle.make_subtitle("A", 0, 2):can_expand_with(subtitle.make_subtitle("A", 1, 3)), true)
    h.assert_equals(subtitle.make_subtitle("A", 0, 1):can_expand_with(subtitle.make_subtitle("A", 1.01, 2)), false)
    h.assert_equals(subtitle.make_subtitle("A", 1, 2):can_expand_with(subtitle.make_subtitle("A", 0, 1)), false)
    h.assert_equals(subtitle.make_subtitle("A", 0, 1):can_expand_with(subtitle.make_subtitle("B", 0.5, 2)), false)
end

local function test_expand_end_time()
    local expanded = subtitle.make_subtitle("A", 0, 1):expand_end_time(subtitle.make_subtitle("A", 1, 3))
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
        local shifted = subtitle.make_subtitle("Line", 1, 2):delay(subtitle.subtitle_delay(case.is_secondary, mp_stub))
        h.assert_equals(shifted['start'], case.expected_start)
        h.assert_equals(shifted['end'], case.expected_end)
    end
end

local function run_tests()
    test_is_same_event()
    test_eq_uses_same_event()
    test_time_overlap()
    test_duration_and_overlap_duration()
    test_can_expand_with()
    test_expand_end_time()
    test_subtitle_delay()
end

return {
    run_tests = run_tests,
}
