--[[
Copyright (C) 2020 Ren Tatsumoto

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

Requirements:
* mpv >= 0.32.0
* AnkiConnect
* curl
* xclip

Usage:
1. Change `config` according to your needs
* Options can be changed right in this file or in a separate config file.
* Config path: ~/.config/mpv/script-opts/subs2srs.conf
* Config file isn't created automatically.

2. Open a video

3. Use key bindings to manipulate the script
* Open mpvacious menu - `a`
* Create a note from the current subtitle line - `Ctrl + e`

For complete usage guide, see <https://github.com/Ajatt-Tools/mpvacious/blob/master/README.md>
]]

local config = {
    collection_path = "",       -- full path to the collection. most users should leave it empty.
    anki_user = "User 1",       -- your anki username. it is displayed on the title bar of the Anki window.
    autoclip = false,           -- copy subs to the clipboard or not
    nuke_spaces = true,         -- remove all spaces or not
    snapshot_format = "webp",   -- webp or jpg
    snapshot_quality = 5,       -- from 0=lowest to 100=highest
    snapshot_width = -2,        -- a positive integer or -2 for auto
    snapshot_height = 200,      -- same
    audio_format = "opus",      -- opus or mp3
    audio_bitrate = "18k",      -- from 16k to 32k
    audio_padding = 0.0,        -- Set a pad to the dialog timings. 0.5 = audio is padded by .5 seconds. 0 = disable.
    deck_name = "Learning",     -- the deck will be created if needed
    model_name = "Japanese sentences", -- Tools -> Manage note types
    sentence_field = "SentKanji",
    audio_field = "SentAudio",
    use_forvo = "yes",                  -- 'yes', 'no', 'always'
    vocab_field = "VocabKanji",         -- target word field
    vocab_audio_field = "VocabAudio",   -- target word audio
    image_field = "Image",
    menu_font_size = 25,
    note_tag = "subs2srs",      -- the tag that is added to new notes. change to "" to disable tagging
    tie_volumes = false,        -- if set to true, the volume of the outputted audio file depends on the volume of the player at the time of export
}

local utils = require('mp.utils')
local msg = require('mp.msg')
local mpopt = require('mp.options')

mpopt.read_options(config, "subs2srs")

-- namespaces
local subs
local clip_autocopy
local encoder
local ankiconnect
local menu
local platform

-- classes
local Subtitle
local OSD

------------------------------------------------------------
-- utility functions

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

function table.max_num(table)
    local max = table[1]
    for _, value in ipairs(table) do
        if value > max then
            max = value
        end
    end
    return max
end

local function is_empty(var)
    return var == nil or var == '' or (type(var) == 'table' and next(var) == nil)
end

local function is_running_windows()
    return mp.get_property('options/vo-mmcss-profile') ~= nil
end

local function is_running_macOS()
    return mp.get_property('options/cocoa-force-dedicated-gpu') ~= nil
end

local function is_dir(path)
    if is_empty(path) then
        return false
    end
    local file_info = utils.file_info(path)
    if file_info == nil then
        return false
    end
    return file_info.is_dir == true
end

local function capitalize_first_letter(string)
    return string:gsub("^%l", string.upper)
end

local function notify(message, level, duration)
    level = level or 'info'
    duration = duration or 1
    msg[level](message)
    mp.osd_message(message, duration)
end

local function remove_extension(filename)
    return filename:gsub('%.%w+$', '')
end

local function remove_special_characters(str)
    return str:gsub('[%c%p%s]', ''):gsub('　', '')
end

local function remove_text_in_brackets(str)
    return str:gsub('%b[]', ''):gsub('【.-】', '')
end

local function remove_text_in_parentheses(str)
    -- Remove text like （泣き声） or （ドアの開く音）
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub('%b()', ''):gsub('（.-）', '')
end

local function remove_newlines(str)
    return str:gsub('[\n\r]+', ' ')
end

local function remove_leading_trailing_spaces(str)
    return str:gsub('^%s*(.-)%s*$', '%1')
