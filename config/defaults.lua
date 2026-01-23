--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Default config.
]]

local this = {}

-- This constant should be used in place of width and/or height in the config file.
-- It tells the encoder to preserve aspect ratio when downscaling snapshots.
-- The user almost always wants to set either width or height to this value.
-- Note: If set to -1, encoding will fail with the "height/width not divisible by 2" error.
this.preserve_aspect_ratio = -2

-- Min sides
this.min_side_px = 42
this.max_side_px = 1920

-- Default height
this.default_height_px = 350

-- Measure quality from 0 (worst/lowest) to 100 (best/highest)
this.default_image_quality = 15

this.defaults = {
    -- Default config.
    -- The user should not modify anything below.

    -- Common
    nuke_spaces = false,                       -- remove all spaces from the primary subtitles on exported anki cards and when copying text to clipboard.
    clipboard_trim_enabled = true,             -- remove unnecessary characters from strings before copying to the clipboard
    use_ffmpeg = false,                        -- if set to true, use ffmpeg to create audio clips and snapshots. by default use mpv.
    reload_config_before_card_creation = true, -- for convenience, read config file from disk before a card is made.
    card_overwrite_safeguard = 1,              -- a safeguard for accidentally overwriting more cards than intended.

    -- Clipboard and external communication
    autoclip = false,              -- enable copying subs to the clipboard when mpv starts
    autoclip_method = "clipboard", -- one of the methods
    autoclip_custom_args = "",     -- command to run when autoclip is triggered and autoclip_method and set to "custom_command".

    -- Secondary subtitle
    secondary_sub_auto_load = true,                 -- Automatically load secondary subtitle track when a video file is opened.
    secondary_sub_lang = 'eng,en,rus,ru,jp,jpn,ja', -- Language of secondary subs that should be automatically loaded.
    secondary_sub_area = 0.15,                      -- Hover area. Fraction of the window from the top.
    secondary_sub_visibility = 'auto',              -- One of: 'auto', 'never', 'always'. Controls secondary_sid visibility. Ctrl+V to cycle.

    -- Snapshots
    snapshot_format = "avif",               -- avif, webp or jpg
    snapshot_quality = 15,                  -- from 0=lowest to 100=highest
    snapshot_width = this.preserve_aspect_ratio, -- a positive integer or -2 for auto
    snapshot_height = this.default_height_px,    -- same
    screenshot = false,                     -- create a screenshot instead of a snapshot; see example config.

    -- Animations
    animated_snapshot_enabled = false,               -- if enabled captures the selected segment of the video, instead of just a frame
    animated_snapshot_format = "avif",               -- avif or webp
    animated_snapshot_fps = 10,                      -- positive integer between 0 and 30 (30 included)
    animated_snapshot_width = this.preserve_aspect_ratio, -- positive integer or -2 to scale it maintaining ratio (height must not be -2 in that case)
    animated_snapshot_height = this.default_height_px,    -- positive integer or -2 to scale it maintaining ratio (width must not be -2 in that case)
    animated_snapshot_quality = 5,                   -- positive integer between 0 and 100 (100 included)

    -- Audio clips
    audio_format = "opus",  -- opus or mp3
    opus_container = "ogg", -- ogg, opus, m4a, webm or caf
    audio_bitrate = "18k",  -- from 16k to 32k
    audio_padding = 0.12,   -- Set a pad to the dialog timings. 0.5 = audio is padded by .5 seconds. 0 = disable.
    tie_volumes = false,    -- if set to true, the volume of the outputted audio file depends on the volume of the player at the time of export
    preview_audio = false,  -- play created audio clips in background.

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
    create_deck = false,               -- automatically create a deck for new cards
    allow_duplicates = false,          -- allow making notes with the same sentence field
    deck_name = "Learning",            -- name of the deck for new cards
    model_name = "Japanese sentences", -- Tools -> Manage note types
    sentence_field = "SentKanji",
    secondary_field = "SentEng",
    audio_field = "SentAudio",
    audio_template = '[sound:%s]',
    image_field = "Image",
    image_template = '<img alt="snapshot" src="%s">',
    append_media = true,        -- True to append video media after existing data, false to insert media before
    disable_gui_browse = false, -- Lets you disable anki browser manipulation by mpvacious.
    ankiconnect_url = '127.0.0.1:8765',
    ankiconnect_api_key = '',

    -- Note tagging
    -- The tag(s) added to new notes. Spaces separate multiple tags.
    -- Change to "" to disable tagging completely.
    -- The following substitutions are supported:
    --   %n - the name of the video
    --   %t - timestamp
    --   %d - episode number (if none found, returns nothing)
    --   %e - SUBS2SRS_TAGS environment variable
    --   %f - full file path of the video
    note_tag = "subs2srs %n",
    tag_nuke_brackets = true,         -- delete all text inside brackets before substituting filename into tag
    tag_nuke_parentheses = false,     -- delete all text inside parentheses before substituting filename into tag
    tag_del_episode_num = true,       -- delete the episode number if found
    tag_del_after_episode_num = true, -- delete everything after the found episode number (does nothing if tag_del_episode_num is disabled)
    tag_filename_lowercase = false,   -- convert filename to lowercase for tagging.

    -- Misc info
    miscinfo_enable = true,
    miscinfo_field = "Notes",         -- misc notes and source information field
    miscinfo_format = "%n EP%d (%t)", -- format string to use for the miscinfo_field, accepts note_tag-style format strings

    -- Forvo support
    use_forvo = "yes",                -- 'yes', 'no', 'always'
    vocab_field = "VocabKanji",       -- target word field
    vocab_audio_field = "VocabAudio", -- target word audio

    -- Custom Sub Filter
    custom_sub_filter_enabled = false,                    -- True to enable custom sub preprocessing be default
    custom_sub_filter_notification = "Custom Sub Filter", -- Notification prefix for toggle
    use_custom_trim = false,                              -- True to use a custom trim instead of the built in one

    -- New note timer
    enable_new_note_timer = true,        -- Start the new note checker when mpv starts.
    new_note_timer_interval_seconds = 2, -- Check for new notes every N seconds.
}

-- Defines config profiles
-- Each name references a file in ~/.config/mpv/script-opts/*.conf
-- Profiles themselves are defined in ~/.config/mpv/script-opts/subs2srs_profiles.conf
this.profiles = {
    profiles = "subs2srs,subs2srs_english",
    active = "subs2srs",
}

return this
