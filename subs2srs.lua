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
    -- Common
    autoclip = false,              -- enable copying subs to the clipboard when mpv starts
    nuke_spaces = true,            -- remove all spaces from exported anki cards
    clipboard_trim_enabled = true, -- remove unnecessary characters from strings before copying to the clipboard
    snapshot_format = "webp",      -- webp or jpg
    snapshot_quality = 15,         -- from 0=lowest to 100=highest
    snapshot_width = -2,           -- a positive integer or -2 for auto
    snapshot_height = 200,         -- same
    audio_format = "opus",         -- opus or mp3
    audio_bitrate = "18k",         -- from 16k to 32k
    audio_padding = 0.12,          -- Set a pad to the dialog timings. 0.5 = audio is padded by .5 seconds. 0 = disable.
    tie_volumes = false,           -- if set to true, the volume of the outputted audio file depends on the volume of the player at the time of export
    menu_font_size = 25,

    -- Anki
    deck_name = "Learning",        -- the deck will be created if needed
    model_name = "Japanese sentences",  -- Tools -> Manage note types
    sentence_field = "SentKanji",
    audio_field = "SentAudio",
    image_field = "Image",
    note_tag = "subs2srs",      -- the tag that is added to new notes. change to "" to disable tagging

    -- Forvo support
    use_forvo = "yes",                  -- 'yes', 'no', 'always'
    vocab_field = "VocabKanji",         -- target word field
    vocab_audio_field = "VocabAudio",   -- target word audio
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
local append_forvo_pronunciation

-- classes
local Subtitle
local OSD

------------------------------------------------------------
-- utility functions

---Returns true if table contains element. Returns false otherwise.
---@param table table
---@param element any
---@return boolean
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

---Returns the largest numeric index.
---@param table table
---@return number
function table.max_num(table)
    local max = table[1]
    for _, value in ipairs(table) do
        if value > max then
            max = value
        end
    end
    return max
end

---Returns a value for the given key. If key is not available then returns default value 'nil'.
---@param table table
---@param key string
---@param default any
---@return any
function table.get(table, key, default)
    if table[key] == nil then
        return default or 'nil'
    else
        return table[key]
    end
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

local function contains_non_latin_letters(str)
    return str:match("[^%c%p%s%w]")
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

local escape_special_characters
do
    local entities = {
        ['&'] = '&amp;',
        ['"'] = '&quot;',
        ["'"] = '&apos;',
        ['<'] = '&lt;',
        ['>'] = '&gt;',
    }
    escape_special_characters = function(s)
        return s:gsub('[&"\'<>]', entities)
    end
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
    -- No deletion is performed if there's no text after the parentheses.
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub('(%b())(.)', '%2'):gsub('(（.-）)(.)', '%2')
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

local function remove_spaces(str)
    if config.nuke_spaces == true and contains_non_latin_letters(str) then
        return remove_all_spaces(str)
    else
        return remove_leading_trailing_spaces(str)
    end
end

local function trim(str)
    str = remove_spaces(str)
    str = remove_text_in_parentheses(str)
    str = remove_newlines(str)
    return str
end

local function copy_to_clipboard(_, text)
    if not is_empty(text) then
        text = config.clipboard_trim_enabled and trim(text) or remove_newlines(text)
        platform.copy_to_clipboard(text)
    end
end

local function copy_sub_to_clipboard()
    copy_to_clipboard("copy-on-demand", mp.get_property("sub-text"))
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

local function construct_note_fields(sub_text, snapshot_filename, audio_filename)
    return {
        [config.sentence_field] = sub_text,
        [config.image_field] = string.format('<img alt="snapshot" src="%s">', snapshot_filename),
        [config.audio_field] = string.format('[sound:%s]', audio_filename),
    }
end

local function minutes_ago(m)
    return (os.time() - 60 * m) * 1000
end

local function join_media_fields(new_data, stored_data)
    for _, field in pairs { config.audio_field, config.image_field } do
        new_data[field] = table.get(stored_data, field, "") .. table.get(new_data, field, "")
    end
    return new_data
