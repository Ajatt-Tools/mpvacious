--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Config utils.
]]

local mp = require('mp')
local h = require('helpers')
local utils = require('mp.utils')
local defaults = require('config.defaults')

local function create_config_file(default_profile_filename)
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

local function validate_config(config)
    if h.is_empty(config) then
        error("config not passed")
    end

    local function set_file_extension_for_opus()
        -- Default to OGG, then change if an extension is supported.
        -- https://en.wikipedia.org/wiki/Core_Audio_Format
        config.audio_extension = '.ogg'
        for _, extension in ipairs({ 'opus', 'm4a', 'webm', 'caf' }) do
            if extension == config.opus_container then
                config.audio_extension = '.' .. config.opus_container
                break
            end
        end
    end

    local function set_audio_format()
        if config.audio_format == 'opus' then
            -- https://opus-codec.org/
            config.audio_codec = 'libopus'
            set_file_extension_for_opus()
        else
            config.audio_codec = 'libmp3lame'
            config.audio_extension = '.mp3'
        end
        return config
    end

    local function set_video_format()
        if config.snapshot_format == 'avif' then
            config.snapshot_extension = '.avif'
            config.snapshot_codec = 'libaom-av1'
        elseif config.snapshot_format == 'webp' then
            config.snapshot_extension = '.webp'
            config.snapshot_codec = 'libwebp'
        else
            config.snapshot_extension = '.jpg'
            config.snapshot_codec = 'mjpeg'
        end

        -- Animated webp images can only have .webp extension.
        -- The user has no choice on this. Same logic for avif.
        if config.animated_snapshot_format == 'avif' then
            config.animated_snapshot_extension = '.avif'
            config.animated_snapshot_codec = 'libaom-av1'
        else
            config.animated_snapshot_extension = '.webp'
            config.animated_snapshot_codec = 'libwebp'
        end
        return config
    end

    local function ensure_in_range(dimension)
        if config[dimension] < defaults.min_side_px then
            config[dimension] = defaults.preserve_aspect_ratio
        end
        if config[dimension] > defaults.max_side_px then
            config[dimension] = defaults.max_side_px
        end
        return config
    end

    local function conditionally_set_defaults(width, height, quality)
        if config[width] < 1 and config[height] < 1 then
            config[width] = defaults.preserve_aspect_ratio
            config[height] = defaults.default_height_px
        end
        if config[quality] < 0 or config[quality] > 100 then
            config[quality] = defaults.default_image_quality
        end
        return config
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

    local function main()
        set_audio_format()
        set_video_format()
        check_image_settings()
        check_animated_snapshot_settings()
    end
    return main()
end

return {
    create_config_file = create_config_file,
    validate_config = validate_config,
}
