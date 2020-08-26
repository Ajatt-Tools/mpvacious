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
    human_readable_time = true, -- use seconds if false
    snapshot_quality = 5,       -- from 0=lowest to 100=highest
    snapshot_width = -2,        -- a positive integer or -2 for auto
    snapshot_height = 200,      -- same
    audio_bitrate = "18k",      -- from 16k to 32k
    deck_name = "Learning",     -- the deck will be created if needed
    model_name = "Japanese sentences", -- Tools -> Manage note types
    sentence_field = "SentKanji",
    audio_field = "SentAudio",
    image_field = "Image",
}

local utils = require('mp.utils')
local msg = require('mp.msg')
local mpopt = require('mp.options')

mpopt.read_options(config, "subs2srs")

local subs
local clip_autocopy
local ffmpeg
local ankiconnect

------------------------------------------------------------
-- utility functions

local function check_config_sanity()
    if config.collection_path[-1] ~= '/' then
        -- The user forgot to add a slash at the end of the collection path
        config.collection_path = config.collection_path .. '/'
    end

    if config.snapshot_width  < 1 then config.snapshot_width  = -2 end
    if config.snapshot_height < 1 then config.snapshot_height = -2 end

    if config.snapshot_width  > 800 then config.snapshot_width  = 800 end
    if config.snapshot_height > 800 then config.snapshot_height = 800 end

    if config.snapshot_width < 1 and config.snapshot_height < 1 then
        config.snapshot_width = -2
        config.snapshot_height = 200
        mp.osd_message("`snapshot_width` and `snapshot_height` can't be both less than 1.", 5)
    end

    if config.snapshot_quality < 0 or config.snapshot_quality > 100 then
        config.snapshot_quality = 5
    end
end

local function split_str(str)
    t = {}
    str:gsub('[^%s]+', function(c) table.insert(t,c) end)
    return t
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
    return str:gsub('\r', ''):gsub('%s*\n', ' ')
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
        str = string.gsub(str, "%s*", "")
    else
        str = string.gsub(str, "^%s*(.-)%s*$", "%1")
    end

    return str
end

local function seconds_to_human_readable_time(time)
    local hours = math.floor(time / 3600)
    local mins = math.floor(time / 60) % 60
    local secs = math.floor(time % 60)
    local milliseconds = math.floor((time * 1000) % 1000)

    return string.format("%dh%02dm%02ds%03dms", hours, mins, secs, milliseconds)
end

local function format_time(time)
    if config.human_readable_time == true then
        return seconds_to_human_readable_time(time)
    else
        return string.format("%.3f", time)
    end
end

local function construct_filename(sub)
    local filename = mp.get_property("filename") -- filename without path

    filename = remove_extension(filename)
    filename = remove_text_in_brackets(filename)
    filename = remove_special_characters(filename)

    filename = string.format(
        '%s_(%s-%s)',
        filename,
        format_time(sub['start']),
        format_time(sub['end'])
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
            audio_track_number = track_index - 1
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

------------------------------------------------------------
-- ffmpeg helper

ffmpeg = {prefix = {"ffmpeg", "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet"}}

ffmpeg.execute = function(args)
    if next(args) ~= nil then
        for i, value in ipairs(ffmpeg.prefix) do
            table.insert(args, i, value)
        end

        mp.commandv("run", unpack(args))
    end
end

ffmpeg.create_snapshot = function(sub, snapshot_filename)
    local video_path = mp.get_property("path")
    local timestamp = tostring((sub['start'] + sub['end']) / 2)
    local snapshot_path = config.collection_path .. snapshot_filename

    ffmpeg.execute{'-an',
                    '-ss', timestamp,
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

ffmpeg.create_audio = function(sub, audio_filename)
    local video_path = mp.get_property("path")
    local fragment_path = config.collection_path .. audio_filename
    local track_number = get_audio_track_number()

    ffmpeg.execute{'-vn',
                    '-ss', tostring(sub['start']),
                    '-to', tostring(sub['end']),
                    '-i', video_path,
                    '-map_metadata', '-1',
                    '-map', string.format("0:a:%d", track_number),
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

ankiconnect.add_note = function(subtitle_string, audio_filename, snapshot_filename)
    local args = {
        action = "addNote",
        version = 6,
        params = {
            note = {
                deckName =  config.deck_name,
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

    for k, v in pairs(ret.json) do print(k, '=', v) end

    if ret.json.error == nil then
        mp.osd_message("Note added. ID = " .. ret.json.result, 1)
    else
        mp.osd_message("Error: " .. ret.json.error, 1)
    end
end

------------------------------------------------------------
-- subtitles and timings

subs = {list = {}}

subs.get_current = function()
    local sub_text = mp.get_property("sub-text")

    if is_emptystring(sub_text) then
        return nil
    end

    local sub_delay = mp.get_property_native("sub-delay")

    return {
        ['text']   = trim(sub_text),
        ['start']  = mp.get_property_number("sub-start") + sub_delay,
        ['end']    = mp.get_property_number("sub-end")   + sub_delay
    }
end

subs.get = function()
    if is_emptytable(subs.list) then
        return subs.get_current()
    end

    local sub = {
        ['text'] = '',
        ['start'] = subs.list[1]['start'],
        ['end'] = subs.list[#subs.list]['end'],
    }

    if sub['start'] > sub['end'] then
        msg.warn("First line can't start later than last one ends.")
        return nil
    end

    for index, value in ipairs(subs.list) do
        sub['text'] = sub['text'] .. value['text']
    end

    return sub
end

subs.append = function()
    local sub = subs.get_current()
    if sub ~= nil then
        table.insert(subs.list, sub)
    end
end

subs.set_starting_point = function()
    subs.list = {}
    mp.observe_property("sub-text", "string", subs.append)

    local current_sub = subs.get_current()

    if current_sub ~= nil then
        local starting_point = current_sub['start']
        starting_point = seconds_to_human_readable_time(starting_point)
        mp.osd_message("Starting point is set to " .. starting_point, 2)
    else
        mp.osd_message("There's no visible subtitle.", 2)
    end
end

subs.clear = function()
    mp.unobserve_property(subs.append)
    subs.list = {}
end

subs.reset_starting_point = function()
    subs.clear()
    mp.osd_message("Starting point is reset.", 2)
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
-- main

local function export_to_anki()
    local sub = subs.get()
    subs.clear()

    if sub ~= nil then
        local filename = construct_filename(sub)
        local snapshot_filename = add_extension(filename, '.webp')
        local audio_filename = add_extension(filename, '.ogg')

        ffmpeg.create_snapshot(sub, snapshot_filename)
        ffmpeg.create_audio(sub, audio_filename)

        ankiconnect.add_note(sub['text'], audio_filename, snapshot_filename)
    else
        msg.warn("Nothing to export.")
        mp.osd_message("Nothing to export.", 1)
    end
end

if config.autoclip == true then clip_autocopy.enable() end

check_config_sanity()
ankiconnect.create_deck_if_doesnt_exist(config.deck_name)
mp.add_key_binding("ctrl+e", "anki-export-note", export_to_anki)
mp.add_key_binding("ctrl+s", "set-starting-point", subs.set_starting_point)
mp.add_key_binding("ctrl+r", "reset-starting-point", subs.reset_starting_point)
mp.add_key_binding("ctrl+t", "toggle-sub-autocopy", clip_autocopy.toggle)
mp.add_key_binding("ctrl+h", "sub-rewind", sub_rewind)