end

local function remove_all_spaces(str)
    return str:gsub('%s*', '')
end

local function escape_apostrophes(str)
    return str:gsub("'", "&apos;")
end

local function escape_quotes(str)
    return str:gsub('"', '&quot;')
end

local function contains_non_latin_letters(str)
    return str:match("[^%c%p%s%w]")
end

local function trim(str)
    str = remove_text_in_parentheses(str)
    str = remove_newlines(str)
    str = escape_apostrophes(str)
    str = escape_quotes(str)

    if config.nuke_spaces == true and contains_non_latin_letters(str) then
        str = remove_all_spaces(str)
    else
        str = remove_leading_trailing_spaces(str)
    end

    return str
end

local base64d -- http://lua-users.org/wiki/BaseSixtyFour
do
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    base64d = function(data)
        data = string.gsub(data, '[^'..b..'=]', '')
        return (data:gsub('.', function(x)
            if (x == '=') then return '' end
            local r,f='',(b:find(x)-1)
            for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
            return r;
        end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
            if (#x ~= 8) then return '' end
            local c=0
            for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
            return string.char(c)
        end))
    end
end

local function url_encode(url) -- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w _%%%-%.~])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

local function copy_sub_to_clipboard()
    platform.copy_to_clipboard("copy-on-demand", mp.get_property("sub-text"))
end

local function human_readable_time(seconds)
    if type(seconds) ~= 'number' or seconds < 0 then
        return 'empty'
    end

    local parts = {
        h = math.floor(seconds / 3600),
        m = math.floor(seconds / 60) % 60,
        s = math.floor(seconds % 60),
        ms = math.floor((seconds * 1000) % 1000),
    }

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format('%dh%s', parts.h, ret)
    end

    return ret
end

local function subprocess(args, completion_fn)
    -- if `completion_fn` is passed, the command is ran asynchronously,
    -- and upon completion, `completion_fn` is called to process the results.
    local command_native = type(completion_fn) == 'function' and mp.command_native_async or mp.command_native
    local command_table = {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = args
    }
    return command_native(command_table, completion_fn)
end

local anki_compatible_length
do
    -- Anki forcibly mutilates all filenames longer than 119 bytes when you run `Tools->Check Media...`.
    local allowed_bytes = 119
    local timestamp_bytes = #'_(99h99m99s999ms-99h99m99s999ms).webp'
    local limit_bytes = allowed_bytes - timestamp_bytes

    anki_compatible_length = function(str)
        if #str <= limit_bytes then
            return str
        end

        local bytes_per_char = contains_non_latin_letters(str) and #'車' or #'z'
        local limit_chars = math.floor(limit_bytes / bytes_per_char)

        if limit_chars == limit_bytes then
            return str:sub(1, limit_bytes)
        end

        local ret = subprocess {
            'awk',
            '-v', string.format('str=%s', str),
            '-v', string.format('limit=%d', limit_chars),
            'BEGIN{print substr(str, 1, limit); exit}'
        }

        if ret.status == 0 then
            ret.stdout = remove_newlines(ret.stdout)
            ret.stdout = remove_leading_trailing_spaces(ret.stdout)
            return ret.stdout
        else
            return 'subs2srs_' .. os.time()
        end
    end
end

local function construct_media_filenames(timings)
    local filename = mp.get_property("filename") -- filename without path

    filename = remove_extension(filename)
    filename = remove_text_in_brackets(filename)
    filename = remove_special_characters(filename)
    filename = anki_compatible_length(filename)

    filename = string.format(
            '%s_(%s-%s)',
            filename,
            human_readable_time(timings['start']),
            human_readable_time(timings['end'])
    )

    return filename .. config.snapshot_extension, filename .. config.audio_extension
end

local function construct_note_fields(sub_text, snapshot_filename, audio_filename)
    if not is_empty(sub_text) then
        sub_text = trim(sub_text)
    end
    return {
        [config.sentence_field] = sub_text,
        [config.image_field] = string.format('<img src="%s" alt="snapshot">', snapshot_filename),
        [config.audio_field] = string.format('[sound:%s]', audio_filename),
    }
