--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle list tests.
]]

local h = require('helpers')
local subtitle = require('subtitles.subtitle')
local sub_list = require('subtitles.sub_list')

--- Create a numbered subtitle for list-order tests.
local function numbered_sub(index)
    return subtitle.make_subtitle("Line " .. index, index, index + 1)
end

--- Fill a subtitle list with numbered test cues.
local function make_numbered_sub_list(first_index, last_index)
    local subs = sub_list.new()
    for i = first_index, last_index do
        h.assert_equals(subs.insert(numbered_sub(i)), true)
    end
    return subs
end

--- Assert that the collected subtitles remain chronologically sorted.
local function assert_subs_sorted(subs)
    local previous
    for _, sub in ipairs(subs) do
        if previous and not (previous < sub) then
            error("list is not sorted")
        end
        previous = sub
    end
end

--- Create two separated subtitle lines for test cases.
local function make_two_line_subs()
    local subs = sub_list.new()
    subs.insert(subtitle.make_subtitle("First line", 0, 2))
    subs.insert(subtitle.make_subtitle("Second line", 3, 5))
    return subs
end

--- Reject missing and empty subtitle events.
local function test_insert_rejects_invalid_subs()
    local subs = sub_list.new()
    h.assert_equals(subs.insert(nil), false)
    h.assert_equals(subs.insert(subtitle.make_subtitle("", 0, 2)), false)
end

--- Reject the same subtitle event when observed twice.
local function test_insert_rejects_duplicate_event()
    local subs = sub_list.new()
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 0, 2)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 0.04, 2.04)), false)
end

--- Extend a subtitle when the next matching event touches it.
local function test_insert_expands_touching_same_text_event()
    local subs = sub_list.new()
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 0, 1)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 1, 2)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 1)
    h.assert_equals(ordered_list[1]['start'], 0)
    h.assert_equals(ordered_list[1]['end'], 2)
    h.assert_equals(subs.get_text(), "Same line")
end

--- Preserve a single event through successive adjacent expansions.
local function test_insert_chains_expansions()
    -- Successive adjacent same-text events keep expanding the same stored sub.
    local subs = sub_list.new()
    h.assert_equals(subs.insert(subtitle.make_subtitle("A", 0, 1)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("A", 1, 2)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("A", 2, 3)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 1)
    h.assert_equals(ordered_list[1]['start'], 0)
    h.assert_equals(ordered_list[1]['end'], 3)
end

--- Keep repeated text as distinct events across a real gap.
local function test_insert_keeps_same_text_event_after_real_gap()
    local subs = sub_list.new()
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 0, 1)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 1.01, 2)), true)
    h.assert_equals(#subs.get_subs_list(), 2)
    h.assert_equals(subs.get_text(), "Same line\nSame line")
end

--- Sort events that arrive backward without merging them.
local function test_insert_keeps_backward_arrival_unmerged_and_sorted()
    local subs = sub_list.new()
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 1, 2)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Same line", 0, 1)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 2)
    h.assert_equals(ordered_list[1]['start'], 0)
    h.assert_equals(ordered_list[2]['start'], 1)
    assert_subs_sorted(ordered_list)
end

