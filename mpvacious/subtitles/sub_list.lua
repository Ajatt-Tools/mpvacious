--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle list remembers selected subtitle lines.
]]

local h = require('helpers')
local Subtitle = require('subtitles.subtitle')
local CONCAT_CHR = '\n' -- character used to concatenate subtitle lines
local LOOKUP_WINDOW_SIZE = 25 -- how many recent subs to scan for duplicate events
local MAX_SUB_GAP_SECONDS = 20 -- stop joining lines separated by a longer gap

local new_sub_list = function()
    local subs_list = {}

    local get_time = function(position)
        local i = position == 'start' and 1 or #subs_list
        return subs_list[i][position]
    end
    local get_text = function()
        local speech = {}
        for _, sub in ipairs(subs_list) do
            table.insert(speech, sub['text'])
        end
        return table.concat(speech, CONCAT_CHR)
    end
    local get_n_text = function(sub, n_lines)
        local speech = {}
        local end_sub = sub
        for _, v in ipairs(subs_list) do
            if v['start'] - end_sub['end'] >= MAX_SUB_GAP_SECONDS then
                break
            end
            if v >= sub and #speech < n_lines then
                table.insert(speech, v['text'])
                end_sub = v
            end
        end
        return table.concat(speech, CONCAT_CHR), end_sub
    end
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
    local previous = nil
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
end

return {
    new = new_sub_list,
    run_tests = run_tests,
}
