--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Config management, validation, loading.
]]

local mp = require('mp')
local mpopt = require('mp.options')
local msg = require('mp.msg')
local h = require('helpers')
local utils = require('mp.utils')

local min_side_px = 42
local max_side_px = 1920
local default_height_px = 350

-- Measure quality from 0 (worst/lowest) to 100 (best/highest)
local default_image_quality = 15

-- This constant should be used in place of width and/or height in the config file.
-- It tells the encoder to preserve aspect ratio when downscaling snapshots.
-- The user almost always wants to set either width or height to this value.
-- Note: If set to -1, encoding will fail with the "height/width not divisible by 2" error.
local preserve_aspect_ratio = -2

local self = {
    config = nil,
    profiles = nil,
    initial_config = {}
}

local default_profile_filename = 'subs2srs'
local profiles_filename = 'subs2srs_profiles'

local function set_file_extension_for_opus()
    -- Default to OGG, then change if an extension is supported.
    -- https://en.wikipedia.org/wiki/Core_Audio_Format
    self.config.audio_extension = '.ogg'
    for _, extension in ipairs({ 'opus', 'm4a', 'webm', 'caf' }) do
        if extension == self.config.opus_container then
            self.config.audio_extension = '.' .. self.config.opus_container
            break
        end
    end
end

local function set_audio_format()
    if self.config.audio_format == 'opus' then
        -- https://opus-codec.org/
        self.config.audio_codec = 'libopus'
        set_file_extension_for_opus()
    else
        self.config.audio_codec = 'libmp3lame'
        self.config.audio_extension = '.mp3'
    end
end

local function set_video_format()
    if self.config.snapshot_format == 'avif' then
        self.config.snapshot_extension = '.avif'
        self.config.snapshot_codec = 'libaom-av1'
    elseif self.config.snapshot_format == 'webp' then
        self.config.snapshot_extension = '.webp'
        self.config.snapshot_codec = 'libwebp'
    else
        self.config.snapshot_extension = '.jpg'
        self.config.snapshot_codec = 'mjpeg'
    end

    -- Animated webp images can only have .webp extension.
    -- The user has no choice on this. Same logic for avif.
    if self.config.animated_snapshot_format == 'avif' then
        self.config.animated_snapshot_extension = '.avif'
        self.config.animated_snapshot_codec = 'libaom-av1'
    else
        self.config.animated_snapshot_extension = '.webp'
        self.config.animated_snapshot_codec = 'libwebp'
    end
end

local function ensure_in_range(dimension)
    self.config[dimension] = self.config[dimension] < min_side_px and preserve_aspect_ratio or self.config[dimension]
    self.config[dimension] = self.config[dimension] > max_side_px and max_side_px or self.config[dimension]
end

local function conditionally_set_defaults(width, height, quality)
    if self.config[width] < 1 and self.config[height] < 1 then
        self.config[width] = preserve_aspect_ratio
        self.config[height] = default_height_px
    end
    if self.config[quality] < 0 or self.config[quality] > 100 then
        self.config[quality] = default_image_quality
    end
end

local function check_image_settings()
    ensure_in_range('snapshot_width')
    ensure_in_range('snapshot_height')
    conditionally_set_defaults('snapshot_width', 'snapshot_height', 'snapshot_quality')
end

local function ensure_correct_fps()
    if self.config.animated_snapshot_fps == nil or self.config.animated_snapshot_fps <= 0 or self.config.animated_snapshot_fps > 30 then
        self.config.animated_snapshot_fps = 10
    end
end

local function check_animated_snapshot_settings()
    ensure_in_range('animated_snapshot_width')
    ensure_in_range('animated_snapshot_height')
    conditionally_set_defaults('animated_snapshot_width', 'animated_snapshot_height', 'animated_snapshot_quality')
    ensure_correct_fps()
end

local function validate_config()
    set_audio_format()
    set_video_format()
    check_image_settings()
    check_animated_snapshot_settings()
end

local function remember_initial_config()
    if h.is_empty(self.initial_config) then
        for key, value in pairs(self.config) do
            self.initial_config[key] = value
        end
    else
        msg.fatal("Ignoring. Initial config has been read already.")
    end
end

local function restore_initial_config()
    for key, value in pairs(self.initial_config) do
        self.config[key] = value
    end
end

local function read_profile_list()
    mpopt.read_options(self.profiles, profiles_filename)
    msg.info("Read profile list. Defined profiles: " .. self.profiles.profiles)
end

local function read_profile(profile_name)
    mpopt.read_options(self.config, profile_name)
    msg.info("Read config file: " .. profile_name)
end

local function read_default_config()
    read_profile(default_profile_filename)
end

local function reload_from_disk()
    --- Loads default config file (subs2srs.conf), then overwrites it with current profile.
    if not h.is_empty(self.config) and not h.is_empty(self.profiles) then
        restore_initial_config()
        read_default_config()
        if self.profiles.active ~= default_profile_filename then
            read_profile(self.profiles.active)
        end
        validate_config()
    else
        msg.fatal("Attempt to load config when init hasn't been done.")
    end
end

local function next_profile()
    local first, next, new
    for profile in string.gmatch(self.profiles.profiles, '[^,]+') do
        if not first then
            first = profile
        end
        if profile == self.profiles.active then
            next = true
        elseif next then
            next = false
            new = profile
        end
    end
    if next == true or not new then
        new = first
    end
    self.profiles.active = new
    reload_from_disk()
end

local function create_config_file()
    local name = default_profile_filename
    -- ~/.config/mpv/scripts/ and the mpvacious dir
    local parent, child = utils.split_path(mp.get_script_directory())
    -- ~/.config/mpv/ and "scripts"
    parent, child = utils.split_path(parent:gsub("/$", ""))
    -- ~/.config/mpv/script-opts/subs2srs.conf
    local config_filepath = utils.join_path(utils.join_path(parent, "script-opts"), string.format('%s.conf', name))
    local example_config_filepath = utils.join_path(mp.get_script_directory(), ".github/RELEASE/subs2srs.conf")

    local file_info = utils.file_info(config_filepath)
    if file_info and file_info.is_file then
        print("config already exists")
        return
    end

    local handle = io.open(example_config_filepath, 'r')
    if handle == nil then
        return
    end

    local content = handle:read("*a")
    handle:close()

    handle = io.open(config_filepath, 'w')
    if handle == nil then
        h.notify(string.format("Warning: failed to write '%s.'", config_filepath), "warn", 5)
        return
    end

    handle:write(string.format("# Written by %s on %s.\n", name, os.date()))
    handle:write(content)
    handle:close()
    h.notify("Settings saved.", "info", 2)
end

local function init(config_table, profiles_table)
    create_config_file()
    self.config, self.profiles = config_table, profiles_table
    -- 'subs2srs' is the main profile, it is always loaded. 'active profile' overrides it afterwards.
    -- initial state is saved to another table to maintain consistency when cycling through incomplete profiles.
    read_profile_list()
    read_default_config()
    remember_initial_config()
    if self.profiles.active ~= default_profile_filename then
        read_profile(self.profiles.active)
    end
    validate_config()
end

return {
    reload_from_disk = reload_from_disk,
    init = init,
    next_profile = next_profile,
    default_height_px = default_height_px,
    preserve_aspect_ratio = preserve_aspect_ratio,
}
