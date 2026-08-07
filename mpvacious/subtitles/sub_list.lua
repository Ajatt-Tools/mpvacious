--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle list remembers selected subtitle lines.
]]

local h = require('helpers')
local Subtitle = require('subtitles.subtitle')
local speech_collector = require('subtitles.collector')
local LOOKUP_WINDOW_SIZE = 25 -- how many recent subs to scan for duplicate events
local MAX_SUB_GAP_SECONDS = 20 -- stop joining lines separated by a longer gap

local new_sub_list = function()
    local subs_list = {}

    local get_time = function(position)
        local i = position == 'start' and 1 or #subs_list
        return subs_list[i][position]
    end
    local get_text = function()
        -- Dedup applies to every list (primary, secondary), collapsing adjacent
        -- multiline sub expansions into one continuous dialog string.
        local collector = speech_collector.make_speech_collector()
        for _, sub in ipairs(subs_list) do
            collector.append_sub(sub)
        end
        return collector.get_all_as_string()
    end
    local get_n_text = function(sub, n_lines)
        local collector = speech_collector.make_speech_collector()
        local end_sub = sub
        local n_subs = 0
        for _, v in ipairs(subs_list) do
            if v['start'] - end_sub['end'] >= MAX_SUB_GAP_SECONDS then
                break
            end
            if not (v < sub) and n_subs < n_lines then
                collector.append_sub(v)
                end_sub = v
                n_subs = n_subs + 1
            end
        end
        return collector.get_all_as_string(), end_sub
    end
    local get_overlapping_text = function(start_time, end_time)
        local collector = speech_collector.make_speech_collector()
        for _, sub in ipairs(subs_list) do
            if sub['start'] < end_time and sub['end'] > start_time then
                collector.append_sub(sub)
            end
        end
        return collector.get_all_as_string():gsub('%s+', ' '):match('^%s*(.-)%s*$')
    end
    -- Event-level guard and expansion.
    -- The same sub event is offered repeatedly (on every sub change and on
    -- every collect call); exact duplicates (same text and timing) are skipped.
    -- An adjacent same-text event (overlapping or touching in time) expands
    -- the last recorded sub's end time.
    -- Text-overlap cleanup for multiline expansion is intentionally delayed
    -- until get_text()/get_n_text(), where the selected output window is known.
    local insert = function(sub)
        if sub == nil or h.is_empty(sub.text) then
            return false
        end
        local n_latest_subs = h.itable_slice(subs_list, -LOOKUP_WINDOW_SIZE)
        for _, existing in ipairs(n_latest_subs) do
            if existing:is_same_event(sub) then
                return false
            end
        end
        -- Expand only the last stored sub.
        -- The last sub has no successor, so extending its end time cannot break sorted order.
        local last_sub = subs_list[#subs_list]
        if last_sub and last_sub:can_expand_with(sub) then
            last_sub:expand_end_time(sub)
            return true
        end
        table.insert(subs_list, (#subs_list - #n_latest_subs) + h.find_insertion_point(n_latest_subs, sub), sub)
        return true
    end
    local get_subs_list = function()
        -- Return a shallow copy so callers can't mutate the internal list.
        local copy = {}
        for key, value in pairs(subs_list) do
            copy[key] = value
        end
        return copy
    end
    return {
        get_subs_list = get_subs_list,
        get_time = get_time,
        get_text = get_text,
        get_n_text = get_n_text,
        get_overlapping_text = get_overlapping_text,
        insert = insert,
        is_empty = function()
            return h.is_empty(subs_list)
        end,
    }
end

local function numbered_sub(index)
    return Subtitle:from_text("Line " .. index, index, index + 1)
end

local function make_numbered_sub_list(first_index, last_index)
    local subs = new_sub_list()
    for i = first_index, last_index do
        h.assert_equals(subs.insert(numbered_sub(i)), true)
    end
    return subs
end

local function assert_subs_sorted(subs)
    local previous
    for _, sub in ipairs(subs) do
        if previous and not (previous < sub) then
            error("list is not sorted")
        end
        previous = sub
    end
end

local function make_two_line_subs()
    local subs = new_sub_list()
    subs.insert(Subtitle:from_text("First line", 0, 2))
    subs.insert(Subtitle:from_text("Second line", 3, 5))
    return subs
end

local function test_insert_rejects_invalid_subs()
    local subs = new_sub_list()
    h.assert_equals(subs.insert(nil), false)
    h.assert_equals(subs.insert(Subtitle:from_text("", 0, 2)), false)
end

local function test_insert_rejects_duplicate_event()
    local subs = new_sub_list()
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 0, 2)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 0.04, 2.04)), false)
end

