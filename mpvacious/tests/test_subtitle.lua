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

--- Replace clone timings without changing the source and retain chainable subtitle methods.
local function test_set_timings()
    for _, case in ipairs { { start_time = 0, end_time = 0 }, { start_time = 2.5, end_time = 7.5 } } do
        local original = subtitle.make_subtitle("Line", 3, 7)
        local copy = original:clone()
        h.assert_equals(rawequal(copy:set_timings(case.start_time, case.end_time), copy), true)
        h.assert_equals(copy["start"], case.start_time)
        h.assert_equals(copy["end"], case.end_time)
        h.assert_equals(copy:duration(), case.end_time - case.start_time)
        h.assert_equals(copy.text, "Line")
        h.assert_equals(original["start"], 3)
        h.assert_equals(original["end"], 7)
    end
end

--- Record positive, negative, and zero offsets while retaining direct timestamp access and chaining.
local function test_delay_records_applied_offset()
    for _, offset in ipairs { 0, 1.5, -2 } do
        local sub = subtitle.make_subtitle("Line", 10, 12)
        h.assert_equals(sub.applied_delay, nil)
        h.assert_equals(rawequal(sub:delay(offset), sub), true)
        h.assert_equals(sub["start"], 10 + offset)
        h.assert_equals(sub["end"], 12 + offset)
        h.assert_equals(sub.applied_delay, offset)
        h.assert_equals(sub:duration(), 2)
    end
end

--- Reject another offset without modifying the already adjusted subtitle.
local function assert_repeated_delay_test_rejected(sub, offset)
    local original = h.shallow_copy(sub)
    local success, message = pcall(sub.delay, sub, offset)
    h.assert_equals(success, false)
    h.assert_equals(h.is_substr(message, "subtitle delay has already been applied"), true)
    h.assert_equals(h.shallow_copy(sub), original)
end

--- A second application is forbidden for original and cloned subtitles, including zero offsets.
local function test_delay_rejects_reapplication()
    for _, first_offset in ipairs { 0, 1.5, -2 } do
        for _, second_offset in ipairs { 0, first_offset, -first_offset } do
            local sub = subtitle.make_subtitle("Line", 10, 12):delay(first_offset)
            assert_repeated_delay_test_rejected(sub, second_offset)
            local copy = sub:clone()
            h.assert_equals(copy.applied_delay, first_offset)
            assert_repeated_delay_test_rejected(copy, second_offset)
        end
    end
end

--- Delaying a raw clone leaves its source raw and eligible for its own independent adjustment.
local function test_delay_preserves_raw_clone_source()
    for _, offset in ipairs { 0, 1.5, -2 } do
        local original = subtitle.make_subtitle("Line", 10, 12)
        local copy = original:clone():delay(offset)
        h.assert_equals(original.applied_delay, nil)
        h.assert_equals({ original["start"], original["end"] }, { 10, 12 })
        original:delay(offset + 1)
        h.assert_equals(copy.applied_delay, offset)
        h.assert_equals({ copy["start"], copy["end"] }, { 10 + offset, 12 + offset })
    end
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
        { is_secondary = "primary", expected_start = 10, expected_end = 11 },
        { is_secondary = "secondary", expected_start = 3, expected_end = 4 },
        { expected_start = 10, expected_end = 11 },
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
        { secondary = "primary", visible = true, text = "Primary", start_time = 10, end_time = 11 },
        { secondary = "secondary", visible = true, text = "Secondary", start_time = 6, end_time = 8 },
        { visible = true, text = "Primary", start_time = 10, end_time = 11 },
        { secondary = false, visible = false },
        { secondary = true, visible = false },
        { secondary = "primary", visible = false },
        { secondary = "secondary", visible = false },
    } do
        local mp_api = make_current_subtitle_test_api(case.visible)
        local current = subtitle.make_current { is_secondary = case.secondary, mp_api = mp_api, delay = true }
        if case.visible then
            h.assert_equals(current.text, case.text)
            h.assert_equals(current["start"], case.start_time)
            h.assert_equals(current["end"], case.end_time)
            h.assert_equals(current.is_secondary, case.secondary == true or case.secondary == "secondary")
            h.assert_equals(current.applied_delay, subtitle.subtitle_delay(case.secondary, mp_api))
        else
            h.assert_equals(current, nil)
        end
    end
end

--- Read raw cues without requiring delay properties or modifying the caller's options.
local function assert_raw_current_test_case(case, delay)
    local mp_api = make_current_subtitle_test_api(true)
    mp_api.get_property_native = nil
    local options = { is_secondary = case.selector, mp_api = mp_api, delay = delay }
    local original = h.shallow_copy(options)
    local current = subtitle.make_current(options)
    h.assert_equals(current.text, case.text)
    h.assert_equals({ current["start"], current["end"] }, { case.start_time, case.end_time })
    h.assert_equals(current.is_secondary, case.secondary)
    h.assert_equals(current.applied_delay, nil)
    h.assert_equals(current:duration(), case.end_time - case.start_time)
    h.assert_equals(h.shallow_copy(subtitle.Subtitle:now(options)), h.shallow_copy(current))
    h.assert_equals(options, original)
end

--- False or omitted delay preserves source timestamps for Boolean, named, and default selectors.
local function test_make_current_raw_options()
    for _, case in ipairs {
        { selector = false, secondary = false, text = "Primary", start_time = 1, end_time = 2 },
        { selector = true, secondary = true, text = "Secondary", start_time = 4, end_time = 6 },
        { selector = "primary", secondary = false, text = "Primary", start_time = 1, end_time = 2 },
        { selector = "secondary", secondary = true, text = "Secondary", start_time = 4, end_time = 6 },
        { secondary = false, text = "Primary", start_time = 1, end_time = 2 },
    } do
        assert_raw_current_test_case(case, false)
        assert_raw_current_test_case(case, nil)
    end
end

--- Missing timing properties reject raw and adjusted reads before consulting delay properties.
local function test_make_current_options_without_visible_cue()
    for _, delay in ipairs { false, true } do
        for _, selector in ipairs { false, true, "primary", "secondary" } do
            local mp_api = make_current_subtitle_test_api(false)
            mp_api.get_property_native = nil
            local options = { is_secondary = selector, mp_api = mp_api, delay = delay }
            h.assert_equals(subtitle.make_current(options), nil)
            h.assert_equals(subtitle.Subtitle:now(options), nil)
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
    test_set_timings()
    test_delay_records_applied_offset()
    test_delay_rejects_reapplication()
    test_delay_preserves_raw_clone_source()
    test_subtitle_delay()
    test_make_current()
    test_make_current_raw_options()
    test_make_current_options_without_visible_cue()
    test_clone()
end

return {
    run_tests = run_tests,
}