end

local function _(fn, param1)
    return function() pcall(fn, param1) end
end

local function sub_seek(direction)
    mp.commandv("sub_seek", direction == 'backward' and '-1' or '1')
    mp.commandv("seek", "0.015", "relative+exact")
end

local function sub_rewind()
    local sub_start_time = subs.get_current()['start'] + 0.015
    mp.commandv('seek', sub_start_time, 'absolute')
end

local function minutes_ago(m)
    return (os.time() - 60 * m) * 1000
end

local function export_to_anki(gui)
    local sub = subs.get()
    subs.clear()
    if sub == nil then
        notify("Nothing to export.", "warn", 1)
        return
    end

    local snapshot_filename, audio_filename = construct_media_filenames(sub)
    local snapshot_timestamp = (sub['start'] + sub['end']) / 2

    encoder.create_snapshot(snapshot_timestamp, snapshot_filename)
    encoder.create_audio(sub['start'], sub['end'], audio_filename)

    local note_fields = construct_note_fields(sub['text'], snapshot_filename, audio_filename)
    ankiconnect.add_note(note_fields, gui)
end

local function update_last_note(overwrite)
    local sub = subs.get()
    local last_note_id = ankiconnect.get_last_note_id()
    subs.clear()

    if sub == nil then
        notify("Nothing to export. Have you set the timings?", "warn", 2)
        return
    end

    if last_note_id < minutes_ago(10) then
        notify("Couldn't find the target note.", "warn", 2)
        return
    end

    local snapshot_filename, audio_filename = construct_media_filenames(sub)
    local snapshot_timestamp = (sub['start'] + sub['end']) / 2

    encoder.create_snapshot(snapshot_timestamp, snapshot_filename)
    encoder.create_audio(sub['start'], sub['end'], audio_filename)

    local note_fields = construct_note_fields(sub['text'], snapshot_filename, audio_filename)
    ankiconnect.append_media(last_note_id, note_fields, overwrite)
end

local function get_empty_timings()
    return {
        ['start'] = -1,
        ['end'] = -1,
    }
end

local function join_media_fields(note1, note2)
    if note2[config.audio_field] then
        note1[config.audio_field] = note2[config.audio_field] .. note1[config.audio_field]
    end

    if note2[config.image_field] then
        note1[config.image_field] = note2[config.image_field] .. note1[config.image_field]
    end

    return note1
end

local function get_forvo_pronunciation(word)
    word = platform.windows and url_encode(word) or word
    local forvo_format = config.audio_extension:sub(2)
    local forvo_page = subprocess { 'curl', '-s', string.format('https://forvo.com/search/%s/ja', word) }.stdout
    local play_params = string.match(forvo_page, "Play%((.-)%);")
    if not play_params then
        return nil
    end
    local iter = string.gmatch(play_params, "'(.-)'")
    local formats = { mp3 = iter(), ogg = iter() }
    local audio_url = string.format('https://audio00.forvo.com/%s/%s', forvo_format, base64d(formats[forvo_format]))
    local pronunciation_filename = string.format('forvo_%s.%s', platform.windows and os.time() or word, forvo_format)
    local pronunciation_path = utils.join_path(config.collection_path, pronunciation_filename)
    mp.commandv('run', 'curl', audio_url, '-s', '-L', '-o', pronunciation_path)
    return string.format('[sound:%s]', pronunciation_filename)
end

local function append_forvo_pronunciation(note1, note2)
    if config.use_forvo == 'no' then
        return note1
    end
    if type(note2[config.vocab_audio_field]) ~= 'string' then
        return note1
    end
    if is_empty(note2[config.vocab_field]) then
        return note1
    end
    if config.use_forvo == 'always' or is_empty(note2[config.vocab_audio_field]) then
        note1[config.vocab_audio_field] = get_forvo_pronunciation(note2[config.vocab_field])
    end
    return note1