end

local validate_config
do
    local function is_webp_supported()
        local ret = subprocess { 'mpv', '--ovc=help' }
        return ret.status == 0 and ret.stdout:match('--ovc=libwebp')
    end

    local function is_opus_supported()
        local ret = subprocess { 'mpv', '--oac=help' }
        return ret.status == 0 and ret.stdout:match('--oac=libopus')
    end

    local function set_audio_format()
        if config.audio_format == 'opus' and is_opus_supported() then
            config.audio_codec = 'libopus'
            config.audio_extension = '.ogg'
        else
            config.audio_codec = 'libmp3lame'
            config.audio_extension = '.mp3'
        end
    end

    local function set_video_format()
        if config.snapshot_format == 'webp' and is_webp_supported() then
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

    local function conditionally_set_defaults(width, height, quality)
        if config[width] < 1 and config[height] < 1 then
            config[width] = -2
            config[height] = 200
        end
        if config[quality] < 0 or config[quality] > 100 then
            config[quality] = 15
        end
    end

    local function check_image_settings()
        ensure_in_range('snapshot_width')
        ensure_in_range('snapshot_height')
        conditionally_set_defaults('snapshot_width', 'snapshot_height', 'snapshot_quality')
    end

    validate_config = function()
        set_audio_format()
        set_video_format()
        check_image_settings()
    end
end

local function update_sentence(new_data, stored_data)
    -- adds support for TSCs
    -- https://tatsumoto-ren.github.io/blog/discussing-various-card-templates.html#targeted-sentence-cards-or-mpvacious-cards
    -- if the target word was marked by yomichan, this function makes sure that the highlighting doesn't get erased.
    local _, target, _ = stored_data[config.sentence_field]:match('^(.-)<b>(.-)</b>(.-)$')
    if target then
        local prefix, _, suffix = new_data[config.sentence_field]:match(table.concat { '^(.-)(', target, ')(.-)$' })
        if prefix and suffix then
            new_data[config.sentence_field] = table.concat { prefix, '<b>', target, '</b>', suffix }
        end
    end
    return new_data
end

------------------------------------------------------------
-- utility classes

local function new_timings()
    local self = { ['start'] = -1, ['end'] = -1, }
    local is_set = function(position)
        return self[position] >= 0
    end
    local set = function(position)
        self[position] = mp.get_property_number('time-pos')
    end
    local get = function(position)
        return self[position]
    end
    return {
        is_set = is_set,
        set = set,
        get = get,
    }
end

local function new_sub_list()
    local subs_list = {}
    local _is_empty = function()
        return next(subs_list) == nil
    end
    local find_i = function(sub)
        for i, v in ipairs(subs_list) do
            if sub < v then
                return i
            end
        end
        return #subs_list + 1
    end
    local get_time = function(position)
        local i = position == 'start' and 1 or #subs_list
        return subs_list[i][position]
    end
    local get_text = function()
        local speech = {}
        for _, sub in ipairs(subs_list) do
            table.insert(speech, sub['text'])
        end
        return table.concat(speech, ' ')
    end
    local insert = function(sub)
        if sub ~= nil and not table.contains(subs_list, sub) then
            table.insert(subs_list, find_i(sub), sub)
            return true
        end
        return false
    end
    return {
        get_time = get_time,
        get_text = get_text,
        is_empty = _is_empty,
        insert = insert
    }
end

local function make_switch(states)
    local self = {
        states = states,
        current_state = 1
    }
    local bump = function()
        self.current_state = self.current_state + 1
        if self.current_state > #self.states then
            self.current_state = 1
        end
    end
    local get = function()
        return self.states[self.current_state]
    end
    return {
        bump = bump,
        get = get
    }
end

