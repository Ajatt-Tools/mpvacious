--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Loads every cue from the active secondary subtitle track.
]]

local h = require('helpers')
local exec = require('encoder.executables')
local Subtitle = require('subtitles.subtitle')
local sub_list = require('subtitles.sub_list')
local msg = require('mp.msg')

local self = {}

local function parse_time(value)
    local hours, minutes, seconds, fraction = value:match('^(%d+):(%d+):(%d+)[,.](%d+)$')
    if not hours then
        return nil
    end
    return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)
            + tonumber(fraction) / (10 ^ #fraction)
end

function self.parse_srt(text)
    local subs = sub_list.new()
    text = (text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')

    for block in (text .. '\n\n'):gmatch('(.-)\n\n+') do
        local lines = {}
        for line in block:gmatch('[^\n]+') do
            table.insert(lines, line)
        end

        local timing_index, start_time, end_time
        for index, line in ipairs(lines) do
            local start_value, end_value = line:match('^%s*(%d+:%d+:%d+[,.]%d+)%s+%-%->%s+(%d+:%d+:%d+[,.]%d+)')
            if start_value then
                timing_index = index
                start_time = parse_time(start_value)
                end_time = parse_time(end_value)
                break
            end
        end

        if timing_index and start_time and end_time then
            local cue_lines = {}
            for index = timing_index + 1, #lines do
                table.insert(cue_lines, (lines[index]:gsub('<[^>]*>', '')))
            end
            subs.insert(Subtitle:from_text(table.concat(cue_lines, '\n'), start_time, end_time))
        end
    end

    return subs
end

local function split_ass_fields(value, count)
    local fields = {}
    local start_index = 1
    for index = 1, count - 1 do
        local comma_index = value:find(',', start_index, true)
        if not comma_index then
            return nil
        end
        fields[index] = h.trim(value:sub(start_index, comma_index - 1))
        start_index = comma_index + 1
    end
    fields[count] = h.trim(value:sub(start_index))
    return fields
end

function self.parse_ass(text)
    local subs = sub_list.new()
    local format
    local in_events = false
    text = (text or ''):gsub('^\239\187\191', ''):gsub('\r\n', '\n'):gsub('\r', '\n')

    for line in text:gmatch('[^\n]+') do
        local section = line:match('^%s*(%b[])')
        if section then
            in_events = section:lower() == '[events]'
        elseif in_events then
            local name, value = line:match('^%s*([^:]+):%s*(.*)$')
            name = name and name:lower()
            if name == 'format' then
                format = {}
                for field in value:gmatch('[^,]+') do
                    table.insert(format, h.trim(field):lower())
                end
            elseif name == 'dialogue' and format then
                local fields = split_ass_fields(value, #format)
                local event = {}
                for index, field_name in ipairs(format) do
                    event[field_name] = fields and fields[index]
                end
                local start_time = event.start and parse_time(event.start)
                local end_time = event['end'] and parse_time(event['end'])
                if start_time and end_time and event.text then
                    local cue_text = event.text:gsub('{[^}]*}', '')
                            :gsub('\\[Nn]', '\n')
                            :gsub('\\h', ' ')
                    subs.insert(Subtitle:from_text(cue_text, start_time, end_time))
                end
            end
        end
    end

    return subs
end

local function read_file(path)
    local file = io.open(path, 'rb')
    if not file then
        return nil
    end
    local contents = file:read('*a')
    file:close()
    return contents
end

function self.new(run_subprocess, read_subtitle_file)
    run_subprocess = run_subprocess or h.subprocess
    read_subtitle_file = read_subtitle_file or read_file
    local active_key
    local generation = 0
    local loaded_subs

    local function refresh(track_list, media_path)
        local secondary_track
        for _, track in ipairs(track_list or {}) do
            if track.type == 'sub' and track['main-selection'] == 1 then
                secondary_track = track
                break
            end
        end

        local input = secondary_track and (secondary_track['external-filename'] or media_path)
        local ff_index = secondary_track and secondary_track['ff-index']
        local new_key = input and ff_index and (input .. '\0' .. ff_index) or nil
        if new_key == active_key then
            return
        end

        active_key = new_key
        generation = generation + 1
        loaded_subs = nil
        if not new_key then
            return
        end

        local external_filename = secondary_track['external-filename']
        if external_filename then
            local extension = external_filename:lower():match('%.([^./]+)$')
            local parser = extension == 'srt' and self.parse_srt
                    or (extension == 'ass' or extension == 'ssa') and self.parse_ass
            local contents = parser and read_subtitle_file(external_filename)
            if contents then
                loaded_subs = parser(contents)
            else
                msg.warn('Could not read the complete external secondary subtitle track; using observed cues.')
            end
            return
        end

        local request_generation = generation
        run_subprocess {
            args = {
                exec.ffmpeg, '-v', 'error', '-nostdin', '-i', input,
                '-map', '0:' .. ff_index, '-f', 'srt', '-',
            },
            suppress_log = true,
            completion_fn = function(success, result, error)
                if request_generation ~= generation then
                    return
                end
                if success == true and error == nil and result and result.status == 0 then
                    loaded_subs = self.parse_srt(result.stdout)
                else
                    msg.warn('Could not load the complete secondary subtitle track; using observed cues.')
                end
            end,
        }
    end

    local function get_overlapping_text(start_time, end_time, delay)
        if not loaded_subs then
            return nil
        end
        delay = delay or 0
        return loaded_subs.get_overlapping_text(start_time - delay, end_time - delay)
    end

    return {
        refresh = refresh,
        get_overlapping_text = get_overlapping_text,
    }
end

local function test_parse_srt_returns_timed_plain_text()
    local subs = self.parse_srt([[
1
00:00:01,000 --> 00:00:02,500
<i>First line</i>

2
00:00:02.750 --> 00:00:05,000
Second line
]])
    h.assert_equals(subs.get_overlapping_text(1, 5), 'First line Second line')
end

local function test_parse_ass_returns_timed_plain_text()
    local subs = self.parse_ass([[
[Script Info]
Title: Test

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:01.00,0:00:02.50,Default,{\i1}First line{\i0}
Dialogue: 0,0:00:02.75,0:00:05.00,Default,Second\Nline
]])
    h.assert_equals(subs.get_overlapping_text(1, 5), 'First line Second line')
end

local function test_cache_extracts_selected_secondary_track()
    local request
    local cache = self.new(function(options)
        request = options
    end)
    cache.refresh({
        { type = 'sub', ['main-selection'] = 0, ['ff-index'] = 2 },
        { type = 'sub', ['main-selection'] = 1, ['ff-index'] = 3 },
    }, '/video.mkv')

    h.assert_equals(cache.get_overlapping_text(1, 5, 0), nil)
    table.remove(request.args, 1) -- executable path is platform-specific
    h.assert_equals(request.args, {
        '-v', 'error', '-nostdin', '-i', '/video.mkv',
        '-map', '0:3', '-f', 'srt', '-',
    })

    request.completion_fn(true, {
        status = 0,
        stdout = '1\n00:00:01,000 --> 00:00:05,000\nFuture line\n',
        stderr = '',
    }, nil)
    h.assert_equals(cache.get_overlapping_text(1, 5, 0), 'Future line')
end

local function test_cache_reads_external_text_subtitles_without_subprocess()
    local cases = {
        {
            path = '/subtitles/english.ass',
            contents = [[
[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:01.00,0:00:05.00,Default,Future line
]],
        },
        {
            path = '/subtitles/english.srt',
            contents = '1\n00:00:01,000 --> 00:00:05,000\nFuture line\n',
        },
    }

    for _, case in ipairs(cases) do
        local subprocess_called = false
        local cache = self.new(function()
            subprocess_called = true
        end, function(path)
            h.assert_equals(path, case.path)
            return case.contents
        end)
        cache.refresh({
            {
                type = 'sub',
                ['main-selection'] = 1,
                ['ff-index'] = 0,
                ['external-filename'] = case.path,
            },
        }, '/video.mkv')

        h.assert_equals(cache.get_overlapping_text(1, 5, 0), 'Future line')
        h.assert_equals(subprocess_called, false)
    end
end

local function test_cache_applies_delay()
    local request
    local cache = self.new(function(options)
        request = options
    end)
    cache.refresh({
        {
            type = 'sub',
            ['main-selection'] = 1,
            ['ff-index'] = 0,
        },
    }, '/video.mkv')

    h.assert_equals(request.args[6], '/video.mkv')
    request.completion_fn(true, {
        status = 0,
        stdout = '1\n00:00:01,000 --> 00:00:02,000\nDelayed line\n',
        stderr = '',
    }, nil)
    h.assert_equals(cache.get_overlapping_text(2, 3, 1), 'Delayed line')
end

local function test_cache_ignores_results_from_previous_track()
    local requests = {}
    local cache = self.new(function(options)
        table.insert(requests, options)
    end)
    local function track()
        return {
            {
                type = 'sub',
                ['main-selection'] = 1,
                ['ff-index'] = 0,
            },
        }
    end

    cache.refresh(track(), '/first.mkv')
    cache.refresh(track(), '/second.mkv')
    requests[1].completion_fn(true, {
        status = 0,
        stdout = '1\n00:00:01,000 --> 00:00:02,000\nStale line\n',
        stderr = '',
    }, nil)
    h.assert_equals(cache.get_overlapping_text(1, 2, 0), nil)

    requests[2].completion_fn(true, {
        status = 0,
        stdout = '1\n00:00:01,000 --> 00:00:02,000\nCurrent line\n',
        stderr = '',
    }, nil)
    h.assert_equals(cache.get_overlapping_text(1, 2, 0), 'Current line')
end

function self.run_tests()
    test_parse_srt_returns_timed_plain_text()
    test_parse_ass_returns_timed_plain_text()
    test_cache_extracts_selected_secondary_track()
    test_cache_reads_external_text_subtitles_without_subprocess()
    test_cache_applies_delay()
    test_cache_ignores_results_from_previous_track()
end

return self
