--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder creates audio clips and snapshots, both animated and static.
]]

local mp = require('mp')
local utils = require('mp.utils')
local h = require('helpers')
local filename_factory = require('utils.filename_factory')

--Contains the state of the module
local self = {
    snapshot = {},
    audio = {},
    config = nil,
    store_fn = nil,
    platform = nil,
    encoder = nil,
}

------------------------------------------------------------
-- utility functions

local function pad_timings(padding, start_time, end_time)
    local video_duration = mp.get_property_number('duration')
    start_time = start_time - padding
    end_time = end_time + padding

    if start_time < 0 then
        start_time = 0
    end

    if end_time > video_duration then
        end_time = video_duration
    end

    return start_time, end_time
end

local function alt_path_dirs()
    return {
        '/opt/homebrew/bin',
        '/usr/local/bin',
        utils.join_path(os.getenv("HOME") or "~", '.local/bin'),
    }
end

local function find_exec(name)
    local path, info
    for _, alt_dir in pairs(alt_path_dirs()) do
        path = utils.join_path(alt_dir, name)
        info = utils.file_info(path)
        if info and info.is_file then
            return path
        end
    end
    return name
end

local function toms(timestamp)
    --- Trim timestamp down to milliseconds.
    return string.format("%.3f", timestamp)
end

------------------------------------------------------------
-- ffmpeg encoder

local ffmpeg = {}

ffmpeg.prefix = { find_exec("ffmpeg"), "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet", "-sn", }

ffmpeg.prepend = function(args)
    if next(args) ~= nil then
        for i, value in ipairs(ffmpeg.prefix) do
            table.insert(args, i, value)
        end
    end
    return args
end

ffmpeg.make_static_snapshot_args = function(source_path, output_path, timestamp)
    return ffmpeg.prepend {
        '-an',
        '-ss', toms(timestamp),
        '-i', source_path,
        '-map_metadata', '-1',
        '-vcodec', self.config.snapshot_codec,
        '-lossless', '0',
        '-compression_level', '6',
        '-qscale:v', tostring(self.config.snapshot_quality),
        '-vf', string.format('scale=%d:%d', self.config.snapshot_width, self.config.snapshot_height),
        '-vframes', '1',
        output_path
    }
end

ffmpeg.animated_snapshot_filters = function()
    return string.format(
            "fps=%d,scale=%d:%d:flags=lanczos",
            self.config.animated_snapshot_fps,
            self.config.animated_snapshot_width,
            self.config.animated_snapshot_height
    )
end

ffmpeg.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
    -- Documentation: https://www.ffmpeg.org/ffmpeg-all.html#libwebp
    return ffmpeg.prepend {
        '-an',
        '-ss', toms(start_timestamp),
        '-t', toms(end_timestamp - start_timestamp),
        '-i', source_path,
        '-map_metadata', '-1',
        '-vcodec', 'libwebp',
        '-loop', '0',
        '-lossless', '0',
        '-compression_level', '6',
        '-quality', tostring(self.config.animated_snapshot_quality),
        '-vf', ffmpeg.animated_snapshot_filters(),
        output_path
    }
end

