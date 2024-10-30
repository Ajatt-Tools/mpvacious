--[[
Copyright (C) 2020-2022 Ren Tatsumoto and contributors

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
* xclip (when running X11)
* wl-copy (when running Wayland)

Usage:
1. Change `config` according to your needs
* Config path: ~/.config/mpv/script-opts/subs2srs.conf
* Config file isn't created automatically.

2. Open a video

3. Use key bindings to manipulate the script
* Open mpvacious menu - `a`
* Create a note from the current subtitle line - `Ctrl + n`

For complete usage guide, see <https://github.com/Ajatt-Tools/mpvacious/blob/master/README.md>
]]

local mp = require('mp')
local OSD = require('osd_styler')
local cfg_mgr = require('cfg_mgr')
local encoder = require('encoder')
local h = require('helpers')
local Menu = require('menu')
local ankiconnect = require('ankiconnect')
local switch = require('utils.switch')
local play_control = require('utils.play_control')
local secondary_sid = require('subtitles.secondary_sid')
local platform = require('platform.init')
local forvo = require('utils.forvo')
local subs_observer = require('subtitles.observer')
local menu

------------------------------------------------------------
-- default config

local config = {
    -- The user should not modify anything below.

    -- Common
    nuke_spaces = false, -- remove all spaces from the primary subtitles on exported anki cards and when copying text to clipboard.
    clipboard_trim_enabled = true, -- remove unnecessary characters from strings before copying to the clipboard
    use_ffmpeg = false, -- if set to true, use ffmpeg to create audio clips and snapshots. by default use mpv.
    reload_config_before_card_creation = true, -- for convenience, read config file from disk before a card is made.

    -- Clipboard and external communication
    autoclip = false, -- enable copying subs to the clipboard when mpv starts
    autoclip_method = "clipboard", -- one of the methods
    autoclip_custom_args = "", -- command to run when autoclip is triggered and autoclip_method and set to "custom_command".

    -- Secondary subtitle
    secondary_sub_auto_load = true, -- Automatically load secondary subtitle track when a video file is opened.
    secondary_sub_lang = 'eng,en,rus,ru,jp,jpn,ja', -- Language of secondary subs that should be automatically loaded.
    secondary_sub_area = 0.15, -- Hover area. Fraction of the window from the top.
    secondary_sub_visibility = 'auto', -- One of: 'auto', 'never', 'always'. Controls secondary_sid visibility. Ctrl+V to cycle.

    -- Snapshots
    snapshot_format = "avif", -- avif, webp or jpg
    snapshot_quality = 15, -- from 0=lowest to 100=highest
    snapshot_width = cfg_mgr.preserve_aspect_ratio, -- a positive integer or -2 for auto
    snapshot_height = cfg_mgr.default_height_px, -- same
    screenshot = false, -- create a screenshot instead of a snapshot; see example config.

    -- Animations
    animated_snapshot_enabled = false, -- if enabled captures the selected segment of the video, instead of just a frame
    animated_snapshot_format = "avif", -- avif or webp
    animated_snapshot_fps = 10, -- positive integer between 0 and 30 (30 included)
    animated_snapshot_width = cfg_mgr.preserve_aspect_ratio, -- positive integer or -2 to scale it maintaining ratio (height must not be -2 in that case)
    animated_snapshot_height = cfg_mgr.default_height_px, -- positive integer or -2 to scale it maintaining ratio (width must not be -2 in that case)
    animated_snapshot_quality = 5, -- positive integer between 0 and 100 (100 included)

    -- Audio clips
    audio_format = "opus", -- opus or mp3
    opus_container = "ogg", -- ogg, opus, m4a, webm or caf
    audio_bitrate = "18k", -- from 16k to 32k
    audio_padding = 0.12, -- Set a pad to the dialog timings. 0.5 = audio is padded by .5 seconds. 0 = disable.
    tie_volumes = false, -- if set to true, the volume of the outputted audio file depends on the volume of the player at the time of export
    preview_audio = false, -- play created audio clips in background.

    -- Menu
    menu_font_name = "Noto Sans CJK JP",
    menu_font_size = 25,
    show_selected_text = true,

    -- Make sure to remove loudnorm from ffmpeg_audio_args and mpv_audio_args before enabling.
    loudnorm = false,
    loudnorm_target = -16,
    loudnorm_range = 11,
    loudnorm_peak = -1.5,

    -- Custom encoding args
    -- Defaults are for backward compatibility, in case someone
    -- updates mpvacious without updating their config.
    -- Better to remove loudnorm from custom args and enable two-pass loudnorm.
    -- Enabling loudnorm both through the separate switch and through custom args
    -- can lead to unpredictable results.
    ffmpeg_audio_args = '-af loudnorm=I=-16:TP=-1.5:LRA=11:dual_mono=true',
    mpv_audio_args = '--af-append=loudnorm=I=-16:TP=-1.5:LRA=11:dual_mono=true',

    -- Anki
    create_deck = false, -- automatically create a deck for new cards
    allow_duplicates = false, -- allow making notes with the same sentence field
    deck_name = "Learning", -- name of the deck for new cards
    model_name = "Japanese sentences", -- Tools -> Manage note types
    sentence_field = "SentKanji",
    secondary_field = "SentEng",
    audio_field = "SentAudio",
    audio_template = '[sound:%s]',
    image_field = "Image",
    image_template = '<img alt="snapshot" src="%s">',
    append_media = true, -- True to append video media after existing data, false to insert media before
    disable_gui_browse = false, -- Lets you disable anki browser manipulation by mpvacious.
    ankiconnect_url = '127.0.0.1:8765',

    -- Note tagging
    -- The tag(s) added to new notes. Spaces separate multiple tags.
    -- Change to "" to disable tagging completely.
    -- The following substitutions are supported:
    --   %n - the name of the video
    --   %t - timestamp
    --   %d - episode number (if none found, returns nothing)
    --   %e - SUBS2SRS_TAGS environment variable
    note_tag = "subs2srs %n",
    tag_nuke_brackets = true, -- delete all text inside brackets before substituting filename into tag
    tag_nuke_parentheses = false, -- delete all text inside parentheses before substituting filename into tag
    tag_del_episode_num = true, -- delete the episode number if found
    tag_del_after_episode_num = true, -- delete everything after the found episode number (does nothing if tag_del_episode_num is disabled)
    tag_filename_lowercase = false, -- convert filename to lowercase for tagging.

    -- Misc info
    miscinfo_enable = true,
    miscinfo_field = "Notes", -- misc notes and source information field
    miscinfo_format = "%n EP%d (%t)", -- format string to use for the miscinfo_field, accepts note_tag-style format strings

    -- Forvo support
    use_forvo = "yes", -- 'yes', 'no', 'always'
    vocab_field = "VocabKanji", -- target word field
    vocab_audio_field = "VocabAudio", -- target word audio
}