local function test_insert_expands_touching_same_text_event()
    local subs = new_sub_list()
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 0, 1)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 1, 2)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 1)
    h.assert_equals(ordered_list[1]['start'], 0)
    h.assert_equals(ordered_list[1]['end'], 2)
    h.assert_equals(subs.get_text(), "Same line")
end

local function test_insert_chains_expansions()
    -- Successive adjacent same-text events keep expanding the same stored sub.
    local subs = new_sub_list()
    h.assert_equals(subs.insert(Subtitle:from_text("A", 0, 1)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("A", 1, 2)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("A", 2, 3)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 1)
    h.assert_equals(ordered_list[1]['start'], 0)
    h.assert_equals(ordered_list[1]['end'], 3)
end

local function test_insert_keeps_same_text_event_after_real_gap()
    local subs = new_sub_list()
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 0, 1)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 1.01, 2)), true)
    h.assert_equals(#subs.get_subs_list(), 2)
    h.assert_equals(subs.get_text(), "Same line\nSame line")
end

local function test_insert_keeps_backward_arrival_unmerged_and_sorted()
    local subs = new_sub_list()
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 1, 2)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("Same line", 0, 1)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 2)
    h.assert_equals(ordered_list[1]['start'], 0)
    h.assert_equals(ordered_list[2]['start'], 1)
    assert_subs_sorted(ordered_list)
end