local filename_factory = (function()
    local filename

    local anki_compatible_length = (function()
        -- Anki forcibly mutilates all filenames longer than 119 bytes when you run `Tools->Check Media...`.
        local allowed_bytes = 119
        local timestamp_bytes = #'_99h99m99s999ms-99h99m99s999ms.webp'

        return function(str, timestamp)
            -- if timestamp provided, recalculate limit_bytes
            local limit_bytes = allowed_bytes - (timestamp and #timestamp or timestamp_bytes)

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
    end)()

    local make_media_filename = function()
        filename = mp.get_property("filename") -- filename without path
        filename = remove_extension(filename)
        filename = remove_text_in_brackets(filename)
        filename = remove_special_characters(filename)
    end

    local make_audio_filename = function(speech_start, speech_end)
        local filename_timestamp = string.format(
                '_%s-%s%s',
                human_readable_time(speech_start),
                human_readable_time(speech_end),
                config.audio_extension
        )
        return anki_compatible_length(filename, filename_timestamp) .. filename_timestamp
    end

    local make_snapshot_filename = function(timestamp)
        local filename_timestamp = string.format(
                '_%s%s',
                human_readable_time(timestamp),
                config.snapshot_extension
        )
        return anki_compatible_length(filename, filename_timestamp) .. filename_timestamp
    end

    mp.register_event("file-loaded", make_media_filename)

    return {
        make_audio_filename = make_audio_filename,
        make_snapshot_filename = make_snapshot_filename,
    }
end)()

------------------------------------------------------------
-- front for adding and updating notes

local function export_to_anki(gui)
    local sub = subs.get()
    if sub == nil then
        notify("Nothing to export.", "warn", 1)
        return
    end

    if not gui and is_empty(sub['text']) then
        sub['text'] = string.format([[<span id="mpv%s">mpvacious wasn't able to grab subtitles</span>]], os.time())
    end

    local snapshot_timestamp = mp.get_property_number("time-pos", 0)
    local snapshot_filename = filename_factory.make_snapshot_filename(snapshot_timestamp)
    local audio_filename = filename_factory.make_audio_filename(sub['start'], sub['end'])

    encoder.create_snapshot(snapshot_timestamp, snapshot_filename)
    encoder.create_audio(sub['start'], sub['end'], audio_filename)

    local note_fields = construct_note_fields(sub['text'], snapshot_filename, audio_filename)
    ankiconnect.add_note(note_fields, gui)
    subs.clear()
end

local function update_last_note(overwrite)
    local sub = subs.get()
    local last_note_id = ankiconnect.get_last_note_id()

    if sub == nil or is_empty(sub['text']) then
        notify("Nothing to export. Have you set the timings?", "warn", 2)
        return
    end

    if last_note_id < minutes_ago(10) then
        notify("Couldn't find the target note.", "warn", 2)
        return
    end

    local snapshot_timestamp = mp.get_property_number("time-pos", 0)
    local snapshot_filename = filename_factory.make_snapshot_filename(snapshot_timestamp)
    local audio_filename = filename_factory.make_audio_filename(sub['start'], sub['end'])

    local create_media = function()
        encoder.create_snapshot(snapshot_timestamp, snapshot_filename)
        encoder.create_audio(sub['start'], sub['end'], audio_filename)
    end

    local new_data = construct_note_fields(sub['text'], snapshot_filename, audio_filename)
    local stored_data = ankiconnect.get_note_fields(last_note_id)
    if stored_data then
        new_data = append_forvo_pronunciation(new_data, stored_data)
        new_data = update_sentence(new_data, stored_data)
        if not overwrite then
            new_data = join_media_fields(new_data, stored_data)
        end
    end

    ankiconnect.append_media(last_note_id, new_data, create_media)
    subs.clear()
end

------------------------------------------------------------
-- seeking: sub replay, sub seek, sub rewind

local function _(params)
    local unpack = unpack and unpack or table.unpack
    return function() return pcall(unpack(params)) end
end

local pause_timer = (function()
    local stop_time = -1
    local check_stop
    local set_stop_time = function(time)
        stop_time = time
    end
    local stop = function()
        mp.unobserve_property(check_stop)
        stop_time = -1
    end
    check_stop = function(_, time)
        if time > stop_time then
            stop()
            mp.set_property("pause", "yes")
        else
            notify('Timer: ' .. human_readable_time(stop_time - time))
        end
    end
    return {
        set_stop_time = set_stop_time,
        check_stop = check_stop,
        stop = stop,
    }
end)()

local function sub_replay()
    local sub = subs.get_current()
    pause_timer.set_stop_time(sub['end'] - 0.050)
    mp.commandv('seek', sub['start'], 'absolute')
    mp.set_property("pause", "no")
    mp.observe_property("time-pos", "number", pause_timer.check_stop)
end

local function sub_seek(direction, pause)
    mp.commandv("sub_seek", direction == 'backward' and '-1' or '1')
    mp.commandv("seek", "0.015", "relative+exact")
    if pause then
        mp.set_property("pause", "yes")
    end
    pause_timer.stop()
end

local function sub_rewind()
    mp.commandv('seek', subs.get_current()['start'] + 0.015, 'absolute')
    pause_timer.stop()
end

------------------------------------------------------------
-- platform specific

local function init_platform_windows()
    local self = {}
    local curl_tmpfile_path = utils.join_path(os.getenv('TEMP'), 'curl_tmp.txt')
    mp.register_event('shutdown', function() os.remove(curl_tmpfile_path) end)

    self.tmp_dir = function()
        return os.getenv('TEMP')
    end

    self.copy_to_clipboard = function(text)
        text = text:gsub("&", "^^^&")
        mp.commandv("run", "cmd.exe", "/d", "/c", string.format("@echo off & chcp 65001 & echo %s|clip", text))
    end

    self.curl_request = function(request_json, completion_fn)
        local handle = io.open(curl_tmpfile_path, "w")
        handle:write(request_json)
        handle:close()
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

    self.tmp_dir = function()
        return '/tmp'
    end

    self.copy_to_clipboard = function(text)
        local handle = io.popen(clip, 'w')
        handle:write(text)
        handle:close()
    end

    self.curl_request = function(request_json, completion_fn)
        local args = { 'curl', '-s', 'localhost:8765', '-X', 'POST', '-d', request_json }
        return subprocess(args, completion_fn)
    end

    return self
end

platform = is_running_windows() and init_platform_windows() or init_platform_nix()

------------------------------------------------------------
-- utils for downloading pronunciations from Forvo

do
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

    local function reencode(source_path, dest_path)
        local args = {
            'mpv',
            source_path,
            '--loop-file=no',
            '--video=no',
            '--no-ocopy-metadata',
            '--no-sub',
            '--audio-channels=mono',
            '--oacopts-add=vbr=on',
            '--oacopts-add=application=voip',
            '--oacopts-add=compression_level=10',
            '--af-append=silenceremove=1:0:-50dB',
            table.concat { '--oac=', config.audio_codec },
            table.concat { '--oacopts-add=b=', config.audio_bitrate },
            table.concat { '-o=', dest_path }
        }
        return subprocess(args)
    end

    local function reencode_and_store(source_path, filename)
        local reencoded_path = utils.join_path(platform.tmp_dir(), 'reencoded_' .. filename)
        reencode(source_path, reencoded_path)
        local result = ankiconnect.store_file(filename, reencoded_path)
        os.remove(reencoded_path)
        return result
    end

    local function curl_save(source_url, save_location)
        local curl_args = { 'curl', source_url, '-s', '-L', '-o', save_location }
        return subprocess(curl_args).status == 0
    end

    local function get_pronunciation_url(word)
        local file_format = config.audio_extension:sub(2)
        local forvo_page = subprocess { 'curl', '-s', string.format('https://forvo.com/search/%s/ja', url_encode(word)) }.stdout
        local play_params = string.match(forvo_page, "Play%((.-)%);")

        if play_params then
            local iter = string.gmatch(play_params, "'(.-)'")
            local formats = { mp3 = iter(), ogg = iter() }
            return string.format('https://audio00.forvo.com/%s/%s', file_format, base64d(formats[file_format]))
        end
    end

    local function make_forvo_filename(word)
        return string.format('forvo_%s%s', platform.windows and os.time() or word, config.audio_extension)
    end

    local function get_forvo_pronunciation(word)
        local audio_url = get_pronunciation_url(word)

        if is_empty(audio_url) then
            msg.warn(string.format("Seems like Forvo doesn't have audio for word %s.", word))
            return
        end

        local filename = make_forvo_filename(word)
        local tmp_filepath = utils.join_path(platform.tmp_dir(), filename)

        local result
        if curl_save(audio_url, tmp_filepath) and reencode_and_store(tmp_filepath, filename) then
            result = string.format('[sound:%s]', filename)
        else
            msg.warn(string.format("Couldn't download audio for word %s from Forvo.", word))
        end

        os.remove(tmp_filepath)
        return result
    end

    append_forvo_pronunciation = function(new_data, stored_data)
        if config.use_forvo == 'no' then
            -- forvo functionality was disabled in the config file
            return new_data
        end

        if type(stored_data[config.vocab_audio_field]) ~= 'string' then
            -- there is no field configured to store forvo pronunciation
            return new_data
        end

        if is_empty(stored_data[config.vocab_field]) then
            -- target word field is empty. can't continue.
            return new_data
        end

        if config.use_forvo == 'always' or is_empty(stored_data[config.vocab_audio_field]) then
            local forvo_pronunciation = get_forvo_pronunciation(stored_data[config.vocab_field])
            if not is_empty(forvo_pronunciation) then
                if config.vocab_audio_field == config.audio_field then
                    -- improperly configured fields. don't lose sentence audio
                    new_data[config.audio_field] = forvo_pronunciation .. new_data[config.audio_field]
                else
                    new_data[config.vocab_audio_field] = forvo_pronunciation
                end
            end
        end

        return new_data
    end
end

------------------------------------------------------------
-- provides interface for creating audio clips and snapshots

encoder = {}

encoder.pad_timings = function(start_time, end_time)
    local video_duration = mp.get_property_number('duration')
    if config.audio_padding == 0.0 or not video_duration then
        return start_time, end_time
    end
    if subs.user_timings.is_set('start') or subs.user_timings.is_set('end') then
        return start_time, end_time
    end
    start_time = start_time - config.audio_padding
    end_time = end_time + config.audio_padding
    if start_time < 0 then start_time = 0 end
    if end_time > video_duration then end_time = video_duration end
    return start_time, end_time
end

encoder.get_active_track = function(track_type)
    local track_list = mp.get_property_native('track-list')
    for _, track in pairs(track_list) do
        if track.type == track_type and track.selected == true then
            return track
        end
    end
    return nil
end

encoder.create_snapshot = function(timestamp, filename)
    local source_path = mp.get_property("path")
    local output_path = utils.join_path(platform.tmp_dir(), filename)

    local args = {
        'mpv',
        source_path,
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
        table.concat { '-o=', output_path }
    }
    local on_finish = function()
        ankiconnect.store_file(filename, output_path)
        os.remove(output_path)
    end
    subprocess(args, on_finish)
end

encoder.create_audio = function(start_timestamp, end_timestamp, filename)
    local source_path = mp.get_property("path")
    local audio_track = encoder.get_active_track('audio')
    local audio_track_id = mp.get_property("aid")
    local output_path = utils.join_path(platform.tmp_dir(), filename)

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'auto'
    end

    start_timestamp, end_timestamp = encoder.pad_timings(start_timestamp, end_timestamp)

    local args = {
        'mpv',
        source_path,
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
        table.concat { '--aid=', audio_track_id },
        table.concat { '--volume=', config.tie_volumes and mp.get_property('volume') or '100' },
        table.concat { '--oacopts-add=b=', config.audio_bitrate },
        table.concat { '-o=', output_path }
    }
    local on_finish = function()
        ankiconnect.store_file(filename, output_path)
        os.remove(output_path)
    end
    subprocess(args, on_finish)
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

ankiconnect.store_file = function(filename, file_path)
    local args = {
        action = "storeMediaFile",
        version = 6,
        params = {
            filename = filename,
            path = file_path
        }
    }

    local ret =  ankiconnect.execute(args)
    local _, error = ankiconnect.parse_result(ret)
    if not error then
        msg.info(string.format("File stored: '%s'.", filename))
        return true
    else
        msg.error(string.format("Couldn't store file '%s': %s", filename, error))
        return false
    end
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

ankiconnect.append_media = function(note_id, fields, create_media_fn)
    -- AnkiConnect will fail to update the note if it's selected in the Anki Browser.
    -- https://github.com/FooSoft/anki-connect/issues/82
    -- Switch focus from the current note to avoid it.
    ankiconnect.gui_browse("nid:1") -- impossible nid

    local args = {
        action = "updateNoteFields",
        version = 6,
        params = {
            note = {
                id = note_id,
                fields = fields,
            }
        }
    }

    local on_finish = function(_, result, _)
        local _, error = ankiconnect.parse_result(result)
        if not error then
            create_media_fn()
            ankiconnect.gui_browse(string.format("nid:%s", note_id)) -- select the updated note in the card browser
            notify(string.format("Note #%s updated.", note_id))
        else
            notify(string.format("Error: %s.", error), "error", 2)
        end
    end

    ankiconnect.execute(args, on_finish)
end

------------------------------------------------------------
-- subtitles and timings

subs = {
    dialogs = new_sub_list(),
    user_timings = new_timings(),
    observed = false
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
    if subs.user_timings.is_set(position) then
        return subs.user_timings.get(position)
    elseif not subs.dialogs.is_empty() then
        return subs.dialogs.get_time(position)
    end
    return -1
end

subs.get = function()
    if subs.dialogs.is_empty() then
        subs.dialogs.insert(subs.get_current())
    end
    local sub = Subtitle:new {
        ['text'] = subs.dialogs.get_text(),
        ['start'] = subs.get_timing('start'),
        ['end'] = subs.get_timing('end'),
    }
    if sub['start'] < 0 or sub['end'] < 0 then
        return nil
    end
    if sub['start'] == sub['end'] then
        return nil
    end
    if sub['start'] > sub['end'] then
        sub['start'], sub['end'] = sub['end'], sub['start']
    end
    if not is_empty(sub['text']) then
        sub['text'] = trim(sub['text'])
        sub['text'] = escape_special_characters(sub['text'])
    end
    return sub
end

subs.append = function()
    if subs.dialogs.insert(subs.get_current()) then
        menu.update()
    end
end

subs.observe = function()
    mp.observe_property("sub-text", "string", subs.append)
    subs.observed = true
end

subs.unobserve = function()
    mp.unobserve_property(subs.append)
    subs.observed = false
end

subs.set_timing = function(position)
    subs.user_timings.set(position)
    menu.update()
    notify(capitalize_first_letter(position) .. " time has been set.")
    if not subs.observed then
        subs.observe()
    end
end

subs.set_starting_line = function()
    subs.clear()
    if not is_empty(mp.get_property("sub-text")) then
        subs.observe()
        notify("Timings have been set to the current sub.", "info", 2)
    else
        notify("There's no visible subtitle.", "info", 2)
    end
end

subs.clear = function()
    subs.unobserve()
    subs.dialogs = new_sub_list()
    subs.user_timings = new_timings()
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
    mp.observe_property("sub-text", "string", copy_to_clipboard)
    notify("Clipboard autocopy has been enabled.", "info", 1)
end

clip_autocopy.disable = function()
    mp.unobserve_property(copy_to_clipboard)
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
    return config.autoclip == true and 'enabled' or 'disabled'
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
    hints_state = make_switch { 'hidden', 'menu', 'global', },
    overlay = mp.create_osd_overlay and mp.create_osd_overlay('ass-events'),
}

menu.overlay_draw = function(text)
    menu.overlay.data = text
    menu.overlay:update()
end

menu.keybindings = {
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

    local osd = OSD:new():size(config.menu_font_size):align(4)
    osd:submenu('mpvacious options'):newline()
    osd:item('Start time: '):text(human_readable_time(subs.get_timing('start'))):newline()
    osd:item('End time: '):text(human_readable_time(subs.get_timing('end'))):newline()
    osd:item('Clipboard autocopy: '):text(clip_autocopy.is_enabled()):newline()

    if menu.hints_state.get() == 'global' then
        osd:submenu('Global bindings'):newline()
        osd:tab():item('ctrl+c: '):text('Copy current subtitle to clipboard'):newline()
        osd:tab():item('ctrl+h: '):text('Seek to the start of the line'):newline()
        osd:tab():item('ctrl+shift+h: '):text('Replay current subtitle'):newline()
        osd:tab():item('shift+h/l: '):text('Seek to the previous/next subtitle'):newline()
        osd:tab():item('alt+h/l: '):text('Seek to the previous/next subtitle and pause'):newline()
        osd:italics("Press "):item('i'):italics(" to hide bindings."):newline()
    elseif menu.hints_state.get() == 'menu' then
        osd:submenu('Menu bindings'):newline()
        osd:tab():item('c: '):text('Set timings to the current sub'):newline()
        osd:tab():item('s: '):text('Set start time to current position'):newline()
        osd:tab():item('e: '):text('Set end time to current position'):newline()
        osd:tab():item('r: '):text('Reset timings'):newline()
        osd:tab():item('n: '):text('Export note'):newline()
        osd:tab():item('g: '):text('GUI export'):newline()
        osd:tab():item('m: '):text('Update the last added note '):italics('(+shift to overwrite)'):newline()
        osd:tab():item('t: '):text('Toggle clipboard autocopy'):newline()
        osd:tab():item('ESC: '):text('Close'):newline()
        osd:italics("Press "):item('i'):italics(" to show global bindings."):newline()
    else
        osd:italics("Press "):item('i'):italics(" to show menu bindings."):newline()
    end

    menu.overlay_draw(osd:get_text())
end

menu.hints_toggle = function()
    menu.hints_state.bump()
    menu.update()
end

menu.open = function()
    if menu.overlay == nil then
        notify("OSD overlay is not supported in " .. mp.get_property("mpv-version"), "error", 5)
        return
    end

    if menu.active == true then
        menu.close()
        return
    end

    for _, val in pairs(menu.keybindings) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end

    menu.active = true
    menu.update()
end

menu.close = function()
    if menu.active == false then
        return
    end

    for _, val in pairs(menu.keybindings) do
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

local main
do
    local main_executed = false
    main = function()
        if main_executed then return end
        validate_config()
        ankiconnect.create_deck(config.deck_name)
        if config.autoclip == true then clip_autocopy.enable() end

        -- Key bindings
        mp.add_forced_key_binding("ctrl+e", "mpvacious-export-note", export_to_anki)
        mp.add_forced_key_binding("ctrl+c", "mpvacious-copy-sub-to-clipboard", copy_sub_to_clipboard)
        mp.add_key_binding("a", "mpvacious-menu-open", menu.open) -- a for advanced

        -- Vim-like seeking between subtitle lines
        mp.add_key_binding("H", "mpvacious-sub-seek-back", _ { sub_seek, 'backward' })
        mp.add_key_binding("L", "mpvacious-sub-seek-forward", _ { sub_seek, 'forward' })

        mp.add_key_binding("Alt+h", "mpvacious-sub-seek-back-pause", _ { sub_seek, 'backward', true })
        mp.add_key_binding("Alt+l", "mpvacious-sub-seek-forward-pause", _ { sub_seek, 'forward', true })

        mp.add_key_binding("ctrl+h", "mpvacious-sub-rewind", _ { sub_rewind })
        mp.add_key_binding("ctrl+H", "mpvacious-sub-replay", _ { sub_replay })

        -- Unset by default
        mp.add_key_binding(nil, "mpvacious-set-starting-line", subs.set_starting_line)
        mp.add_key_binding(nil, "mpvacious-reset-timings", subs.clear_and_notify)
        mp.add_key_binding(nil, "mpvacious-toggle-sub-autocopy", clip_autocopy.toggle)
        mp.add_key_binding(nil, "mpvacious-update-last-note", update_last_note)

        main_executed = true
    end
end
mp.register_event("file-loaded", main)