--- Avoid merging matching events across an intervening subtitle.
local function test_insert_does_not_expand_across_intervening_event()
    local subs = sub_list.new()
    h.assert_equals(subs.insert(subtitle.make_subtitle("A", 1, 2)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("B", 1, 3)), true)
    h.assert_equals(subs.insert(subtitle.make_subtitle("A", 2, 4)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 3)
    h.assert_equals(ordered_list[1]['text'], "A")
    h.assert_equals(ordered_list[1]['end'], 2)
    h.assert_equals(ordered_list[2]['text'], "B")
    h.assert_equals(ordered_list[3]['text'], "A")
    assert_subs_sorted(ordered_list)
end

--- Limit duplicate detection to the recent lookup window.
local function test_insert_uses_recent_lookup_window()
    local subs = make_numbered_sub_list(0, 29)
    h.assert_equals(#subs.get_subs_list(), 30)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Line 29", 29.04, 30.04)), false)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Line 4", 4.04, 5.04)), true)
end

--- Keep events sorted when inserting between existing cues.
local function test_insert_preserves_sorted_order()
    local subs = make_numbered_sub_list(0, 29)
    h.assert_equals(subs.insert(subtitle.make_subtitle("Line 5.5", 5.5, 6.5)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 31)
    h.assert_equals(ordered_list[6]['text'], "Line 5")
    h.assert_equals(ordered_list[7]['text'], "Line 5.5")
    h.assert_equals(ordered_list[8]['text'], "Line 6")
    assert_subs_sorted(ordered_list)
end

--- Return the first start and last end times.
local function test_get_time_returns_boundary_times()
    local subs = make_two_line_subs()
    h.assert_equals(subs.get_time('start'), 0)
    h.assert_equals(subs.get_time('end'), 5)
end

--- Prevent clients from mutating the internal subtitle list.
local function test_get_subs_list_returns_array_copy()
    local subs = make_two_line_subs()
    local copy = subs.get_subs_list()
    table.remove(copy, 1)
    h.assert_equals(#copy, 1)
    h.assert_equals(subs.get_text(), "First line\nSecond line")
    h.assert_equals(subs.get_subs_list()[1]['text'], "First line")
end

--- Return fresh text cases with timings so insertion and boundary dedup run together.
local function make_get_text_test_cases()
    return {
        { cues = { { "First line", 0, 2 }, { "First line\nSecond line", 1, 3 } }, expected = "First line\nSecond line" },
        -- The second cue is rejected by insert()'s event-level guard.
        { cues = { { "Same line", 0, 2 }, { "Same line", 0.04, 2.04 } }, expected = "Same line" },
        { cues = { { "Same line", 0, 1 }, { "Same line", 3, 4 } }, expected = "Same line\nSame line" },
        { cues = { { "Yes", 0, 1 }, { "No", 1, 2 }, { "Yes", 2, 3 } }, expected = "Yes\nNo\nYes" },
        -- A repeated line outside the adjacent suffix/prefix boundary must be kept.
        -- The old global seen-set approach dropped the final "X" here.
        { cues = { { "X", 0, 1 }, { "Y", 1, 2 }, { "Y\nX", 2, 3 } }, expected = "X\nY\nX" },
        { cues = { { "Yes\nNo", 0, 2 }, { "No\nMaybe", 2, 4 } }, expected = "Yes\nNo\nMaybe" },
        { cues = { { "First line\n\nSecond line", 0, 2 } }, expected = "First line\n\nSecond line" },
        -- Dedup only applies at boundaries between cues, not within one cue.
        { cues = { { "A\nA", 0, 2 } }, expected = "A\nA" },
        { cues = { { "First line\r\nSecond line\rThird line", 0, 2 } }, expected = "First line\nSecond line\nThird line" },
        -- A trailing newline must not introduce a spurious blank line.
        { cues = { { "First line\nSecond line\n", 0, 2 } }, expected = "First line\nSecond line" },
    }
end

--- Check every text collection case with a fresh subtitle list.
local function test_get_text()
    for _, case in ipairs(make_get_text_test_cases()) do
        local subs = sub_list.new()
        for _, cue in ipairs(case.cues) do
            subs.insert(subtitle.make_subtitle(h.unpack(cue)))
        end
        h.assert_equals(subs.get_text(), case.expected)
    end
end

--- Collect adjacent subtitle lines up to the requested count.
local function test_collect_n_subs_limit()
    local first = subtitle.make_subtitle("First line", 0, 2)
    local subs = sub_list.new()
    subs.insert(first)
    subs.insert(subtitle.make_subtitle("First line\nSecond line", 1, 3))
    h.assert_equals(subs.collect_n_subs(first, 2).text, "First line\nSecond line")

    local limited_subs = sub_list.new()
    limited_subs.insert(subtitle.make_subtitle("First line", 0, 2))
    limited_subs.insert(subtitle.make_subtitle("First line\nSecond line", 1, 3))
    limited_subs.insert(subtitle.make_subtitle("Second line\nThird line", 2, 4))
    h.assert_equals(limited_subs.collect_n_subs(first, 2).text, "First line\nSecond line")
end

--- Preserve non-adjacent repeated lines while collecting subtitles.
local function test_collect_n_subs_repeated_lines()
    -- Non-adjacent repeated lines are kept in collect_n_subs too.
    local repeated_subs = sub_list.new()
    repeated_subs.insert(subtitle.make_subtitle("Yes", 0, 1))
    repeated_subs.insert(subtitle.make_subtitle("No", 1, 2))
    repeated_subs.insert(subtitle.make_subtitle("Yes\nAgain", 2, 3))
    h.assert_equals(repeated_subs.collect_n_subs(repeated_subs.get_subs_list()[1], 3).text, "Yes\nNo\nYes\nAgain")
end

--- Count a covered cue even when it contributes no new text.
local function test_collect_n_subs_covered_line()
    -- A sub fully covered by the previous suffix still counts toward n_lines,
    -- so end_sub (used for the card's end timing) advances past it.
    local covered_subs = sub_list.new()
    local container = subtitle.make_subtitle("A\nB", 0, 2)
    covered_subs.insert(container)
    covered_subs.insert(subtitle.make_subtitle("B", 1, 3))
    covered_subs.insert(subtitle.make_subtitle("C", 2, 4))
    local combined = covered_subs.collect_n_subs(container, 2)
    h.assert_equals(combined["text"], "A\nB")
    h.assert_equals(combined['start'], 0)
    h.assert_equals(combined['end'], 3)
end

local function make_overlap_thresholds_cases()
    return {
        { sub = subtitle.make_subtitle('', 1, 3), window = subtitle.make_subtitle('', 0, 2), expected = true }, -- 50%
        { sub = subtitle.make_subtitle('', 1.01, 3.01), window = subtitle.make_subtitle('', 0, 2), expected = false },
        { sub = subtitle.make_subtitle('', 0.125, 0.625), window = subtitle.make_subtitle('', 0, 0.5), expected = true }, -- 75%
        { sub = subtitle.make_subtitle('', 0.126, 0.626), window = subtitle.make_subtitle('', 0, 0.5), expected = false },
        { sub = subtitle.make_subtitle('', 0.5, 1.5), window = subtitle.make_subtitle('', 0, 1), expected = true }, -- 1s uses 50%
        { sub = subtitle.make_subtitle('', 1, 2), window = subtitle.make_subtitle('', 0, 1), expected = false },
        { sub = subtitle.make_subtitle('', 0, 0), window = subtitle.make_subtitle('', 0, 1), expected = false },
        { sub = subtitle.make_subtitle('', 0.25, 0.75), window = subtitle.make_subtitle('', 0, 1), expected = true },
    }
end

--- Exercise ordinary, short-cue, and zero-duration overlap thresholds.
local function test_overlap_thresholds()
    for _, case in ipairs(make_overlap_thresholds_cases()) do
        h.assert_equals(sub_list.overlaps_enough(case.sub, case.window), case.expected)
    end
end

--- Combine and format subtitles aligned with the requested time window.
local function test_get_overlapping_text_formats_matches()
    local subs = sub_list.new()
    subs.insert(subtitle.make_subtitle("Before", 0, 1))
    subs.insert(subtitle.make_subtitle("First line", 1, 2))
    subs.insert(subtitle.make_subtitle("First line\nSecond line", 2, 3))
    subs.insert(subtitle.make_subtitle("After", 3, 4))
    h.assert_equals(subs.get_overlapping_text(subtitle.make_subtitle('', 1, 3)), "First line Second line")

    local spaced_subs = sub_list.new()
    spaced_subs.insert(subtitle.make_subtitle("  First\t line\nSecond  line  ", 1, 2))
    h.assert_equals(spaced_subs.get_overlapping_text(subtitle.make_subtitle('', 1, 2)), "First line Second line")
end

--- Exclude subtitles whose boundary overlap is only timing noise.
local function test_get_overlapping_text_filters_timing_noise()
    local timing_noise = sub_list.new()
    timing_noise.insert(subtitle.make_subtitle("Relevant", 759.82, 763.09))
    timing_noise.insert(subtitle.make_subtitle("Unrelated", 763.09, 766.03))
    h.assert_equals(
            timing_noise.get_overlapping_text(subtitle.make_subtitle('', 761.594, 763.179)),
            "Relevant"
    )
end

--- Run subtitle-list behavior tests in both test environments.
local function run_tests()
    test_insert_rejects_invalid_subs()
    test_insert_rejects_duplicate_event()
    test_insert_expands_touching_same_text_event()
    test_insert_chains_expansions()
    test_insert_keeps_same_text_event_after_real_gap()
    test_insert_keeps_backward_arrival_unmerged_and_sorted()
    test_insert_does_not_expand_across_intervening_event()
    test_insert_uses_recent_lookup_window()
    test_insert_preserves_sorted_order()
    test_get_time_returns_boundary_times()
    test_get_subs_list_returns_array_copy()
    test_get_text()
    test_collect_n_subs_limit()
    test_collect_n_subs_repeated_lines()
    test_collect_n_subs_covered_line()
    test_overlap_thresholds()
    test_get_overlapping_text_formats_matches()
    test_get_overlapping_text_filters_timing_noise()
end

return {
    run_tests = run_tests,
}