end

local validate_config
do
    local function set_collection_path()
        if not is_dir(config.collection_path) then
            -- collection path wasn't specified. construct it using config.anki_user
            config.collection_path = platform.construct_collection_path()
        end
    end

    local function set_audio_format()
        if config.audio_format == 'opus' then
            config.audio_codec = 'libopus'
            config.audio_extension = '.ogg'
        else
            config.audio_codec = 'libmp3lame'
            config.audio_extension = '.mp3'
        end
    end

    local function set_video_format()
        if config.snapshot_format == 'webp' then
            config.snapshot_extension = '.webp'
            config.snapshot_codec = 'libwebp'
        else
            config.snapshot_extension = '.jpg'
            config.snapshot_codec = 'mjpeg'
        end
    end

    local function ensure_in_range(dimension)
        config[dimension] = config[dimension] < 42 and -2 or config[dimension]
        config[dimension] = config[dimension] > 640 and 640 or config[dimension]
    end

    local function check_snapshot_settings()
        ensure_in_range('snapshot_width')
        ensure_in_range('snapshot_height')
        if config.snapshot_width < 1 and config.snapshot_height < 1 then
            config.snapshot_width = -2
            config.snapshot_height = 200
        end
        if config.snapshot_quality < 0 or config.snapshot_quality > 100 then
            config.snapshot_quality = 15
        end
    end

    validate_config = function()
        set_collection_path()
        set_audio_format()
        set_video_format()
        check_snapshot_settings()
    end
end

------------------------------------------------------------
-- platform specific

local function init_platform_windows()
    local self = {}
    local curl_tmpfile_path = utils.join_path(os.getenv('TEMP'), 'curl_tmp.txt')
    mp.register_event('shutdown', function() os.remove(curl_tmpfile_path) end)

    self.copy_to_clipboard = function(_, text)
        if not is_empty(text) then
            text = remove_newlines(text)
            mp.commandv("run", "cmd.exe", "/d", "/c", string.format("@echo off & chcp 65001 & echo %s|clip", text))
        end
    end

    self.construct_collection_path = function()
        return string.format([[%s\Anki2\%s\collection.media\]], os.getenv('APPDATA'), config.anki_user)
    end

    self.curl_request = function(request_json, completion_fn)
        io.open(curl_tmpfile_path, "w"):write(request_json):close()
        local args = {
            'curl',
            '-s',
            'localhost:8765',
            '-H',
            'Content-Type: application/json; charset=UTF-8',
            '-X',
            'POST',
            '--data-binary',
            table.concat { '@', curl_tmpfile_path }
        }
        return subprocess(args, completion_fn)
    end

    self.windows = true

    return self
end

local function init_platform_nix()
    local self = {}
    local clip = is_running_macOS() and 'LANG=en_US.UTF-8 pbcopy' or 'xclip -i -selection clipboard'

    self.copy_to_clipboard = function(_, text)
        if not is_empty(text) then
            local handle = io.popen(clip, 'w')
            handle:write(text)
            handle:close()
        end
    end

    self.construct_collection_path = function()
        return string.format('%s/.local/share/Anki2/%s/collection.media/', os.getenv('HOME'), config.anki_user)
    end

    self.curl_request = function(request_json, completion_fn)
        return subprocess ({ 'curl', '-s', 'localhost:8765', '-X', 'POST', '-d', request_json }, completion_fn)
    end

    return self
end

platform = is_running_windows() and init_platform_windows() or init_platform_nix()

------------------------------------------------------------
-- provides interface for creating audioclips and snapshots

encoder = {}

encoder.pad_timings = function(start_time, end_time)
    local video_duration = mp.get_property_number('duration')
    if config.audio_padding == 0.0 or not video_duration then
        return start_time, end_time
    end
    start_time = start_time - config.audio_padding
    end_time = end_time + config.audio_padding
    if start_time < 0 then start_time = 0 end
    if end_time > video_duration then end_time = video_duration end
    return start_time, end_time
