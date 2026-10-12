--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle construction, comparison, and timing tests.
]]

local h = require("helpers")
local subtitle = require("subtitles.subtitle")

--- Compare subtitle events within the timing tolerance.
local function test_is_same_event()
    h.assert_equals(
        subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Same line", 0, 2)),
        true
    )
    h.assert_equals(
        subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Same line", 0.04, 2.04)),
        true
    )
    h.assert_equals(
        subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Same line", 0.06, 2)),
        false
    )
    h.assert_equals(
        subtitle.make_subtitle("Same line", 0, 2):is_same_event(subtitle.make_subtitle("Other line", 0, 2)),
        false
    )
end

--- Verify equality delegates to subtitle event comparison.
local function test_eq_uses_same_event()
    -- __eq delegates to is_same_event: same text and timing within tolerance.
    h.assert_equals(subtitle.make_subtitle("A", 0, 2) == subtitle.make_subtitle("A", 0.04, 2.04), true)
    h.assert_equals(subtitle.make_subtitle("A", 0, 2) == subtitle.make_subtitle("A", 3, 4), false)
end

--- Distinguish overlapping, touching, and disjoint subtitle windows.
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

--- Verify duration and symmetric overlap calculations.
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

--- Allow only matching forward subtitle expansions without a gap.
local function test_can_expand_with()
    h.assert_equals(subtitle.make_subtitle("A", 0, 1):can_expand_with(subtitle.make_subtitle("A", 1, 2)), true)
    h.assert_equals(subtitle.make_subtitle("A", 0, 2):can_expand_with(subtitle.make_subtitle("A", 1, 3)), true)
    h.assert_equals(subtitle.make_subtitle("A", 0, 1):can_expand_with(subtitle.make_subtitle("A", 1.01, 2)), false)
    h.assert_equals(subtitle.make_subtitle("A", 1, 2):can_expand_with(subtitle.make_subtitle("A", 0, 1)), false)
    h.assert_equals(subtitle.make_subtitle("A", 0, 1):can_expand_with(subtitle.make_subtitle("B", 0.5, 2)), false)
end

--- Expand the end timestamp without changing the start.
local function test_expand_end_time()
    local expanded = subtitle.make_subtitle("A", 0, 1):expand_end_time(subtitle.make_subtitle("A", 1, 3))
    h.assert_equals(expanded["start"], 0)
    h.assert_equals(expanded["end"], 3)
end

--- Supply independent subtitle and audio delays for timing tests.
local function make_mp_stub_for_tests()
    local delays = { ["sub-delay"] = 10, ["secondary-sub-delay"] = 3, ["audio-delay"] = 1 }
    --- Return the requested timing offset.
    local function get_property_native(name)
        return delays[name]
    end
    return { get_property_native = get_property_native }
end

--- Apply each subtitle track's delay relative to audio.
local function test_subtitle_delay()
    local mp_stub = make_mp_stub_for_tests()
    local cases = {
        { is_secondary = false, expected_start = 10, expected_end = 11 },
        { is_secondary = true, expected_start = 3, expected_end = 4 },
    }
    for _, case in ipairs(cases) do
        local shifted = subtitle.make_subtitle("Line", 1, 2):delay(subtitle.subtitle_delay(case.is_secondary, mp_stub))
        h.assert_equals(shifted["start"], case.expected_start)
        h.assert_equals(shifted["end"], case.expected_end)
    end
end

--- Supply visible primary and secondary subtitle properties without changing mp.
local function make_current_subtitle_test_api(visible)
    local properties = {
        ["sub-text"] = "Primary",
        ["secondary-sub-text"] = "Secondary",
        ["sub-start"] = 1,
        ["sub-end"] = 2,
        ["secondary-sub-start"] = 4,
        ["secondary-sub-end"] = 6,
        ["sub-delay"] = 10,
        ["secondary-sub-delay"] = 3,
        ["audio-delay"] = 1,
    }
    return {
        get_property = function(name) return properties[name] end,
        get_property_number = function(name)
            if visible then return properties[name] end
            return nil
        end,
        get_property_native = function(name) return properties[name] end,
    }
end

--- Collect visible tracks with delays applied and reject absent subtitle timings.
local function test_make_current()
    for _, case in ipairs {
        { secondary = false, visible = true, text = "Primary", start_time = 10, end_time = 11 },
        { secondary = true, visible = true, text = "Secondary", start_time = 6, end_time = 8 },
        { secondary = false, visible = false },
        { secondary = true, visible = false },
    } do
        local current = subtitle.make_current(case.secondary, make_current_subtitle_test_api(case.visible))
        if case.visible then
            h.assert_equals(current.text, case.text)
            h.assert_equals(current["start"], case.start_time)
            h.assert_equals(current["end"], case.end_time)
            h.assert_equals(current.is_secondary, case.secondary)
        else
            h.assert_equals(current, nil)
        end
    end
end

--- Verify clones preserve methods and all fields while owning their scalar values.
local function test_clone()
    for _, case in ipairs { { text = "Primary" }, { text = "" }, {} } do
        local original = subtitle.Subtitle:new {
            text = case.text,
            secondary = "Secondary",
            ["start"] = 1,
            ["end"] = 3,
            is_secondary = true,
            extra = { source = "test" },
        }
        local cloned = original:clone()
        h.assert_equals(rawequal(cloned, original), false)
        h.assert_equals(cloned, original)
        h.assert_equals(rawget(cloned, "text"), rawget(original, "text"))
        h.assert_equals(getmetatable(cloned), getmetatable(original))
        h.assert_equals(cloned:duration(), 2)
        h.assert_equals(rawequal(cloned.extra, original.extra), true)
        cloned.text, cloned.secondary, cloned["end"] = "Changed", "Changed translation", 5
        h.assert_equals(rawget(original, "text"), case.text)
        h.assert_equals(original.secondary, "Secondary")
        h.assert_equals(original:duration(), 2)
        h.assert_equals(cloned:duration(), 4)
    end
end

--- Run subtitle comparison, construction, cloning, and timing tests.
local function run_tests()
    test_is_same_event()
    test_eq_uses_same_event()
    test_time_overlap()
    test_duration_and_overlap_duration()
    test_can_expand_with()
    test_expand_end_time()
    test_subtitle_delay()
    test_make_current()
    test_clone()
end

return {
    run_tests = run_tests,
}