ffmpeg.append_user_audio_args = function(args)
    local args_iter = string.gmatch(self.config.ffmpeg_audio_args, "%S+")
    local filters = (
            self.config.tie_volumes
                    and string.format("volume=%.1f", mp.get_property_native('volume') / 100.0)
                    or ""
    )
    for arg in args_iter do
        if arg == '-af' or arg == '-filter:a' then
            filters = #filters > 0 and string.format("%s,%s", args_iter(), filters) or args_iter()
        else
            table.insert(args, #args, arg)
        end
    end
    if #filters > 0 then
        table.insert(args, #args, '-af')
        table.insert(args, #args, filters)
    end
    return args
end

ffmpeg.make_audio_args = function(source_path, output_path, start_timestamp, end_timestamp)
    local audio_track = h.get_active_track('audio')
    local audio_track_id = audio_track['ff-index']

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'a'
    end

    local args = ffmpeg.prepend {
        '-vn',
        '-ss', toms(start_timestamp),
        '-to', toms(end_timestamp),
        '-i', source_path,
        '-map_metadata', '-1',
        '-map', string.format("0:%d", audio_track_id),
        '-ac', '1',
        '-codec:a', self.config.audio_codec,
        '-vbr', 'on',
        '-compression_level', '10',
        '-application', 'voip',
        '-b:a', tostring(self.config.audio_bitrate),
        output_path
    }
    return ffmpeg.append_user_audio_args(args)
end

------------------------------------------------------------
-- mpv encoder

local mpv = { }

mpv.exec = find_exec("mpv")

mpv.make_static_snapshot_args = function(source_path, output_path, timestamp)
    return {
        mpv.exec,
        source_path,
        '--loop-file=no',
        '--audio=no',
        '--no-ocopy-metadata',
        '--no-sub',
        '--frames=1',
        '--ovcopts-add=lossless=0',
        '--ovcopts-add=compression_level=6',
        table.concat { '--ovc=', self.config.snapshot_codec },
        table.concat { '-start=', toms(timestamp), },
        table.concat { '--ovcopts-add=quality=', tostring(self.config.snapshot_quality) },
        table.concat { '--vf-add=scale=', self.config.snapshot_width, ':', self.config.snapshot_height },
        table.concat { '-o=', output_path }
    }
end

mpv.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
    return {
        mpv.exec,
        source_path,
        '--loop-file=no',
        '--ovc=libwebp',
        '--of=webp',
        '--ofopts-add=loop=0',
        '--audio=no',
        '--no-sub',
        '--no-ocopy-metadata',
        '--ovcopts-add=lossless=0',
        '--ovcopts-add=compression_level=6',
        table.concat { '--start=', toms(start_timestamp), },
        table.concat { '--end=', toms(end_timestamp), },
        table.concat { '--ovcopts-add=quality=', tostring(self.config.animated_snapshot_quality) },
        table.concat { '--vf-add=scale=', self.config.animated_snapshot_width, ':', self.config.animated_snapshot_height, ':flags=lanczos', },
        table.concat { '--vf-add=fps=', self.config.animated_snapshot_fps, },
        table.concat { '-o=', output_path },
    }
end

mpv.make_audio_args = function(source_path, output_path, start_timestamp, end_timestamp)
    local audio_track = h.get_active_track('audio')
    local audio_track_id = mp.get_property("aid")

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'auto'
    end

    local args = {
        mpv.exec,
        source_path,
        '--loop-file=no',
        '--video=no',
        '--no-ocopy-metadata',
        '--no-sub',
        '--audio-channels=mono',
        '--oacopts-add=vbr=on',
        '--oacopts-add=application=voip',
        '--oacopts-add=compression_level=10',
        table.concat { '--oac=', self.config.audio_codec },
        table.concat { '--start=', toms(start_timestamp), },
        table.concat { '--end=', toms(end_timestamp), },
        table.concat { '--aid=', audio_track_id },
        table.concat { '--volume=', self.config.tie_volumes and mp.get_property('volume') or '100' },
        table.concat { '--oacopts-add=b=', self.config.audio_bitrate },
        table.concat { '-o=', output_path }
    }
    for arg in string.gmatch(self.config.mpv_audio_args, "%S+") do
        -- Prepend before output path
        table.insert(args, #args, arg)
    end
    return args
end

------------------------------------------------------------
-- main interface

local create_animated_snapshot = function(start_timestamp, end_timestamp, source_path, output_path, on_finish_fn)
    -- Creates the animated snapshot and then calls on_finish_fn
    local args = self.encoder.make_animated_snapshot_args(source_path, output_path, start_timestamp, end_timestamp)
    h.subprocess(args, on_finish_fn)
end

local create_static_snapshot = function(timestamp, source_path, output_path, on_finish_fn)
    -- Creates a static snapshot, in other words an image, and then calls on_finish_fn
    if not self.config.screenshot then
        local args = self.encoder.make_static_snapshot_args(source_path, output_path, timestamp)
        h.subprocess(args, on_finish_fn)
    else
        local args = { 'screenshot-to-file', output_path, 'video', }
        mp.command_native_async(args, on_finish_fn)
    end

end

local create_snapshot = function(start_timestamp, end_timestamp, current_timestamp, filename)
    -- Calls the proper function depending on whether or not the snapshot should be animated
    if not h.is_empty(self.config.image_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.platform.tmp_dir(), filename)

        local on_finish = function()
            self.store_fn(filename, output_path)
            os.remove(output_path)
        end

        if self.config.animated_snapshot_enabled then
            create_animated_snapshot(start_timestamp, end_timestamp, source_path, output_path, on_finish)
        else
            create_static_snapshot(current_timestamp, source_path, output_path, on_finish)
        end
    else
        print("Snapshot will not be created.")
    end
end

local background_play = function(file_path, on_finish)
    return h.subprocess(
            { mpv.exec, '--audio-display=no', '--force-window=no', '--keep-open=no', '--really-quiet', file_path },
            on_finish
    )
end

local create_audio = function(start_timestamp, end_timestamp, filename, padding)
    if not h.is_empty(self.config.audio_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.platform.tmp_dir(), filename)

        if padding > 0 then
            start_timestamp, end_timestamp = pad_timings(padding, start_timestamp, end_timestamp)
        end

        local args = self.encoder.make_audio_args(source_path, output_path, start_timestamp, end_timestamp)
        local on_finish = function()
            self.store_fn(filename, output_path)
            if self.config.preview_audio then
                background_play(output_path, function() os.remove(output_path) end)
            else
                os.remove(output_path)
            end
        end
        h.subprocess(args, on_finish)
    else
        print("Audio will not be created.")
    end
end

local make_snapshot_filename = function(start_time, end_time, timestamp)
    -- Generate a filename for the snapshot, taking care of its extension and whether it's animated or static
    if self.config.animated_snapshot_enabled then
        return filename_factory.make_filename(start_time, end_time, self.config.animated_snapshot_extension)
    else
        return filename_factory.make_filename(timestamp, self.config.snapshot_extension)
    end
end

local make_audio_filename = function(start_time, end_time)
    -- Generates a filename for the audio
    return filename_factory.make_filename(start_time, end_time, self.config.audio_extension)
end

local toggle_animation = function()
    -- Toggles on and off animated snapshot generation at runtime. It is called whenever ctrl+g is pressed
    self.config.animated_snapshot_enabled = not self.config.animated_snapshot_enabled
    h.notify("Animation " .. (self.config.animated_snapshot_enabled and "enabled" or "disabled"), "info", 2)
end

local init = function(config, store_fn, platform)
    -- Sets the module to its preconfigured status
    self.config = config
    self.store_fn = store_fn
    self.platform = platform
    self.encoder = config.use_ffmpeg and ffmpeg or mpv
end

local create_job = function(type, sub, audio_padding)
    local filename, run_async, current_timestamp
    if type == 'snapshot' and h.has_video_track() then
        current_timestamp = mp.get_property_number("time-pos", 0)
        filename = make_snapshot_filename(sub['start'], sub['end'], current_timestamp)
        run_async = function() create_snapshot(sub['start'], sub['end'], current_timestamp, filename) end
    elseif type == 'audioclip' and h.has_audio_track() then
        filename = make_audio_filename(sub['start'], sub['end'])
        run_async = function() create_audio(sub['start'], sub['end'], filename, audio_padding) end
    else
        run_async = function() print(type .. " will not be created.") end
    end
    return {
        filename = filename,
        run_async = run_async,
    }
end

return {
    init = init,
    snapshot = {
        create_job = function(sub) return create_job('snapshot', sub) end,
        toggle_animation = toggle_animation,
    },
    audio = {
        create_job = function(sub, padding) return create_job('audioclip', sub, padding) end,
    },
}