end

encoder.create_snapshot = function(timestamp, filename)
    local video_path = mp.get_property("path")
    local snapshot_path = utils.join_path(config.collection_path, filename)

    mp.commandv(
            'run',
            'mpv',
            video_path,
            '--loop-file=no',
            '--audio=no',
            '--no-ocopy-metadata',
            '--no-sub',
            '--frames=1',
            '--ovcopts-add=lossless=0',
            '--ovcopts-add=compression_level=6',
            table.concat { '--ovc=', config.snapshot_codec },
            table.concat { '-start=', timestamp },
            table.concat { '--ovcopts-add=quality=', tostring(config.snapshot_quality) },
            table.concat { '--vf-add=scale=', config.snapshot_width, ':', config.snapshot_height },
            table.concat { '-o=', snapshot_path }
    )
end

encoder.create_audio = function(start_timestamp, end_timestamp, filename)
    local video_path = mp.get_property("path")
    local fragment_path = utils.join_path(config.collection_path, filename)
    start_timestamp, end_timestamp = encoder.pad_timings(start_timestamp, end_timestamp)

    mp.commandv(
            'run',
            'mpv',
            video_path,
            '--loop-file=no',
            '--video=no',
            '--no-ocopy-metadata',
            '--no-sub',
            '--audio-channels=mono',
            '--oacopts-add=vbr=on',
            '--oacopts-add=application=voip',
            '--oacopts-add=compression_level=10',
            table.concat { '--oac=', config.audio_codec },
            table.concat { '--start=', start_timestamp },
            table.concat { '--end=', end_timestamp },
            table.concat { '--aid=', mp.get_property("aid") }, -- track number
            table.concat { '--volume=', config.tie_volumes and mp.get_property('volume') or '100' },
            table.concat { '--oacopts-add=b=', config.audio_bitrate },
            table.concat { '-o=', fragment_path }
    )
end

------------------------------------------------------------
-- AnkiConnect requests

ankiconnect = {}

ankiconnect.execute = function(request, completion_fn)
    -- utils.format_json returns a string
    -- On error, request_json will contain "null", not nil.
    local request_json, error = utils.format_json(request)

    if error ~= nil or request_json == "null" then
        return completion_fn and completion_fn()
    else
        return platform.curl_request(request_json, completion_fn)
    end
end

ankiconnect.parse_result = function(curl_output)
    -- there are two values that we actually care about: result and error
    -- but we need to crawl inside to get them.

    if curl_output == nil then
        return nil, "Failed to format json or no args passed"
    end

    if curl_output.status ~= 0 then
        return nil, "Ankiconnect isn't running"
    end

    local stdout_json = utils.parse_json(curl_output.stdout)

    if stdout_json == nil then
        return nil, "Fatal error from Ankiconnect"
    end

    if stdout_json.error ~= nil then
        return nil, tostring(stdout_json.error)
    end

    return stdout_json.result, nil
end

ankiconnect.create_deck = function(deck_name)
    local args = {
        action = "changeDeck",
        version = 6,
        params = {
            cards = {},
            deck = deck_name
        }
    }
    local result_notify = function(_, result, _)
        local _, error = ankiconnect.parse_result(result)
        if not error then
            msg.info(string.format("Deck %s: check completed.", deck_name))
        else
            msg.warn(string.format("Deck %s: check failed. Reason: %s.", deck_name, error))
        end
    end
    ankiconnect.execute(args, result_notify)
end

ankiconnect.add_note = function(note_fields, gui)
    local action = gui and 'guiAddCards' or 'addNote'
    local tags = is_empty(config.note_tag) and {} or { config.note_tag }
    local args = {
        action = action,
        version = 6,
        params = {
            note = {
                deckName = config.deck_name,
                modelName = config.model_name,
                fields = note_fields,
                options = {
                    allowDuplicate = false,
                    duplicateScope = "deck",
                },
                tags = tags,
            }
        }
    }
    local result_notify = function(_, result, _)
        local note_id, error = ankiconnect.parse_result(result)
        if not error then
            notify(string.format("Note added. ID = %s.", note_id))
        else
            notify(string.format("Error: %s.", error), "error", 2)
        end
    end
    ankiconnect.execute(args, result_notify)
