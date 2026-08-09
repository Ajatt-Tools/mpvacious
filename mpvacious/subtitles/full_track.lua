--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Loads every cue from the active secondary subtitle track.
]]

local h = require('helpers')
local exec = require('encoder.executables')
local Subtitle = require('subtitles.subtitle')
local sub_list = require('subtitles.sub_list')

local this = {}

local function parse_time(value)
    local hours, minutes, seconds, fraction = value:match('^(%d+):(%d+):(%d+)[,.](%d+)$')
    if not hours then
        return nil
    end
    return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)
            + tonumber(fraction) / (10 ^ #fraction)
end

function this.parse_srt(text)
    local subs = sub_list.new()
    text = (text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
    for block in (text .. '\n\n'):gmatch('(.-)\n\n+') do
        local start_value, end_value = block:match('(%d+:%d+:%d+[,.]%d+)%s+%-%->%s+(%d+:%d+:%d+[,.]%d+)')
        local cue_text = block:match('%-%->[^\n]+\n(.+)$')
        local start_time, end_time = parse_time(start_value or ''), parse_time(end_value or '')
        if start_time and end_time and cue_text then
            cue_text = cue_text:gsub('<[^>]*>', '')
            subs.insert(Subtitle:from_text(cue_text, start_time, end_time))
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
        fields[index] = h.remove_leading_trailing_spaces(value:sub(start_index, comma_index - 1))
        start_index = comma_index + 1
    end
    fields[count] = h.remove_leading_trailing_spaces(value:sub(start_index))
    return fields
end

function this.parse_ass(text)
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
                    table.insert(format, h.remove_leading_trailing_spaces(field):lower())
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
                    local cue_text = event.text:gsub('{[^}]*}', ''):gsub('\\[Nn]', '\n'):gsub('\\h', ' ')
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

function this.new(run_subprocess, read_subtitle_file)
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

        local external_filename = secondary_track and secondary_track['external-filename']
        if external_filename then
            local extension = external_filename:lower():match('%.([^./]+)$')
            local parser = extension == 'srt' and this.parse_srt
                    or (extension == 'ass' or extension == 'ssa') and this.parse_ass
            local contents = parser and read_subtitle_file(external_filename)
            if contents then
                loaded_subs = parser(contents)
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
                    loaded_subs = this.parse_srt(result.stdout)
                end
            end,
        }
    end

    local function get_overlapping_text(window, delay)
        if not loaded_subs then
            return nil
        end
        delay = delay or 0
        local shifted = Subtitle:from_text('', window.start - delay, window['end'] - delay)
        return loaded_subs.get_overlapping_text(shifted)
    end

    return {
        refresh = refresh,
        get_overlapping_text = get_overlapping_text,
    }
end

local function test_parse_srt_returns_timed_text()
    local subs = this.parse_srt([[
1
00:00:01,000 --> 00:00:02,500
<i>First line</i>

2
00:00:02,750 --> 00:00:05,000
Second line
]])
    local window = Subtitle:from_text('', 1, 5)
    h.assert_equals(subs.get_overlapping_text(window), 'First line Second line')
end

local function test_parse_ass_returns_timed_plain_text()
    local subs = this.parse_ass([[
[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:01.00,0:00:02.50,Default,{\i1}First, line{\i0}
Dialogue: 0,0:00:02.75,0:00:05.00,Default,Second\Nline
]])
    local window = Subtitle:from_text('', 1, 5)
    h.assert_equals(subs.get_overlapping_text(window), 'First, line Second line')
end

local function selected_external_track(filename)
    return {
        type = 'sub',
        ['main-selection'] = 1,
        ['external-filename'] = filename,
        ['ff-index'] = 2,
    }
end

local function test_cache_reads_external_track_without_subprocess()
    local subprocess_called = false
    local cache = this.new(function()
        subprocess_called = true
    end, function(path)
        h.assert_equals(path, '/subs.srt')
        return [[
1
00:00:01,000 --> 00:00:05,000
Cached line
]]
    end)
    cache.refresh({ selected_external_track('/subs.srt') }, '/video.mkv')
    h.assert_equals(subprocess_called, false)
    h.assert_equals(cache.get_overlapping_text(Subtitle:from_text('', 1, 5), 0), 'Cached line')
end

local function test_cache_loads_embedded_track_asynchronously()
    local request
    local cache = this.new(function(options)
        request = options
    end)
    cache.refresh({ {
        type = 'sub',
        ['main-selection'] = 1,
        ['ff-index'] = 3,
    } }, '/video.mkv')
    local window = Subtitle:from_text('', 1, 5)
    h.assert_equals(cache.get_overlapping_text(window, 0), nil)
    request.completion_fn(true, {
        status = 0,
        stdout = '1\n00:00:01,000 --> 00:00:05,000\nEmbedded line\n',
    }, nil)
    h.assert_equals(cache.get_overlapping_text(window, 0), 'Embedded line')
end

local function test_cache_applies_subtitle_delay()
    local cache = this.new(function()
        error('external track must not run a subprocess')
    end, function()
        return '1\n00:00:01,000 --> 00:00:02,000\nDelayed line\n'
    end)
    cache.refresh({ selected_external_track('/subs.srt') }, '/video.mkv')
    local displayed_window = Subtitle:from_text('', 2, 3)
    h.assert_equals(cache.get_overlapping_text(displayed_window, 1), 'Delayed line')
end

local function test_cache_ignores_stale_embedded_track_result()
    local requests = {}
    local cache = this.new(function(options)
        table.insert(requests, options)
    end)
    local function embedded_track(ff_index)
        return { type = 'sub', ['main-selection'] = 1, ['ff-index'] = ff_index }
    end
    cache.refresh({ embedded_track(2) }, '/first.mkv')
    cache.refresh({ embedded_track(3) }, '/second.mkv')
    requests[1].completion_fn(true, {
        status = 0,
        stdout = '1\n00:00:01,000 --> 00:00:02,000\nStale line\n',
    }, nil)
    h.assert_equals(cache.get_overlapping_text(Subtitle:from_text('', 1, 2), 0), nil)
end

function this.run_tests()
    test_parse_srt_returns_timed_text()
    test_parse_ass_returns_timed_plain_text()
    test_cache_reads_external_track_without_subprocess()
    test_cache_loads_embedded_track_asynchronously()
    test_cache_applies_subtitle_delay()
    test_cache_ignores_stale_embedded_track_result()
end

return this
