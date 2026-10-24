--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle list remembers selected subtitle lines.
]]

local h = require("helpers")
local subtitle = require("subtitles.subtitle")
local speech_collector = require("subtitles.collector")
local LOOKUP_WINDOW_SIZE = 25 -- how many recent subs to scan for duplicate events
local MAX_SUB_GAP_SECONDS = 20 -- stop joining lines separated by a longer gap
local SHORT_SUB_SECONDS = 1
local MIN_SUB_OVERLAP_RATIO = 0.5
local MIN_SHORT_SUB_OVERLAP_RATIO = 0.75

--- Collapse whitespace in collected subtitle text.
local function flatten_subtitle_text(text)
    return h.remove_leading_trailing_spaces(h.collapse_whitespace(text))
end

--- Return the minimum overlap ratio for the shorter subtitle.
local function required_overlap_ratio(shorter_duration)
    if shorter_duration < SHORT_SUB_SECONDS then
        return MIN_SHORT_SUB_OVERLAP_RATIO
    end
    return MIN_SUB_OVERLAP_RATIO
end

--- Check that two subtitle windows overlap beyond timing noise.
local function overlaps_enough(sub, window)
    local shorter_duration = math.min(sub:duration(), window:duration())
    return shorter_duration > 0
        and sub:overlap_duration(window) >= shorter_duration * required_overlap_ratio(shorter_duration)
end

--- Create an ordered collection of selected subtitles.
local function make_sub_list()
    local subs_list = {}
    local public = {}

    --- Return the start or end time of the selected subtitles.
    function public.get_time(position)
        if position == "start" then
            return subs_list[1][position]
        end
        return subs_list[#subs_list][position]
    end

    --- Return collected subtitle text with adjacent boundary lines deduplicated.
    function public.get_text()
        -- Dedup applies to every list (primary, secondary), collapsing adjacent
        -- multiline sub expansions into one continuous dialog string.
        local collector = speech_collector.new()
        for _, sub in ipairs(subs_list) do
            collector.append_sub(sub)
        end
        return collector.get_all_as_string()
    end

    --- Collect up to n_subs subtitles starting from start_sub and return them as one Subtitle
    --- spanning from start_sub's start to the last collected subtitle's end. Collection stops
    --- early at the first gap of MAX_SUB_GAP_SECONDS or more between consecutive subtitles.
    --- Text is joined by the speech collector, which removes boundary line overlap
    --- between consecutive time-overlapping subtitles.
    function public.collect_n_subs(start_sub, n_subs)
        local collector = speech_collector.new()
        local end_sub = start_sub
        local collected_count = 0
        for _, sub in ipairs(subs_list) do
            if sub["start"] - end_sub["end"] >= MAX_SUB_GAP_SECONDS then
                break
            end
            if not (sub < start_sub) and collected_count < n_subs then
                collector.append_sub(sub)
                end_sub = sub
                collected_count = collected_count + 1
            end
        end
        return subtitle.make_subtitle(collector.get_all_as_string(), start_sub["start"], end_sub["end"])
    end

    --- Return the text of all subs overlapping the given time window, as one line.
    --- Used to align secondary (translation) text with the primary text's time span:
    --- primary and secondary subtitles have independent timings, so collecting secondary
    --- text by line count or by the currently visible subtitle would misalign it with the
    --- primary text. Small boundary intersections are treated as timing noise.
    --- Boundary overlap between consecutive subtitles is removed by the speech collector,
    --- and the result is flattened to a single whitespace-collapsed, trimmed line.
    --- `window` is the selected primary Subtitle. Normal subtitles must overlap at least
    --- half of the shorter subtitle. Subtitles shorter than one second must overlap by 75%.
    function public.get_overlapping_text(window)
        local collector = speech_collector.new()
        for _, sub in ipairs(subs_list) do
            if overlaps_enough(sub, window) then
                collector.append_sub(sub)
            end
        end
        return flatten_subtitle_text(collector.get_all_as_string())
    end

    --- Event-level guard and expansion.
    --- The same sub event is offered repeatedly (on every sub change and on
    --- every collect call); exact duplicates (same text and timing) are skipped.
    --- An adjacent same-text event (overlapping or touching in time) expands
    --- the last recorded sub's end time.
    --- Text-overlap cleanup for multiline expansion is intentionally delayed
    --- until get_text()/collect_n_subs(), where the selected output window is known.
    --- Insert a subtitle, skipping duplicate events and expanding adjacent ones.
    function public.insert(sub)
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

    --- Return a detached list of the collected subtitle objects.
    function public.get_subs_list()
        -- Return a shallow copy so callers can't mutate the internal list.
        local copy = {}
        for key, value in pairs(subs_list) do
            copy[key] = value
        end
        return copy
    end

    --- Report whether any subtitles have been collected.
    function public.is_empty()
        return h.is_empty(subs_list)
    end

    return public
end

return {
    new = make_sub_list,
    overlaps_enough = overlaps_enough,
}