end

ankiconnect.get_last_note_id = function()
    local ret = ankiconnect.execute {
        action = "findNotes",
        version = 6,
        params = {
            query = "added:1" -- find all notes added today
        }
    }

    local note_ids, _ = ankiconnect.parse_result(ret)

    if not is_empty(note_ids) then
        return table.max_num(note_ids)
    else
        return -1
    end
end

ankiconnect.get_note_fields = function(note_id)
    local ret = ankiconnect.execute {
        action = "notesInfo",
        version = 6,
        params = {
            notes = { note_id }
        }
    }

    local result, error = ankiconnect.parse_result(ret)

    if error == nil then
        result = result[1].fields
        for key, value in pairs(result) do
            result[key] = value.value
        end
        return result
    else
        return nil
    end
end

ankiconnect.gui_browse = function(query)
    ankiconnect.execute {
        action = 'guiBrowse',
        version = 6,
        params = {
            query = query
        }
    }
end

ankiconnect.append_media = function(note_id, note_fields, overwrite)
    -- AnkiConnect will fail to update the note if it's selected in the Anki Browser.
    -- https://github.com/FooSoft/anki-connect/issues/82
    -- Switch focus from the current note to avoid it.
    ankiconnect.gui_browse("nid:1") -- impossible nid

    local old_fields = ankiconnect.get_note_fields(note_id)
    if old_fields then
        note_fields = append_forvo_pronunciation(note_fields, old_fields)
        if not overwrite then
            note_fields = join_media_fields(note_fields, old_fields)
        end
    end

    local args = {
        action = "updateNoteFields",
        version = 6,
        params = {
            note = {
                id = note_id,
                fields = note_fields,
            }
        }
    }

    local result_notify = function(_, result, _)
        local _, error = ankiconnect.parse_result(result)
        if not error then
            notify(string.format("Note #%s updated.", note_id))
            ankiconnect.gui_browse(string.format("nid:%s", note_id)) -- select the updated note in the card browser
        else
            notify(string.format("Error: %s.", error), "error", 2)
        end
    end

    ankiconnect.execute(args, result_notify)
end

------------------------------------------------------------
-- subtitles and timings

subs = {
    list = {},
    user_timings = get_empty_timings(),
}

subs.get_current = function()
    local sub_text = mp.get_property("sub-text")
    if not is_empty(sub_text) then
        local sub_delay = mp.get_property_native("sub-delay")
        return Subtitle:new {
            ['text'] = sub_text,
            ['start'] = mp.get_property_number("sub-start") + sub_delay,
            ['end'] = mp.get_property_number("sub-end") + sub_delay
        }
    end
    return nil
end

subs.get_timing = function(position)
    if subs.user_timings[position] >= 0 then
        return subs.user_timings[position]
    end
    if not is_empty(subs.list) then
        local i = position == 'start' and 1 or #subs.list
        return subs.list[i][position]
    end
    return nil
end

subs.get_text = function()
    local speech = {}
    for _, sub in ipairs(subs.list) do
        table.insert(speech, sub['text'])
    end
    return table.concat(speech, ' ')
end

subs.get = function()
    if is_empty(subs.list) then
        return subs.get_current()
    else
        table.sort(subs.list)
        return Subtitle:new {
            ['text'] = subs.get_text(),
            ['start'] = subs.get_timing('start'),
            ['end'] = subs.get_timing('end'),
        }
    end
end

subs.append = function()
    local sub = subs.get_current()

    if sub ~= nil and not table.contains(subs.list, sub) then
        table.insert(subs.list, sub)
        menu.update()
    end
end