local function test_insert_does_not_expand_across_intervening_event()
    local subs = new_sub_list()
    h.assert_equals(subs.insert(Subtitle:from_text("A", 1, 2)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("B", 1, 3)), true)
    h.assert_equals(subs.insert(Subtitle:from_text("A", 2, 4)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 3)
    h.assert_equals(ordered_list[1]['text'], "A")
    h.assert_equals(ordered_list[1]['end'], 2)
    h.assert_equals(ordered_list[2]['text'], "B")
    h.assert_equals(ordered_list[3]['text'], "A")
    assert_subs_sorted(ordered_list)
end

local function test_insert_uses_recent_lookup_window()
    local subs = make_numbered_sub_list(0, 29)
    h.assert_equals(#subs.get_subs_list(), 30)
    h.assert_equals(subs.insert(Subtitle:from_text("Line 29", 29.04, 30.04)), false)
    h.assert_equals(subs.insert(Subtitle:from_text("Line 4", 4.04, 5.04)), true)
end

local function test_insert_preserves_sorted_order()
    local subs = make_numbered_sub_list(0, 29)
    h.assert_equals(subs.insert(Subtitle:from_text("Line 5.5", 5.5, 6.5)), true)
    local ordered_list = subs.get_subs_list()
    h.assert_equals(#ordered_list, 31)
    h.assert_equals(ordered_list[6]['text'], "Line 5")
    h.assert_equals(ordered_list[7]['text'], "Line 5.5")
    h.assert_equals(ordered_list[8]['text'], "Line 6")
    assert_subs_sorted(ordered_list)
end

local function test_get_time_returns_boundary_times()
    local subs = make_two_line_subs()
    h.assert_equals(subs.get_time('start'), 0)
    h.assert_equals(subs.get_time('end'), 5)
end

local function test_get_subs_list_returns_array_copy()
    local subs = make_two_line_subs()
    local copy = subs.get_subs_list()
    table.remove(copy, 1)
    h.assert_equals(#copy, 1)
    h.assert_equals(subs.get_text(), "First line\nSecond line")
    h.assert_equals(subs.get_subs_list()[1]['text'], "First line")
end

local function test_get_text()
    local first = Subtitle:from_text("First line", 0, 2)
    local expanded = Subtitle:from_text("First line\nSecond line", 1, 3)
    local subs = new_sub_list()
    subs.insert(first)
    subs.insert(expanded)
    h.assert_equals(subs.get_text(), "First line\nSecond line")

    -- The second sub is rejected by insert()'s event-level guard (same text and timing),
    -- so the list holds only one sub.
    local duplicate_subs = new_sub_list()
    duplicate_subs.insert(Subtitle:from_text("Same line", 0, 2))
    duplicate_subs.insert(Subtitle:from_text("Same line", 0.04, 2.04))
    h.assert_equals(duplicate_subs.get_text(), "Same line")

    local repeated_same_text_subs = new_sub_list()
    repeated_same_text_subs.insert(Subtitle:from_text("Same line", 0, 1))
    repeated_same_text_subs.insert(Subtitle:from_text("Same line", 3, 4))
    h.assert_equals(repeated_same_text_subs.get_text(), "Same line\nSame line")

    local repeated_event_subs = new_sub_list()
    repeated_event_subs.insert(Subtitle:from_text("Yes", 0, 1))
    repeated_event_subs.insert(Subtitle:from_text("No", 1, 2))
    repeated_event_subs.insert(Subtitle:from_text("Yes", 2, 3))
    h.assert_equals(repeated_event_subs.get_text(), "Yes\nNo\nYes")

    -- A repeated line outside the adjacent suffix/prefix boundary must be kept.
    -- The old global seen-set approach dropped the final "X" here.
    local repeated_subs = new_sub_list()
    repeated_subs.insert(Subtitle:from_text("X", 0, 1))
    repeated_subs.insert(Subtitle:from_text("Y", 1, 2))
    repeated_subs.insert(Subtitle:from_text("Y\nX", 2, 3))
    h.assert_equals(repeated_subs.get_text(), "X\nY\nX")

    local adjacent_overlap_subs = new_sub_list()
    adjacent_overlap_subs.insert(Subtitle:from_text("Yes\nNo", 0, 2))
    adjacent_overlap_subs.insert(Subtitle:from_text("No\nMaybe", 2, 4))
    h.assert_equals(adjacent_overlap_subs.get_text(), "Yes\nNo\nMaybe")

    local formatted_subs = new_sub_list()
    formatted_subs.insert(Subtitle:from_text("First line\n\nSecond line", 0, 2))
    h.assert_equals(formatted_subs.get_text(), "First line\n\nSecond line")

    -- Lines repeated within a single sub are kept as-is:
    -- dedup only applies at the boundary between consecutive subs.
    local within_subs = new_sub_list()
    within_subs.insert(Subtitle:from_text("A\nA", 0, 2))
    h.assert_equals(within_subs.get_text(), "A\nA")

    local crlf_subs = new_sub_list()
    crlf_subs.insert(Subtitle:from_text("First line\r\nSecond line\rThird line", 0, 2))
    h.assert_equals(crlf_subs.get_text(), "First line\nSecond line\nThird line")

    -- A trailing newline must not introduce a spurious blank line.
    local trailing_newline_subs = new_sub_list()
    trailing_newline_subs.insert(Subtitle:from_text("First line\nSecond line\n", 0, 2))
    h.assert_equals(trailing_newline_subs.get_text(), "First line\nSecond line")
end

local function test_get_n_text()
    local first = Subtitle:from_text("First line", 0, 2)
    local subs = new_sub_list()
    subs.insert(first)
    subs.insert(Subtitle:from_text("First line\nSecond line", 1, 3))
    h.assert_equals(subs.get_n_text(first, 2), "First line\nSecond line")

    local limited_subs = new_sub_list()
    limited_subs.insert(Subtitle:from_text("First line", 0, 2))
    limited_subs.insert(Subtitle:from_text("First line\nSecond line", 1, 3))
    limited_subs.insert(Subtitle:from_text("Second line\nThird line", 2, 4))
    h.assert_equals(limited_subs.get_n_text(first, 2), "First line\nSecond line")

    -- Non-adjacent repeated lines are kept in get_n_text too.
    local repeated_subs = new_sub_list()
    repeated_subs.insert(Subtitle:from_text("Yes", 0, 1))
    repeated_subs.insert(Subtitle:from_text("No", 1, 2))
    repeated_subs.insert(Subtitle:from_text("Yes\nAgain", 2, 3))
    h.assert_equals(repeated_subs.get_n_text(repeated_subs.get_subs_list()[1], 3), "Yes\nNo\nYes\nAgain")

    -- A sub fully covered by the previous suffix still counts toward n_lines,
    -- so end_sub (used for the card's end timing) advances past it.
    local covered_subs = new_sub_list()
    local container = Subtitle:from_text("A\nB", 0, 2)
    covered_subs.insert(container)
    covered_subs.insert(Subtitle:from_text("B", 1, 3))
    covered_subs.insert(Subtitle:from_text("C", 2, 4))
    local text, end_sub = covered_subs.get_n_text(container, 2)
    h.assert_equals(text, "A\nB")
    h.assert_equals(end_sub['end'], 3)
end

local function test_get_overlapping_text_uses_timing_and_removes_line_overlap()
    local subs = new_sub_list()
    subs.insert(Subtitle:from_text("Before", 0, 1))
    subs.insert(Subtitle:from_text("First line", 1, 2))
    subs.insert(Subtitle:from_text("First line\nSecond line", 2, 3))
    subs.insert(Subtitle:from_text("After", 3, 4))
    h.assert_equals(subs.get_overlapping_text(1, 3), "First line Second line")
end

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
    test_get_n_text()
    test_get_overlapping_text_uses_timing_and_removes_line_overlap()
end

return {
    new = new_sub_list,
    run_tests = run_tests,
}