-- Defines config profiles
-- Each name references a file in ~/.config/mpv/script-opts/*.conf
-- Profiles themselves are defined in ~/.config/mpv/script-opts/subs2srs_profiles.conf
local profiles = {
    profiles = "subs2srs,subs2srs_english",
    active = "subs2srs",
}


------------------------------------------------------------
-- utility functions

local function _(params)
    return function()
        return pcall(h.unpack(params))
    end
end

local function escape_for_osd(str)
    str = h.trim(str)
    str = str:gsub('[%[%]{}]', '')
    return str
end

local codec_support = (function()
    local ovc_help = h.subprocess { 'mpv', '--ovc=help' }
    local oac_help = h.subprocess { 'mpv', '--oac=help' }

    local function is_audio_supported(codec)
        return oac_help.status == 0 and oac_help.stdout:match('--oac=' .. codec) ~= nil
    end

    local function is_image_supported(codec)
        return ovc_help.status == 0 and ovc_help.stdout:match('--ovc=' .. codec) ~= nil
    end

    return {
        snapshot = {
            ['libaom-av1'] = is_image_supported('libaom-av1'),
            libwebp = is_image_supported('libwebp'),
            mjpeg = is_image_supported('mjpeg'),
        },
        audio = {
            libmp3lame = is_audio_supported('libmp3lame'),
            libopus = is_audio_supported('libopus'),
        },
    }
end)()

local function ensure_deck()
    if config.create_deck == true then
        ankiconnect.create_deck(config.deck_name)
    end
end

local function load_next_profile()
    cfg_mgr.next_profile()
    ensure_deck()
    h.notify("Loaded profile " .. profiles.active)
end

local function tag_format(filename)
    filename = h.remove_extension(filename)
    filename = h.remove_common_resolutions(filename)

    local s, e, episode_num = h.get_episode_number(filename)

    if config.tag_del_episode_num == true and not h.is_empty(s) then
        if config.tag_del_after_episode_num == true then
            -- Removing everything (e.g. episode name) after the episode number including itself.
            filename = filename:sub(1, s)
        else
            -- Removing the first found instance of the episode number.
            filename = filename:sub(1, s) .. filename:sub(e + 1, -1)
        end
    end

    if config.tag_nuke_brackets == true then
        filename = h.remove_text_in_brackets(filename)
    end
    if config.tag_nuke_parentheses == true then
        filename = h.remove_filename_text_in_parentheses(filename)
    end

    if config.tag_filename_lowercase == true then
        filename = filename:lower()
    end

    filename = h.remove_leading_trailing_spaces(filename)
    filename = filename:gsub(" ", "_")
    filename = filename:gsub("_%-_", "_") -- Replaces garbage _-_ substrings with a underscore
    filename = h.remove_leading_trailing_dashes(filename)
    return filename, episode_num or ''
end

local substitute_fmt = (function()
    local function substitute_filename(tag, filename)
        return tag:gsub("%%n", filename)
    end

    local function substitute_episode_number(tag, episode)
        return tag:gsub("%%d", episode)
    end

    local function substitute_time_pos(tag)
        local time_pos = h.human_readable_time(mp.get_property_number('time-pos'))
        return tag:gsub("%%t", time_pos)
    end

    local function substitute_envvar(tag)
        local env_tags = os.getenv('SUBS2SRS_TAGS') or ''
        return tag:gsub("%%e", env_tags)
    end

    return function(tag)
        if not h.is_empty(tag) then
            local filename, episode = tag_format(mp.get_property("filename"))
            tag = substitute_filename(tag, filename)
            tag = substitute_episode_number(tag, episode)
            tag = substitute_time_pos(tag)
            tag = substitute_envvar(tag)
            tag = h.remove_leading_trailing_spaces(tag)
        end
        return tag
    end
end)()

local function prepare_for_exporting(sub_text)
    if not h.is_empty(sub_text) then
        sub_text = h.trim(sub_text)
        sub_text = h.escape_special_characters(sub_text)
    end
    return sub_text
end

local function construct_note_fields(sub_text, secondary_text, snapshot_filename, audio_filename)
    local ret = {
        [config.sentence_field] = subs_observer.maybe_remove_all_spaces(prepare_for_exporting(sub_text)),
    }
    if not h.is_empty(config.secondary_field) then
        ret[config.secondary_field] = prepare_for_exporting(secondary_text)
    end
    if not h.is_empty(config.image_field) and not h.is_empty(snapshot_filename) then
        ret[config.image_field] = string.format(config.image_template, snapshot_filename)
    end
    if not h.is_empty(config.audio_field) and not h.is_empty(audio_filename) then
        ret[config.audio_field] = string.format(config.audio_template, audio_filename)
    end
    if config.miscinfo_enable == true then
        ret[config.miscinfo_field] = substitute_fmt(config.miscinfo_format)
    end
    return ret
end

local function join_media_fields(new_data, stored_data)
    for _, field in pairs { config.audio_field, config.image_field, config.miscinfo_field } do
        if not h.is_empty(field) then
            new_data[field] = h.table_get(stored_data, field, "") .. h.table_get(new_data, field, "")
        end
    end
    return new_data
end

local function update_sentence(new_data, stored_data)
    -- adds support for TSCs
    -- https://tatsumoto-ren.github.io/blog/discussing-various-card-templates.html#targeted-sentence-cards-or-mpvacious-cards
    -- if the target word was marked by yomichan, this function makes sure that the highlighting doesn't get erased.

    if h.is_empty(stored_data[config.sentence_field]) then
        -- sentence field is empty. can't continue.
        return new_data
    elseif h.is_empty(new_data[config.sentence_field]) then
        -- *new* sentence field is empty, but old one contains data. don't delete the existing sentence.
        new_data[config.sentence_field] = stored_data[config.sentence_field]
        return new_data
    end

    local _, opentag, target, closetag, _ = stored_data[config.sentence_field]:match('^(.-)(<[^>]+>)(.-)(</[^>]+>)(.-)$')
    if target then
        local prefix, _, suffix = new_data[config.sentence_field]:match(table.concat { '^(.-)(', target, ')(.-)$' })
        if prefix and suffix then
            new_data[config.sentence_field] = table.concat { prefix, opentag, target, closetag, suffix }
        end
    end
    return new_data
end

local function audio_padding()
    local video_duration = mp.get_property_number('duration')
    if config.audio_padding == 0.0 or not video_duration then
        return 0.0
    end
    if subs_observer.user_altered() then
        return 0.0
    end
    return config.audio_padding
end

------------------------------------------------------------
-- front for adding and updating notes

local function maybe_reload_config()
    if config.reload_config_before_card_creation then
        cfg_mgr.reload_from_disk()
    end
end

local function get_anki_media_dir_path()
    return ankiconnect.get_media_dir_path()
end

local function export_to_anki(gui)
    maybe_reload_config()
    local sub = subs_observer.collect()

    if not sub:is_valid() then
        return h.notify("Nothing to export.", "warn", 1)
    end

    if not gui and h.is_empty(sub['text']) then
        sub['text'] = string.format("mpvacious wasn't able to grab subtitles (%s)", os.time())
    end

    encoder.set_output_dir(get_anki_media_dir_path())
    local snapshot = encoder.snapshot.create_job(sub)
    local audio = encoder.audio.create_job(sub, audio_padding())

    snapshot.run_async()
    audio.run_async()

    local note_fields = construct_note_fields(sub['text'], sub['secondary'], snapshot.filename, audio.filename)

    ankiconnect.add_note(note_fields, substitute_fmt(config.note_tag), gui)
    subs_observer.clear()
end

local function update_last_note(overwrite)
    maybe_reload_config()
    local sub = subs_observer.collect()
    local last_note_id = ankiconnect.get_last_note_id()

    if not sub:is_valid() then
        return h.notify("Nothing to export. Have you set the timings?", "warn", 2)
    end

    if h.is_empty(sub['text']) then
        -- In this case, don't modify whatever existing text there is and just
        -- modify the other fields we can. The user might be trying to add
        -- audio to a card which they've manually transcribed (either the video
        -- has no subtitles or it has image subtitles).
        sub['text'] = nil
    end

    if last_note_id < h.minutes_ago(10) then
        return h.notify("Couldn't find the target note.", "warn", 2)
    end

    local anki_media_dir = get_anki_media_dir_path()
    encoder.set_output_dir(anki_media_dir)
    local snapshot = encoder.snapshot.create_job(sub)
    local audio = encoder.audio.create_job(sub, audio_padding())

    local create_media = function()
        snapshot.run_async()
        audio.run_async()
    end

    local new_data = construct_note_fields(sub['text'], sub['secondary'], snapshot.filename, audio.filename)
    local stored_data = ankiconnect.get_note_fields(last_note_id)
    if stored_data then
        forvo.set_output_dir(anki_media_dir)
        new_data = forvo.append(new_data, stored_data)
        new_data = update_sentence(new_data, stored_data)
        if not overwrite then
            if config.append_media then
                new_data = join_media_fields(new_data, stored_data)
            else
                new_data = join_media_fields(stored_data, new_data)
            end
        end
    end

    -- If the text is still empty, put some dummy text to let the user know why
    -- there's no text in the sentence field.
    if h.is_empty(new_data[config.sentence_field]) then
        new_data[config.sentence_field] = string.format("mpvacious wasn't able to grab subtitles (%s)", os.time())
    end

    ankiconnect.append_media(last_note_id, new_data, create_media, substitute_fmt(config.note_tag))
    subs_observer.clear()
end

------------------------------------------------------------
-- main menu

menu = Menu:new {
    hints_state = switch.new { 'basic', 'menu', 'global', 'hidden', },
}

menu.keybindings = {
    { key = 'S', fn = menu:with_update { subs_observer.set_manual_timing_to_sub, 'start' } },
    { key = 'E', fn = menu:with_update { subs_observer.set_manual_timing_to_sub, 'end' } },
    { key = 's', fn = menu:with_update { subs_observer.set_manual_timing, 'start' } },
    { key = 'e', fn = menu:with_update { subs_observer.set_manual_timing, 'end' } },
    { key = 'c', fn = menu:with_update { subs_observer.set_to_current_sub } },
    { key = 'r', fn = menu:with_update { subs_observer.clear_and_notify } },
    { key = 'g', fn = menu:with_update { export_to_anki, true } },
    { key = 'n', fn = menu:with_update { export_to_anki, false } },
    { key = 'm', fn = menu:with_update { update_last_note, false } },
    { key = 'M', fn = menu:with_update { update_last_note, true } },
    { key = 't', fn = menu:with_update { subs_observer.toggle_autocopy } },
    { key = 'T', fn = menu:with_update { subs_observer.next_autoclip_method } },
    { key = 'i', fn = menu:with_update { menu.hints_state.bump } },
    { key = 'p', fn = menu:with_update { load_next_profile } },
    { key = 'ESC', fn = function() menu:close() end },
    { key = 'q', fn = function() menu:close() end },
}

function menu:print_header(osd)
    if self.hints_state.get() == 'hidden' then
        return
    end
    osd:submenu('mpvacious options'):newline()
    osd:item('Timings: '):text(h.human_readable_time(subs_observer.get_timing('start')))
    osd:item(' to '):text(h.human_readable_time(subs_observer.get_timing('end'))):newline()
    osd:item('Clipboard autocopy: '):text(subs_observer.autocopy_status_str()):newline()
    osd:item('Active profile: '):text(profiles.active):newline()
    osd:item('Deck: '):text(config.deck_name):newline()
end

function menu:print_bindings(osd)
    if self.hints_state.get() == 'global' then
        osd:submenu('Global bindings'):newline()
        osd:tab():item('ctrl+c: '):text('Copy current subtitle to clipboard'):newline()
        osd:tab():item('ctrl+h: '):text('Seek to the start of the line'):newline()
        osd:tab():item('ctrl+g: '):text('Toggle animated snapshots'):newline()
        osd:tab():item('ctrl+shift+h: '):text('Replay current subtitle'):newline()
        osd:tab():item('shift+h/l: '):text('Seek to the previous/next subtitle'):newline()
        osd:tab():item('alt+h/l: '):text('Seek to the previous/next subtitle and pause'):newline()
        osd:italics("Press "):item('i'):italics(" to hide mpvacious options."):newline()
    elseif self.hints_state.get() == 'menu' then
        osd:submenu('Menu bindings'):newline()
        osd:tab():item('c: '):text('Set timings to the current sub'):newline()
        osd:tab():item('s: '):text('Set start time to current position'):newline()
        osd:tab():item('e: '):text('Set end time to current position'):newline()
        osd:tab():item('shift+s: '):text('Set start time to current subtitle'):newline()
        osd:tab():item('shift+e: '):text('Set end time to current subtitle'):newline()
        osd:tab():item('r: '):text('Reset timings'):newline()
        osd:tab():item('n: '):text('Export note'):newline()
        osd:tab():item('g: '):text('GUI export'):newline()
        osd:tab():item('m: '):text('Update the last added note '):italics('(+shift to overwrite)'):newline()
        osd:tab():item('t: '):text('Toggle clipboard autocopy'):newline()
        osd:tab():item('T: '):text('Switch to the next clipboard method'):newline()
        osd:tab():item('p: '):text('Switch to next profile'):newline()
        osd:tab():item('ESC: '):text('Close'):newline()
        osd:italics("Press "):item('i'):italics(" to show global bindings."):newline()
    elseif self.hints_state.get() == 'hidden' then
        -- Menu bindings are active but hidden
    else
        osd:italics("Press "):item('i'):italics(" to show menu bindings."):newline()
    end
end

function menu:warn_formats(osd)
    if config.use_ffmpeg then
        return
    end
    for type, codecs in pairs(codec_support) do
        for codec, supported in pairs(codecs) do
            if not supported and config[type .. '_codec'] == codec then
                osd:red('warning: '):newline()
                osd:tab():text(string.format("your version of mpv does not support %s.", codec)):newline()
                osd:tab():text(string.format("mpvacious won't be able to create %s files.", type)):newline()
            end
        end
    end
end

function menu:warn_clipboard(osd)
    if subs_observer.autocopy_current_method() == "clipboard" and platform.healthy == false then
        osd:red('warning: '):text(string.format("%s is not installed.", platform.clip_util)):newline()
    end
end

function menu:print_legend(osd)
    osd:new_layer():size(config.menu_font_size):font(config.menu_font_name):align(4)
    self:print_header(osd)
    self:print_bindings(osd)
    self:warn_formats(osd)
    self:warn_clipboard(osd)
end

function menu:print_selection(osd)
    if subs_observer.is_appending() and config.show_selected_text then
        osd:new_layer():size(config.menu_font_size):font(config.menu_font_name):align(6)
        osd:submenu("Primary text"):newline()
        for _, s in ipairs(subs_observer.recorded_subs()) do
            osd:text(escape_for_osd(s['text'])):newline()
        end
        if not h.is_empty(config.secondary_field) then
            -- If the user wants to add secondary subs to Anki,
            -- it's okay to print them on the screen.
            osd:submenu("Secondary text"):newline()
            for _, s in ipairs(subs_observer.recorded_secondary_subs()) do
                osd:text(escape_for_osd(s['text'])):newline()
            end
        end
    end
end

function menu:make_osd()
    local osd = OSD:new()
    self:print_legend(osd)
    self:print_selection(osd)
    return osd
end

------------------------------------------------------------
-- main

local main = (function()
    local main_executed = false
    return function()
        if main_executed then
            return
        else
            main_executed = true
        end

        cfg_mgr.init(config, profiles)
        ankiconnect.init(config, platform)
        forvo.init(config, platform)
        encoder.init(config)
        secondary_sid.init(config)
        ensure_deck()
        subs_observer.init(menu, config)

        -- Key bindings
        mp.add_forced_key_binding("Ctrl+c", "mpvacious-copy-sub-to-clipboard", subs_observer.copy_current_primary_to_clipboard)
        mp.add_key_binding("Ctrl+C", "mpvacious-copy-secondary-sub-to-clipboard", subs_observer.copy_current_secondary_to_clipboard)
        mp.add_key_binding("Ctrl+t", "mpvacious-autocopy-toggle", subs_observer.toggle_autocopy)
        mp.add_key_binding("Ctrl+g", "mpvacious-animated-snapshot-toggle", encoder.snapshot.toggle_animation)

        -- Secondary subtitles
        mp.add_key_binding("Ctrl+v", "mpvacious-secondary-sid-toggle", secondary_sid.change_visibility)
        mp.add_key_binding("Ctrl+k", "mpvacious-secondary-sid-prev", secondary_sid.select_previous)
        mp.add_key_binding("Ctrl+j", "mpvacious-secondary-sid-next", secondary_sid.select_next)

        -- Open advanced menu
        mp.add_key_binding("a", "mpvacious-menu-open", function() menu:open() end)

        -- Add note
        mp.add_forced_key_binding("Ctrl+n", "mpvacious-export-note", menu:with_update { export_to_anki, false })

        -- Note updating
        mp.add_key_binding("Ctrl+m", "mpvacious-update-last-note", menu:with_update { update_last_note, false })
        mp.add_key_binding("Ctrl+M", "mpvacious-overwrite-last-note", menu:with_update { update_last_note, true })

        -- Vim-like seeking between subtitle lines
        mp.add_key_binding("H", "mpvacious-sub-seek-back", _ { play_control.sub_seek, 'backward' })
        mp.add_key_binding("L", "mpvacious-sub-seek-forward", _ { play_control.sub_seek, 'forward' })

        mp.add_key_binding("Alt+h", "mpvacious-sub-seek-back-pause", _ { play_control.sub_seek, 'backward', true })
        mp.add_key_binding("Alt+l", "mpvacious-sub-seek-forward-pause", _ { play_control.sub_seek, 'forward', true })

        mp.add_key_binding("Ctrl+h", "mpvacious-sub-rewind", _ { play_control.sub_rewind })
        mp.add_key_binding("Ctrl+H", "mpvacious-sub-replay", _ { play_control.play_till_sub_end })
        mp.add_key_binding("Ctrl+L", "mpvacious-sub-play-up-to-next", _ { play_control.play_till_next_sub_end })

        mp.msg.warn("Press 'a' to open the mpvacious menu.")
    end
end)()

mp.register_event("file-loaded", main)