subs.set_timing = function(position)
    subs.user_timings[position] = mp.get_property_number('time-pos')
    menu.update()
    notify(capitalize_first_letter(position) .. " time has been set.")

    if is_empty(subs.list) then
        mp.observe_property("sub-text", "string", subs.append)
    end
end

subs.set_starting_line = function()
    subs.clear()
    local sub_text = mp.get_property("sub-text")

    if not is_empty(sub_text) then
        mp.observe_property("sub-text", "string", subs.append)
        notify("Timings have been set to the current sub.", "info", 2)
    else
        notify("There's no visible subtitle.", "info", 2)
    end
end

subs.clear = function()
    mp.unobserve_property(subs.append)
    subs.list = {}
    subs.user_timings = get_empty_timings()
    menu.update()
end

subs.clear_and_notify = function()
    subs.clear()
    notify("Timings have been reset.", "info", 2)
end

------------------------------------------------------------
-- send subs to clipboard as they appear

clip_autocopy = {}

clip_autocopy.enable = function()
    mp.observe_property("sub-text", "string", platform.copy_to_clipboard)
    notify("Clipboard autocopy has been enabled.", "info", 1)
end

clip_autocopy.disable = function()
    mp.unobserve_property(platform.copy_to_clipboard)
    notify("Clipboard autocopy has been disabled.", "info", 1)
end

clip_autocopy.toggle = function()
    if config.autoclip == true then
        clip_autocopy.disable()
        config.autoclip = false
    else
        clip_autocopy.enable()
        config.autoclip = true
    end
    menu.update()
end

clip_autocopy.is_enabled = function()
    if config.autoclip == true then
        return 'enabled'
    else
        return 'disabled'
    end
end

------------------------------------------------------------
-- Subtitle class provides methods for comparing subtitle lines

Subtitle = {
    ['text'] = '',
    ['start'] = -1,
    ['end'] = -1,
}

function Subtitle:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

Subtitle.__eq = function(lhs, rhs)
    return lhs['text'] == rhs['text']
end

Subtitle.__lt = function(lhs, rhs)
    return lhs['start'] < rhs['start']
end

------------------------------------------------------------
-- main menu

menu = {
    active = false,
    show_hints = false,
    overlay = mp.create_osd_overlay and mp.create_osd_overlay('ass-events'),
}

menu.overlay_draw = function(text)
    menu.overlay.data = text
    menu.overlay:update()
end

menu.keybinds = {
    { key = 's', fn = function() subs.set_timing('start') end },
    { key = 'e', fn = function() subs.set_timing('end') end },
    { key = 'c', fn = function() subs.set_starting_line() end },
    { key = 'r', fn = function() subs.clear_and_notify() end },
    { key = 'g', fn = function() export_to_anki(true) end },
    { key = 'n', fn = function() export_to_anki(false) end },
    { key = 'm', fn = function() update_last_note(false) end },
    { key = 'M', fn = function() update_last_note(true) end },
    { key = 't', fn = function() clip_autocopy.toggle() end },
    { key = 'i', fn = function() menu.hints_toggle() end },
    { key = 'ESC', fn = function() menu.close() end },
}

menu.update = function()
    if menu.active == false then
        return
    end

    table.sort(subs.list)
    local osd = OSD:new():size(config.menu_font_size):align(4)
    osd:submenu('mpvacious options'):newline()
    osd:item('Start time: '):text(human_readable_time(subs.get_timing('start'))):newline()
    osd:item('End time: '):text(human_readable_time(subs.get_timing('end'))):newline()
    osd:item('Clipboard autocopy: '):text(clip_autocopy.is_enabled()):newline()

    if menu.show_hints then
        osd:submenu('Menu bindings'):newline()
        osd:tab():item('c: '):text('Set timings to the current sub'):newline()
        osd:tab():item('s: '):text('Set start time to current position'):newline()
        osd:tab():item('e: '):text('Set end time to current position'):newline()
        osd:tab():item('r: '):text('Reset timings'):newline()
        osd:tab():item('n: '):text('Export note'):newline()
        osd:tab():item('g: '):text('Export note using the `Add Cards` GUI'):newline()
        osd:tab():item('m: '):text('Update the last added note '):italics('(+shift to overwrite)'):newline()
        osd:tab():item('t: '):text('Toggle clipboard autocopy'):newline()
        osd:tab():item('ESC: '):text('Close'):newline()
        osd:submenu('Global bindings'):newline()
        osd:tab():item('ctrl+e: '):text('Export note'):newline()
        osd:tab():item('ctrl+h: '):text('Seek to the start of the line'):newline()
        osd:tab():item('ctrl+c: '):text('Copy current subtitle to clipboard'):newline()
    else
        osd:italics("Press "):item('i'):italics(" to toggle hints."):newline()
    end

    menu.overlay_draw(osd:get_text())
