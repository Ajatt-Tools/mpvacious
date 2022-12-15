--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Config management, validation, loading.
]]

local mpopt = require('mp.options')
local msg = require('mp.msg')
local h = require('helpers')

local self = {
    config = nil,
    profiles = nil,
    initial_config = {}
}

local default_profile_filename = 'subs2srs'
local profiles_filename = 'subs2srs_profiles'

local function set_audio_format()
    if self.config.audio_format == 'opus' then
        self.config.audio_codec = 'libopus'
        self.config.audio_extension = '.ogg'
    else
        self.config.audio_codec = 'libmp3lame'
        self.config.audio_extension = '.mp3'
    end
end

local function set_video_format()
    if self.config.snapshot_format == 'webp' then
        self.config.snapshot_extension = '.webp'
        self.config.snapshot_codec = 'libwebp'
    else
        self.config.snapshot_extension = '.jpg'
        self.config.snapshot_codec = 'mjpeg'
    end
    -- Animated webp images can only have .webp extension.
    -- The user has no choice on this.
    self.config.animated_snapshot_extension = '.webp'
end

local function ensure_in_range(dimension)
    self.config[dimension] = self.config[dimension] < 42 and -2 or self.config[dimension]
    self.config[dimension] = self.config[dimension] > 640 and 640 or self.config[dimension]
end

local function conditionally_set_defaults(width, height, quality)
    if self.config[width] < 1 and self.config[height] < 1 then
        self.config[width] = -2
        self.config[height] = 200
    end
    if self.config[quality] < 0 or self.config[quality] > 100 then
        self.config[quality] = 15
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

local function init(config_table, profiles_table)
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
}
