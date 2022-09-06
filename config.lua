--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Config management, validation, loading.
]]

local mpopt = require('mp.options')
local helpers = require('helpers')
local initial_config = {}
local default_profile_filename = 'subs2srs'
local profiles_filename = 'subs2srs_profiles'

local config, profiles

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
    -- Animated webp images can only have .webp extension.
    -- The user has no choice on this.
    config.animated_snapshot_extension = '.webp'
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

local function ensure_correct_fps()
    if config.animated_snapshot_fps == nil or config.animated_snapshot_fps <= 0 or config.animated_snapshot_fps > 30 then
        config.animated_snapshot_fps = 10
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

local function load_profile(profile_name)
    if helpers.is_empty(profile_name) then
        profile_name = profiles.active
        if helpers.is_empty(profile_name) then
            profile_name = default_profile_filename
        end
    end
    mpopt.read_options(config, profile_name)
end

local function save_initial_config()
    for key, value in pairs(config) do
        initial_config[key] = value
    end
end

local function restore_initial_config()
    for key, value in pairs(initial_config) do
        config[key] = value
    end
end

local function next_profile()
    local first, next, new
    for profile in string.gmatch(profiles.profiles, '[^,]+') do
        if not first then
            first = profile
        end
        if profile == profiles.active then
            next = true
        elseif next then
            next = false
            new = profile
        end
    end
    if next == true or not new then
        new = first
    end
    profiles.active = new
    restore_initial_config()
    load_profile(profiles.active)
    validate_config()
end

local function init(config_table, profiles_table)
    config, profiles = config_table, profiles_table
    -- 'subs2srs' is the main profile, it is always loaded.
    -- 'active profile' overrides it afterwards.
    mpopt.read_options(profiles, profiles_filename)
    load_profile(default_profile_filename)
    save_initial_config()
    if profiles.active ~= default_profile_filename then
        load_profile(profiles.active)
    end
    validate_config()
end

return {
    init = init,
    next_profile = next_profile,
}
