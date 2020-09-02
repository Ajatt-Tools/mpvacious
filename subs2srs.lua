-- Usage:
-- 1. Change `config` according to your needs
-- * Options can be changed right in this file or in a separate config file.
-- * Config path: ~/.config/mpv/script-opts/subs2srs.conf
-- * Config file isn't created automatically.
--
-- 2. Open a video
-- 3.
-- * `Ctrl + e` creates a note from the current sub.
-- * `Ctrl + s` sets a starting line of the note (then continue watching and press `Ctrl + e` to set the ending line)
-- * `Ctrl + t` toggles clipboard autocopy (to use with Yomichan)

-- Requirements:
-- * ffmpeg
-- * ankiconnect

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
local overlay = mp.create_osd_overlay('ass-events')

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

    if config.snapshot_width  < 1 then config.snapshot_width  = -2 end
    if config.snapshot_height < 1 then config.snapshot_height = -2 end

    if config.snapshot_width  > 800 then config.snapshot_width  = 800 end
    if config.snapshot_height > 800 then config.snapshot_height = 800 end

    if config.snapshot_width < 1 and config.snapshot_height < 1 then
        config.snapshot_width  = -2
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

local function copy_to_clipboard(text)
    local toclip_path = os.getenv("HOME") .. '/.config/mpv/scripts/subs2srs/toclip.sh'
    mp.commandv("run", "sh", toclip_path, text)
end

local function set_clipboard(name, sub)
    if is_emptystring(sub) then return end
    copy_to_clipboard(sub)
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

    parts.h  = math.floor(seconds / 3600)
    parts.m  = math.floor(seconds / 60) % 60
    parts.s  = math.floor(seconds % 60)
    parts.ms = math.floor((seconds * 1000) % 1000)

    local ret = string.format("%02dm%02ds%03dms", parts.m, parts.s, parts.ms)

    if parts.h > 0 then
        ret = string.format('%dh%s', parts.h, ret)
    end

    return ret
end

local function anki_compatible_length(str)
    -- anki forcibly mutilates all filenames longer than 64 characters
    -- leave 25 characters for the filename
    -- the rest is reserved for the timestamp, which is added later
    local args = {
        'awk',
        '-v', string.format('str=%s', str),
        '-v', 'limit=25',
        'BEGIN{print substr(str, 1, limit); exit}'
    }

    local ret = mp.command_native{
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = args
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

local function export_to_anki(gui)
    local sub = subs.get()
    subs.clear()

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

------------------------------------------------------------
-- ffmpeg helper

ffmpeg = {}

ffmpeg.prefix = {"ffmpeg", "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet"}

ffmpeg.execute = function(args)
    if next(args) ~= nil then
        for i, value in ipairs(ffmpeg.prefix) do
            table.insert(args, i, value)
        end

        mp.commandv("run", unpack(args))
    end
end

ffmpeg.create_snapshot = function(timestamp, filename)
    local video_path = mp.get_property("path")
    local snapshot_path = config.collection_path .. filename

    ffmpeg.execute{
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
-- ankiconnect requests

ankiconnect = {}

ankiconnect.execute = function(request)
    local request_json, error = utils.format_json(request)

    if error ~= nil or request_json == "null" then
        msg.error("Couldn't parse request.")
        return
    end

    local args = {'curl', '-s', 'localhost:8765', '-X', 'POST', '-d', request_json}

    local ret = mp.command_native{
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        args = args
    }

    return ret
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
                deckName  = config.deck_name,
                modelName = config.model_name,
                fields = {
                    [config.sentence_field] = subtitle_string,
                    [config.audio_field]    = '[sound:' .. audio_filename .. ']',
                    [config.image_field]    = '<img src="' .. snapshot_filename .. '">'
                },
                options = {
                    allowDuplicate = false,
                    duplicateScope = "deck"
                },
                tags = {"subs2srs"}
            }
        }
    }

    local ret = ankiconnect.execute(args)

    if ret.status ~= 0 then
        msg.error("Error: Ankiconnect isn't running.")
        mp.osd_message("Error: Ankiconnect isn't running.", 1)
        return
    end

    ret.json = utils.parse_json(ret.stdout)

    if ret.json == nil then
        msg.error("Fatal error from Ankiconnect.")
        mp.osd_message("Fatal error from Ankiconnect.", 2)
    end

    if ret.json.error == nil then
        mp.osd_message("Note added. ID = " .. ret.json.result, 1)
    else
        mp.osd_message("Error: " .. ret.json.error, 1)
    end

    for k, v in pairs(ret.json) do print(k, '=', v) end
end

------------------------------------------------------------
-- subtitles and timings

subs = {}

subs.list = {}

subs.user_timings = {
    ['start'] = 0,
    ['end'] = 0,
}

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
    if subs.user_timings[position] > 0 then
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
    for index, value in ipairs(subs.list) do
        text = text .. value['text']
    end
    return text
end