end

menu.hints_toggle = function()
    menu.show_hints = not menu.show_hints
    menu.update()
end

menu.open = function()
    if menu.overlay == nil then
        notify("OSD overlay is not supported in this version of mpv.", "error", 5)
        return
    end

    if menu.active == true then
        menu.close()
        return
    end

    for _, val in pairs(menu.keybinds) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end

    menu.active = true
    menu.update()
end

menu.close = function()
    if menu.active == false then
        return
    end

    for _, val in pairs(menu.keybinds) do
        mp.remove_key_binding(val.key)
    end

    menu.overlay:remove()
    menu.active = false
end

------------------------------------------------------------
-- Helper class for styling OSD messages
-- http://docs.aegisub.org/3.2/ASS_Tags/

OSD = {}
OSD.__index = OSD

function OSD:new()
    return setmetatable({ messages = { } }, self)
end

function OSD:append(s)
    table.insert(self.messages, s)
    return self
end

function OSD:bold(s)
    return self:append('{\\b1}'):append(s):append('{\\b0}')
end

function OSD:italics(s)
    return self:color('ffffff'):append('{\\i1}'):append(s):append('{\\i0}')
end

function OSD:color(code)
    return self:append('{\\1c&H')
               :append(code:sub(5, 6))
               :append(code:sub(3, 4))
               :append(code:sub(1, 2))
               :append('&}')
end

function OSD:text(text)
    return self:color('ffffff'):append(text)
end

function OSD:submenu(text)
    return self:color('ffe1d0'):bold(text)
end

function OSD:item(text)
    return self:color('fef6dd'):bold(text)
end

function OSD:newline()
    return self:append('\\N')
end

function OSD:tab()
    return self:append('\\h\\h\\h\\h')
end

function OSD:size(size)
    return self:append('{\\fs'):append(size):append('}')
end

function OSD:align(number)
    return self:append('{\\an'):append(number):append('}')
end

function OSD:get_text()
    return table.concat(self.messages)
end

------------------------------------------------------------
-- main

if config.autoclip == true then
    clip_autocopy.enable()
end

validate_config()

ankiconnect.create_deck(config.deck_name)

-- Key bindings
mp.add_forced_key_binding("ctrl+e", "mpvacious-export-note", export_to_anki)
mp.add_forced_key_binding("ctrl+c", "mpvacious-copy-sub-to-clipboard", copy_sub_to_clipboard)
mp.add_key_binding("a", "mpvacious-menu-open", menu.open) -- a for advanced
mp.add_key_binding("ctrl+h", "mpvacious-sub-rewind", _(sub_rewind))

-- Vim-like seeking between subtitle lines
mp.add_key_binding("H", "mpvacious-sub-seek-back", _(sub_seek, 'backward'))
mp.add_key_binding("L", "mpvacious-sub-seek-forward", _(sub_seek, 'forward'))

-- Unset by default
mp.add_key_binding(nil, "mpvacious-set-starting-line", subs.set_starting_line)
mp.add_key_binding(nil, "mpvacious-reset-timings", subs.clear_and_notify)
mp.add_key_binding(nil, "mpvacious-toggle-sub-autocopy", clip_autocopy.toggle)
