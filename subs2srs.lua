-- Usage:
-- 1. Change `config` according to your needs
-- * Options can be changed right in this file or in a separate config file.
-- * Config path: ~/.config/mpv/script-opts/subs2srs.conf
-- * Config file isn't created automatically.
--
-- 2. Open a video
-- 3. Use key bindings to manipulate the script
-- * `Ctrl + e` - Creates a note from the current sub.
-- * `a` - Opens advanced options.
--   There you can adjust and reset timings,
--   concatenate subtitle lines, toggle clipboard auto copy, and more.

-- Requirements:
-- * FFmpeg
-- * AnkiConnect

local config = {
    collection_path = string.format('%s/.local/share/Anki2/%s/collection.media/', os.getenv("HOME"), os.getenv("USER")),
    autoclip = false,           -- copy subs to the clipboard or not
    nuke_spaces = true,         -- remove all spaces or not
    snapshot_quality = 5,       -- from 0=lowest to 100=highest
    snapshot_width = -2,        -- a positive integer or -2 for auto
    snapshot_height = 200,      -- same
    audio_bitrate = "18k",      -- from 16k to 32k
    deck_name = "Learning",     -- the deck will be created if needed
    model_name = "Japanese sentences", -- Tools -> Manage note types
    sentence_field = "SentKanji",
    audio_field = "SentAudio",
    image_field = "Image",
    menu_font_size = 24,
}

local utils = require('mp.utils')
local msg = require('mp.msg')
local mpopt = require('mp.options')

mpopt.read_options(config, "subs2srs")

-- namespaces
local subs
local clip_autocopy
local ffmpeg
local ankiconnect
local menu

-- classes
local Subtitle
local OSD

------------------------------------------------------------
-- utility functions

function string:endswith(suffix)
    return self:match(string.format('%s$', suffix))
end

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local function check_config_sanity()
    if not config.collection_path:endswith('/') then
        -- The user forgot to add a slash at the end of the collection path
        config.collection_path = config.collection_path .. '/'
    end

    if config.snapshot_width < 1 then
        config.snapshot_width = -2
    end

    if config.snapshot_height < 1 then
        config.snapshot_height = -2
    end

    if config.snapshot_width > 800 then
        config.snapshot_width = 800
    end

    if config.snapshot_height > 800 then
        config.snapshot_height = 800
    end

    if config.snapshot_width < 1 and config.snapshot_height < 1 then
        config.snapshot_width = -2
        config.snapshot_height = 200
        mp.osd_message("`snapshot_width` and `snapshot_height` can't be both less than 1.", 5)
    end

    if config.snapshot_quality < 0 or config.snapshot_quality > 100 then
        config.snapshot_quality = 5
    end
end

local function is_emptystring(str)
    return str == nil or str == ''
end

local function is_emptytable(tab)
    return tab == nil or next(tab) == nil
end

local function add_extension(filename, extension)
    return filename .. extension
end

local function remove_extension(filename)
    return filename:gsub('%.%w+$','')
end

local function remove_special_characters(str)
    return str:gsub('[%c%p%s]',''):gsub('　', '')
end

local function remove_text_in_brackets(str)
    return str:gsub('%b[]',''):gsub('【.-】', '')
end