subs.get = function()
    if is_emptytable(subs.list) then
        return subs.get_current()
    end

    table.sort(subs.list)

    local sub = Subtitle:new{
        ['text']  = subs.get_text(),
        ['start'] = subs.get_timing('start'),
        ['end']   = subs.get_timing('end'),
    }

    if is_emptystring(sub['text']) then
        return nil
    end

    if sub['start'] > sub['end'] then
        msg.warn("First line can't start later than last one ends.")
        return nil
    end

    return sub
end

subs.append = function()
    local sub = subs.get_current()

    if sub ~= nil and not table.contains(subs.list, sub) then
        table.insert(subs.list, sub)
    end
end

subs.set_timing = function(position)
    subs.user_timings[position] = mp.get_property_number('time-pos')

    if is_emptytable(subs.list) then
        mp.observe_property("sub-text", "string", subs.append)
    end
end

subs.set_starting_line = function()
    subs.clear()

    local current_sub = subs.get_current()

    if current_sub ~= nil then
        local starting_point = human_readable_time(current_sub['start'])
        mp.osd_message("Starting point is set to " .. starting_point, 2)
        mp.observe_property("sub-text", "string", subs.append)
    else
        mp.osd_message("There's no visible subtitle.", 2)
    end
end

subs.clear = function()
    mp.unobserve_property(subs.append)
    subs.list = {}
    subs.user_timings = {
        ['start'] = 0,
        ['end'] = 0,
    }
end

subs.reset_timings = function()
    subs.clear()
    mp.osd_message("Timings have been reset.", 2)
end

------------------------------------------------------------
-- send subs to clipboard as they appear

clip_autocopy = {}

clip_autocopy.enable = function()
    mp.observe_property("sub-text", "string", set_clipboard)
    mp.osd_message("Clipboard autocopy is enabled.", 1)
end

clip_autocopy.disable = function()
    mp.unobserve_property(set_clipboard)
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
end

------------------------------------------------------------
-- Subtitle class provides methods for comparing subtitle lines

Subtitle = {
    ['text']   = '',
    ['start']  = 0,
    ['end']    = 0,
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

menu.keybinds = {
    { key = 's', fn = function() subs.set_timing('start'); menu.update() end },
    { key = 'e', fn = function() subs.set_timing('end'); menu.update() end },
    { key = 'g', fn = function() menu.close(); export_to_anki(true) end },
    { key = 'a', fn = function() menu.close() end },
    { key = 'ESC', fn = function() menu.close() end },
}

menu.update = function(message)
    table.sort(subs.list)
    local osd = OSD:new():size(config.menu_font_size)
    osd:bold('mpvacious: advanced options'):newline()
    osd:newline()
    osd:bold('Start time: '):append(human_readable_time(subs.get_timing('start'))):newline()
    osd:bold('End time: '):append(human_readable_time(subs.get_timing('end'))):newline()
    osd:newline()
    osd:bold('Menu bindings:'):newline()
    osd:tab():bold('s: '):append('Set start time to current position'):newline()
    osd:tab():bold('e: '):append('Set end time to current position'):newline()
    osd:tab():bold('g: '):append('Export note using the `Add Cards` dialog'):newline()
    osd:tab():bold('ESC: '):append('Close'):newline()
    osd:newline()
    osd:bold('Global bindings:'):newline()
    osd:tab():bold('ctrl+e: '):append('Export note'):newline()
    osd:tab():bold('ctrl+s: '):append('Set starting line'):newline()
    osd:tab():bold('ctrl+r: '):append('Reset timings'):newline()
    osd:tab():bold('ctrl+t '):append('Toggle sub autocopy'):newline()
    osd:tab():bold('ctrl+h '):append('Seek to the start of the line'):newline()
    osd:draw()
end

menu.close = function()
    for _, val in pairs(menu.keybinds) do
        mp.remove_key_binding(val.key)
    end
    mp.unobserve_property(menu.update)
    overlay:remove()
end

menu.open = function()
    for _, val in pairs(menu.keybinds) do
        mp.add_key_binding(val.key, val.key, val.fn)
    end
    menu.update()
    mp.observe_property("sub-text", "string", menu.update)
end

------------------------------------------------------------
-- Helper class for styling OSD messages

OSD = {}
OSD.__index = OSD

function OSD:new()
    return setmetatable({text=''}, self)
end

function OSD:append(s)
    self.text = self.text .. s
    return self
end

function OSD:bold(s)
    return self:append('{\\b1}' .. s .. '{\\b0}')
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

function OSD:draw()
    overlay.data = self.text
    overlay:update()
end

------------------------------------------------------------
-- main

if config.autoclip == true then clip_autocopy.enable() end

check_config_sanity()
ankiconnect.create_deck_if_doesnt_exist(config.deck_name)
mp.add_key_binding("ctrl+e", "anki-export-note", export_to_anki)
mp.add_key_binding("ctrl+s", "set-starting-line", subs.set_starting_line)
mp.add_key_binding("ctrl+r", "reset-timings", subs.reset_timings)
mp.add_key_binding("ctrl+t", "toggle-sub-autocopy", clip_autocopy.toggle)
mp.add_key_binding("ctrl+h", "sub-rewind", sub_rewind)

mp.add_key_binding('a', 'mpvacious-menu-open', menu.open) -- a for advanced
