--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Collect subtitle lines into a joined speech.
]]

local h = require("helpers")
local CONCAT_CHR = "\n" -- character used to concatenate subtitle lines

--- Split text into individual lines, normalized to LF.
--- Empty lines are preserved so intentional subtitle formatting survives joining.
local function normalized_lines(text)
    local normalized_text = h.normalize_newlines(text)
    local lines = h.split_lines(normalized_text)
    -- Splitting works by appending a newline, so text that already ends with one
    -- would produce an extra empty line unless we remove it here.
    if normalized_text:sub(-1) == "\n" then
        lines[#lines] = nil
    end
    return lines
end

--- Return true when two subtitle events overlap or touch in time.
--- The collector assumes subtitles are appended in sorted order.
local function do_subs_overlap_in_time(previous_sub, current_sub)
    return previous_sub and current_sub and previous_sub:overlaps_or_touches_in_time(current_sub)
end

--- Return how many lines at the end of recorded_lines are repeated at the start of lines_to_append.
--- Only the boundary between the two lists is considered: a line repeated anywhere else does not count.
local function count_overlapping_lines(recorded_lines, lines_to_append)
    -- Start with the largest possible overlap (bounded by the shorter list)
    -- and shrink it until the boundary lines match (or nothing is left).
    local max_overlap = math.min(#recorded_lines, #lines_to_append)
    for overlap_size = max_overlap, 1, -1 do
        -- Compare the last overlap_size lines of recorded_lines
        -- with the first overlap_size lines of lines_to_append.
        if
            h.list_equal(
                h.itable_slice(recorded_lines, -overlap_size),
                h.itable_slice(lines_to_append, 1, overlap_size)
            )
        then
            return overlap_size
        end
    end
    return 0
end

--- Collect subtitle lines into a joined speech, removing boundary overlap
--- between consecutive time-overlapping or touching subs.
local function make_speech_collector()
    local self = {}
    local recorded_lines = {}
    local previous_sub -- store last recorded sub (with timings, unlike recorded_lines)

    --- Append a sub's lines to speech, skipping leading lines that duplicate
    --- the trailing lines of speech. Skipping applies only when the two subs
    --- overlap or touch in time; a repeated line after a gap is kept as separate dialogue.
    function self.append_sub(sub)
        local lines_to_append = normalized_lines(sub["text"])
        local n_lines_to_skip = 0
        if do_subs_overlap_in_time(previous_sub, sub) then
            n_lines_to_skip = count_overlapping_lines(recorded_lines, lines_to_append)
        end
        for i = n_lines_to_skip + 1, #lines_to_append do
            table.insert(recorded_lines, lines_to_append[i])
        end
        previous_sub = sub
    end

    --- Return all collected lines joined with the subtitle line separator.
    function self.get_all_as_string()
        return table.concat(recorded_lines, CONCAT_CHR)
    end

    return self
end

return {
    new = make_speech_collector,
    count_overlapping_lines = count_overlapping_lines,
}
