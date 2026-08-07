--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Collect subtitle lines into a joined speech.
]]

local h = require('helpers')
local Subtitle = require('subtitles.subtitle')
local this = {}
local CONCAT_CHR = '\n' -- character used to concatenate subtitle lines

--- Split text into individual lines, normalized to LF.
--- Empty lines are preserved so intentional subtitle formatting survives joining.
local function normalized_lines(text)
    local lines = {}
    local normalized_text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    -- Matches zero or more characters followed by a newline.
    -- Keep empty lines so intentional subtitle formatting survives joining.
    for line in (normalized_text .. '\n'):gmatch('(.-)\n') do
        table.insert(lines, line)
    end
    -- Splitting works by appending a newline, so text that already ends with one
    -- would produce an extra empty line unless we remove it here.
    if normalized_text:sub(-1) == '\n' then
        lines[#lines] = nil
    end
    return lines
end

--- Return true when two subtitle events overlap or touch in time.
--- The collector assumes subtitles are appended in sorted order.
local function do_subs_overlap_in_time(previous_sub, current_sub)
    return previous_sub and current_sub and previous_sub['end'] >= current_sub['start']
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
        if h.list_equal(h.itable_slice(recorded_lines, -overlap_size), h.itable_slice(lines_to_append, 1, overlap_size)) then
            return overlap_size
        end
    end
    return 0
end

--- Collect subtitle lines into a joined speech, removing boundary overlap
--- between consecutive time-overlapping or touching subs.
function this.make_speech_collector()
    local self = {}
    local recorded_lines = {}
    local previous_sub -- store last recorded sub (with timings, unlike recorded_lines)

    --- Append a sub's lines to speech, skipping leading lines that duplicate
    --- the trailing lines of speech. Skipping applies only when the two subs
    --- overlap or touch in time; a repeated line after a gap is kept as separate dialogue.
    function self.append_sub(sub)
        local lines_to_append = normalized_lines(sub['text'])
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

local function test_count_overlapping_lines()
    local cases = {
        -- {recorded_lines, lines_to_append, expected}
        { { "Yes", "No" }, { "No", "Maybe" }, 1 }, -- one shared boundary line
        { { "A", "B", "C" }, { "B", "C", "D" }, 2 }, -- multi-line boundary overlap
        { { "A", "B" }, { "A", "B" }, 2 }, -- full overlap
        { { "A", "B", "C", "D" }, { "C", "D" }, 2 }, -- bounded by the shorter list
        { { "X", "A", "B" }, { "A", "B", "C" }, 2 }, -- larger candidate fails, smaller matches
        { { "A", "B" }, { "C", "D" }, 0 }, -- no overlap
        { {}, { "A" }, 0 }, -- empty recorded_lines
        { { "A" }, {}, 0 }, -- empty lines_to_append
        { {}, {}, 0 }, -- both empty
        { { "A", "B", "C" }, { "A", "D" }, 0 }, -- "A" is in recorded_lines but not at the boundary
        { { "B" }, { "A", "B" }, 0 }, -- "B" ends recorded_lines but doesn't start lines_to_append
        { { "a" }, { "A" }, 0 }, -- exact (case-sensitive) match
    }
    for _, case in ipairs(cases) do
        local recorded_lines, lines_to_append, expected = h.unpack(case)
        h.assert_equals(count_overlapping_lines(recorded_lines, lines_to_append), expected)
    end
end

local function test_speech_collector_removes_boundary_overlap()
    local collector = this.make_speech_collector()
    collector.append_sub(Subtitle:from_text("First line", 0, 1))
    collector.append_sub(Subtitle:from_text("First line\nSecond line", 1, 2))
    h.assert_equals(collector.get_all_as_string(), "First line\nSecond line")
end

local function test_speech_collector_keeps_repeated_text_after_gap()
    local collector = this.make_speech_collector()
    collector.append_sub(Subtitle:from_text("Same line", 0, 1))
    collector.append_sub(Subtitle:from_text("Same line", 2, 3))
    h.assert_equals(collector.get_all_as_string(), "Same line\nSame line")
end

local function test_speech_collector_normalizes_newlines()
    local collector = this.make_speech_collector()
    collector.append_sub(Subtitle:from_text("First line\r\nSecond line\rThird line", 0, 1))
    h.assert_equals(collector.get_all_as_string(), "First line\nSecond line\nThird line")
end

local function test_speech_collector_preserves_empty_lines()
    local collector = this.make_speech_collector()
    collector.append_sub(Subtitle:from_text("First line\n\nSecond line", 0, 1))
    h.assert_equals(collector.get_all_as_string(), "First line\n\nSecond line")
end

local function test_speech_collector_drops_trailing_newline()
    local collector = this.make_speech_collector()
    collector.append_sub(Subtitle:from_text("First line\nSecond line\n", 0, 1))
    h.assert_equals(collector.get_all_as_string(), "First line\nSecond line")
end

function this.run_tests()
    test_count_overlapping_lines()
    test_speech_collector_removes_boundary_overlap()
    test_speech_collector_keeps_repeated_text_after_gap()
    test_speech_collector_normalizes_newlines()
    test_speech_collector_preserves_empty_lines()
    test_speech_collector_drops_trailing_newline()
end

return this