local function remove_text_in_parentheses(str)
    -- Remove text like （泣き声） or （ドアの開く音）
    -- Note: the modifier `-´ matches zero or more occurrences.
    -- However, instead of matching the longest sequence, it matches the shortest one.
    return str:gsub('%b()',''):gsub('（.-）','')
end

local function remove_newlines(str)
    return str:gsub('[\n\r]+',' ')
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

local function copy_to_clipboard(_, text)
    -- roughly called as in fn(name, mp.get_property_string(name))
    if is_emptystring(text) then
        return
    end

    local toclip_path = os.getenv("HOME") .. '/.config/mpv/scripts/subs2srs/toclip.sh'
    mp.commandv("run", "sh", toclip_path, text)
end

local function copy_sub_to_clipboard()
    copy_to_clipboard("copy-on-demand", mp.get_property("sub-text"))
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

local function human_readable_time(seconds)
    if type(seconds) ~= 'number' or seconds < 0 then
        return 'empty'
    end

    local parts = {}

    parts.h = math.floor(seconds / 3600)
    parts.m = math.floor(seconds / 60) % 60
    parts.s = math.floor(seconds % 60)
    parts.ms = math.floor((seconds * 1000) % 1000)

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format('%dh%s', parts.h, ret)
    end

    return ret
end

local function subprocess(args)
    return mp.command_native {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = args
    }
end

local function anki_compatible_length(str)
    -- anki forcibly mutilates all filenames longer than 64 characters
    -- leave 25 characters for the filename
    -- the rest is reserved for the timestamp, which is added later

    local ret = subprocess {
        'awk',
        '-v', string.format('str=%s', str),
        '-v', 'limit=25',
        'BEGIN{print substr(str, 1, limit); exit}'
    }

    if ret.status == 0 then
        ret.stdout = remove_newlines(ret.stdout)
        ret.stdout = remove_leading_trailing_spaces(ret.stdout)
        return ret.stdout
    else
        return 'subs2srs'
    end
end

local function construct_filename(sub)
    local filename = mp.get_property("filename") -- filename without path

    filename = remove_extension(filename)
    filename = remove_text_in_brackets(filename)
    filename = remove_special_characters(filename)

    if contains_non_latin_letters(filename) then
        filename = anki_compatible_length(filename)
    end

    filename = string.format(
            '%s_(%s-%s)',
            filename,
            human_readable_time(sub['start']),
            human_readable_time(sub['end'])
    )

    return filename
end

local function get_audio_track_number()
    local audio_track_number = 0
    local tracks_count = mp.get_property_number("track-list/count")

    for i = 1, tracks_count do
        local track_type = mp.get_property(string.format("track-list/%d/type", i))
        local track_index = mp.get_property_number(string.format("track-list/%d/ff-index", i))
        local track_selected = mp.get_property(string.format("track-list/%d/selected", i))

        if track_type == "audio" and track_selected == "yes" then
            audio_track_number = track_index
            break
        end
    end
    return audio_track_number
end

local function sub_rewind()
    pcall(
        function ()
            local sub_start_time = subs.get_current()['start']
            mp.commandv('seek', sub_start_time, 'absolute')
        end
    )
end

local function minutes_ago(m)
    return (os.time() - 60 * m) * 1000
end

local function export_to_anki(gui)
    local sub = subs.get()
    subs.clear()
    menu.close()

    if sub ~= nil then
        local filename = construct_filename(sub)
        local snapshot_filename = add_extension(filename, '.webp')
        local audio_filename = add_extension(filename, '.ogg')
        local snapshot_timestamp = (sub['start'] + sub['end']) / 2

        ffmpeg.create_snapshot(snapshot_timestamp, snapshot_filename)
        ffmpeg.create_audio(sub['start'], sub['end'], audio_filename)

        ankiconnect.add_note(sub['text'], audio_filename, snapshot_filename, gui)
    else
        msg.warn("Nothing to export.")
        mp.osd_message("Nothing to export.", 1)
    end
end

local function update_last_note()
    local sub = subs.get()
    local last_note_id = ankiconnect.get_last_note_id()
    subs.clear()
    menu.close()

    if sub == nil then
        msg.warn("Nothing to export.")
        mp.osd_message("Nothing to export. Have you set the timings?", 2)
        return
    end

    if last_note_id < minutes_ago(10) then
        msg.error("Couldn't find the target note.")
        mp.osd_message("Couldn't find the target note.", 2)
        return
    end

    local filename = construct_filename(sub)
    local snapshot_filename = add_extension(filename, '.webp')
    local audio_filename = add_extension(filename, '.ogg')
    local snapshot_timestamp = (sub['start'] + sub['end']) / 2

    ffmpeg.create_snapshot(snapshot_timestamp, snapshot_filename)
    ffmpeg.create_audio(sub['start'], sub['end'], audio_filename)
    ankiconnect.append_media(last_note_id, audio_filename, snapshot_filename)
end

local function get_empty_timings()
    return {
        ['start'] = -1,
        ['end'] = -1,
    }
end

------------------------------------------------------------
-- ffmpeg helper

ffmpeg = {}

ffmpeg.prefix = {"ffmpeg", "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet"}

ffmpeg.execute = function(args)
    if next(args) ~= nil then
        for i, value in ipairs(ffmpeg.prefix) do
            table.insert(args, i, value)
        end

        mp.commandv("run", table.unpack(args))
    end
end

ffmpeg.create_snapshot = function(timestamp, filename)
    local video_path = mp.get_property("path")
    local snapshot_path = config.collection_path .. filename

    ffmpeg.execute {
        '-an',
        '-ss', tostring(timestamp),
        '-i', video_path,
        '-vcodec', 'libwebp',
        '-lossless', '0',
        '-compression_level', '6',
        '-qscale:v', tostring(config.snapshot_quality),
        '-vf', string.format('scale=%d:%d', config.snapshot_width, config.snapshot_height),
        '-vframes', '1',
        snapshot_path
    }
end

ffmpeg.create_audio = function(start_timestamp, end_timestamp, filename)
    local video_path = mp.get_property("path")
    local fragment_path = config.collection_path .. filename
    local track_number = get_audio_track_number()

    ffmpeg.execute{
        '-vn',
        '-ss', tostring(start_timestamp),
        '-to', tostring(end_timestamp),
        '-i', video_path,
        '-map_metadata', '-1',
        '-map', string.format("0:%d", track_number),
        '-ac', '1',
        '-codec:a', 'libopus',
        '-vbr', 'on',
        '-compression_level', '10',
        '-application', 'voip',
        '-b:a', tostring(config.audio_bitrate),
        fragment_path
    }
end

------------------------------------------------------------
-- AnkiConnect requests

ankiconnect = {}

ankiconnect.execute = function(request)
    -- utils.format_json returns a string
    -- On error, request_json will contain "null", not nil.
    local request_json, error = utils.format_json(request)

    if error ~= nil or request_json == "null" then
        msg.error("Couldn't parse request.")
        return nil
    end

    return subprocess { 'curl', '-s', 'localhost:8765', '-X', 'POST', '-d', request_json }
end

ankiconnect.parse_result = function(curl_output)
    -- there are two values that we actually care about: result and error
    -- but we need to crawl inside to get them.

    if curl_output == nil then
        return nil, "Failed to format json"
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

ankiconnect.create_deck_if_doesnt_exist = function(deck_name)
    local args = {
        action = "changeDeck",
        version = 6,
        params = {
            cards = {},
            deck = deck_name
        }
    }

    ankiconnect.execute(args)
end

ankiconnect.add_note = function(subtitle_string, audio_filename, snapshot_filename, gui)
    local action
    if gui then
        action = 'guiAddCards'
    else
        action = 'addNote'
    end

    local args = {
        action = action,
        version = 6,
        params = {
            note = {
                deckName = config.deck_name,
                modelName = config.model_name,
                fields = {
                    [config.sentence_field] = subtitle_string,
                    [config.audio_field] = string.format('[sound:%s]', audio_filename),
                    [config.image_field] = string.format('<img src="%s" alt="snapshot">', snapshot_filename),
                },
                options = {
                    allowDuplicate = false,
                    duplicateScope = "deck",
                },
                tags = { "subs2srs" }
            }
        }
    }

    local ret = ankiconnect.execute(args)
    local result, error = ankiconnect.parse_result(ret)
    local message = ''

    if error == nil then
        message = string.format("Note added. ID = %s.", result)
        print(message)
        mp.osd_message(message, 1)
    else
        message = string.format("Error: %s.", error)
        msg.error(message)
        mp.osd_message(message, 2)
    end
end

ankiconnect.get_last_note_id = function()
    local args = {
        action = "findNotes",
        version = 6,
        params = {
            query = "added:1" -- find all notes added today
        }
    }

    local ret = ankiconnect.execute(args)
    local note_ids, _ = ankiconnect.parse_result(ret)

    if note_ids ~= nil then
        local last_note_id = math.max(table.unpack(note_ids))
        return last_note_id
    else
        return -1
    end
end

ankiconnect.get_note_fields = function(note_id)
    local result, error = ankiconnect.parse_result(ankiconnect.execute {
        action = "notesInfo",
        version = 6,
        params = {
            notes = { note_id }
        }
    })

    if error == nil then
        result = result[1].fields
        for key,value in pairs(result) do result[key] = value.value end
        return result
    else
        return nil
    end
end

ankiconnect.append_media = function(note_id, audio_filename, snapshot_filename)
    -- AnkiConnect will fail to update the note if the Anki Browser is open.
    -- First, try to close the Anki Browser.
    -- https://github.com/FooSoft/anki-connect/issues/82
    subprocess {
        'xdotool',
        'search',
        '--name',
        [[Browse \([0-9]{1,} cards? shown; [0-9]{1,} selected\)]],
        'key',
        'Escape'
    }

    local audio_field = string.format('[sound:%s]', audio_filename)
    local image_field = string.format('<img src="%s" alt="snapshot">', snapshot_filename)

    local args = {
        action = "updateNoteFields",
        version = 6,
        params = {
            note = {
                id = note_id,
                fields = {
                    [config.audio_field] = audio_field,
                    [config.image_field] = image_field,
                },
            }
        }
    }

    local ret = ankiconnect.execute(args)
    local _, error = ankiconnect.parse_result(ret)
    local message = ''

    if error == nil then
        message = string.format("Note #%d updated.", note_id)
        print(message)
        mp.osd_message(message, 1)
    else
        message = string.format("Error: %s.", error)
        msg.error(message)
        mp.osd_message(message, 2)
    end
end

------------------------------------------------------------
-- subtitles and timings

subs = {}

subs.list = {}

subs.user_timings = get_empty_timings()

subs.get_current = function()
    local sub_text = mp.get_property("sub-text")

    if is_emptystring(sub_text) then
        return nil
    end

    local sub_delay = mp.get_property_native("sub-delay")

    return Subtitle:new{
        ['text']   = trim(sub_text),
        ['start']  = mp.get_property_number("sub-start") + sub_delay,
        ['end']    = mp.get_property_number("sub-end")   + sub_delay
    }
end

subs.get_timing = function(position)
    if subs.user_timings[position] >= 0 then
        return subs.user_timings[position]
    end

    if is_emptytable(subs.list) then
        return nil
    end

    if position == 'start' then
        return subs.list[1]['start']
    elseif position == 'end' then
        return subs.list[#subs.list]['end']
    end
end

subs.get_text = function()
    local text = ''
    for _, value in ipairs(subs.list) do
        text = text .. value['text']
    end
    return text
end

subs.get = function()
    if is_emptytable(subs.list) then
        return subs.get_current()
    end

    table.sort(subs.list)

    local sub = Subtitle:new {
        ['text'] = subs.get_text(),
        ['start'] = subs.get_timing('start'),
        ['end'] = subs.get_timing('end'),
    }

    if is_emptystring(sub['text']) then
        return nil
    end

    if sub['start'] >= sub['end'] then
        msg.warn("First line can't start later or at the same time than last one ends.")
        return nil
    end

    return sub
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
    local time_human = human_readable_time(subs.user_timings[position])

    if is_emptytable(subs.list) then
        mp.observe_property("sub-text", "string", subs.append)
    end

    menu.update()
    mp.osd_message(string.format("%s is set to %s.", position, time_human), 2)
end

subs.set_starting_line = function()
    subs.clear()

    local current_sub = subs.get_current()

    if current_sub ~= nil then
        mp.observe_property("sub-text", "string", subs.append)
        local starting_point = human_readable_time(current_sub['start'])
        mp.osd_message("Starting point is set to " .. starting_point, 2)
    else
        mp.osd_message("There's no visible subtitle.", 2)
    end
end

subs.clear = function()
    mp.unobserve_property(subs.append)
    subs.list = {}
    subs.user_timings = get_empty_timings()
end

subs.reset_timings = function()
    subs.clear()
    menu.update()
    mp.osd_message("Timings have been reset.", 2)
end

------------------------------------------------------------
-- send subs to clipboard as they appear

clip_autocopy = {}

clip_autocopy.enable = function()
    mp.observe_property("sub-text", "string", copy_to_clipboard)
    mp.osd_message("Clipboard autocopy is enabled.", 1)
end

clip_autocopy.disable = function()
    mp.unobserve_property(copy_to_clipboard)
    mp.osd_message("Clipboard autocopy is disabled.", 1)
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

clip_autocopy.enabled = function()
    if config.autoclip == true then
        return 'enabled'
    else
        return 'disabled'
    end
end

------------------------------------------------------------
-- Subtitle class provides methods for comparing subtitle lines

Subtitle = {
    ['text']   = '',
    ['start']  = -1,
    ['end']    = -1,
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

Subtitle.__lt = function (lhs, rhs)
    return lhs['start'] < rhs['start']
end

------------------------------------------------------------
-- main menu

menu = {}

menu.active = false

menu.overlay = mp.create_osd_overlay and mp.create_osd_overlay('ass-events')

menu.overlay_draw = function(text)
    menu.overlay.data = text
    menu.overlay:update()
end

menu.keybinds = {
    { key = 's', fn = function() subs.set_timing('start') end },
    { key = 'e', fn = function() subs.set_timing('end') end },
    { key = 'c', fn = function() subs.set_starting_line() end },
    { key = 'r', fn = function() subs.reset_timings() end },
    { key = 'g', fn = function() export_to_anki(true) end },
    { key = 'n', fn = function() export_to_anki() end },
    { key = 'm', fn = function() update_last_note() end },
    { key = 't', fn = function() clip_autocopy.toggle() end },
    { key = 'ESC', fn = function() menu.close() end },
}

menu.update = function()
    if menu.active == false then
        return
    end

    table.sort(subs.list)
    local osd = OSD:new():size(config.menu_font_size):align(4)
    osd:bold('mpvacious: advanced options'):newline()
    osd:newline()

    osd:bold('Start time: '):append(human_readable_time(subs.get_timing('start'))):newline()
    osd:bold('End time: '):append(human_readable_time(subs.get_timing('end'))):newline()
    osd:bold('Clipboard autocopy: '):append(clip_autocopy.enabled()):newline()
    osd:newline()

    osd:bold('Menu bindings:'):newline()
    osd:tab():bold('c: '):append('Set timings to the current sub'):newline()
    osd:tab():bold('s: '):append('Set start time to current position'):newline()
    osd:tab():bold('e: '):append('Set end time to current position'):newline()
    osd:tab():bold('r: '):append('Reset timings'):newline()
    osd:tab():bold('n: '):append('Export note'):newline()
    osd:tab():bold('g: '):append('Export note using the `Add Cards` GUI'):newline()
    osd:tab():bold('m: '):append('Add audio and image to the last added note'):newline()
    osd:tab():bold('t: '):append('Toggle clipboard autocopy'):newline()
    osd:tab():bold('ESC: '):append('Close'):newline()
    osd:newline()

    osd:bold('Global bindings:'):newline()
    osd:tab():bold('ctrl+e: '):append('Export note'):newline()
    osd:tab():bold('ctrl+h: '):append('Seek to the start of the line'):newline()
    osd:tab():bold('ctrl+c: '):append('Copy current subtitle to clipboard'):newline()

    menu.overlay_draw(osd.text)
end

menu.open = function()
    if menu.overlay == nil then
        local message = "OSD overlay is not supported in this version of mpv."
        mp.osd_message(message, 5)
        msg.error(message)
        return
    end

    if menu.active == true then
        return
    end

    for _, val in pairs(menu.keybinds) do
        mp.add_key_binding(val.key, val.key, val.fn)
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
    return setmetatable({ text = '' }, self)
end

function OSD:append(s)
    self.text = self.text .. s
    return self
end

function OSD:bold(s)
    return self:append('{\\b1}' .. s .. '{\\b0}')
end

function OSD:italics(s)
    return self:append('{\\i1}' .. s .. '{\\i0}')
end

function OSD:newline()
    return self:append('\\N')
end

function OSD:tab()
    return self:append('\\h\\h\\h\\h')
end

function OSD:size(size)
    return self:append('{\\fs' .. size .. '}')
end

function OSD:align(number)
    return self:append('{\\an' .. number .. '}')
end

------------------------------------------------------------
-- main

if config.autoclip == true then
    clip_autocopy.enable()
end

check_config_sanity()
ankiconnect.create_deck_if_doesnt_exist(config.deck_name)
mp.add_key_binding('a', 'mpvacious-menu-open', menu.open) -- a for advanced
mp.add_key_binding("ctrl+e", "anki-export-note", export_to_anki)
mp.add_key_binding("ctrl+h", "sub-rewind", sub_rewind)
mp.add_key_binding("ctrl+c", "copy-sub-to-clipboard", copy_sub_to_clipboard)
mp.add_key_binding(nil, "set-starting-line", subs.set_starting_line)
mp.add_key_binding(nil, "reset-timings", subs.reset_timings)
mp.add_key_binding(nil, "toggle-sub-autocopy", clip_autocopy.toggle)
