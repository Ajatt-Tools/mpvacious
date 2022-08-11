local mp = require('mp')
local utils = require('mp.utils')
local h = require('helpers')
local self = {}

------------------------------------------------------------
-- utility functions

local pad_timings = function(padding, start_time, end_time)
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

local get_active_track = function(track_type)
    local track_list = mp.get_property_native('track-list')
    for _, track in pairs(track_list) do
        if track.type == track_type and track.selected == true then
            return track
        end
    end
    return nil
end

------------------------------------------------------------
-- ffmpeg encoder

local ffmpeg = {}

ffmpeg.prefix = { "ffmpeg", "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet", "-sn", }

ffmpeg.prepend = function(args)
    if next(args) ~= nil then
        for i, value in ipairs(ffmpeg.prefix) do
            table.insert(args, i, value)
        end
    end
    return args
end

ffmpeg.make_snapshot_args = function(source_path, output_path, timestamp)
    return ffmpeg.prepend {
        '-an',
        '-ss', tostring(timestamp),
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

ffmpeg.make_audio_args = function(source_path, output_path, start_timestamp, end_timestamp)
    local audio_track = get_active_track('audio')
    local audio_track_id = audio_track['ff-index']

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'a'
    end

    return ffmpeg.prepend {
        '-vn',
        '-ss', tostring(start_timestamp),
        '-to', tostring(end_timestamp),
        '-i', source_path,
        '-map_metadata', '-1',
        '-map', string.format("0:%d", audio_track_id),
        '-ac', '1',
        '-codec:a', self.config.audio_codec,
        '-vbr', 'on',
        '-compression_level', '10',
        '-application', 'voip',
        '-b:a', tostring(self.config.audio_bitrate),
        '-filter:a', string.format("volume=%.1f", self.config.tie_volumes and mp.get_property_native('volume') / 100 or 1),
        output_path
    }
end

------------------------------------------------------------
-- mpv encoder

local mpv = {}

mpv.make_snapshot_args = function(source_path, output_path, timestamp)
    return {
        'mpv',
        source_path,
        '--loop-file=no',
        '--audio=no',
        '--no-ocopy-metadata',
        '--no-sub',
        '--frames=1',
        '--ovcopts-add=lossless=0',
        '--ovcopts-add=compression_level=6',
        table.concat { '--ovc=', self.config.snapshot_codec },
        table.concat { '-start=', timestamp },
        table.concat { '--ovcopts-add=quality=', tostring(self.config.snapshot_quality) },
        table.concat { '--vf-add=scale=', self.config.snapshot_width, ':', self.config.snapshot_height },
        table.concat { '-o=', output_path }
    }
end

mpv.make_audio_args = function(source_path, output_path, start_timestamp, end_timestamp)
    local audio_track = get_active_track('audio')
    local audio_track_id = mp.get_property("aid")

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'auto'
    end

    return {
        'mpv',
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
        table.concat { '--start=', start_timestamp },
        table.concat { '--end=', end_timestamp },
        table.concat { '--aid=', audio_track_id },
        table.concat { '--volume=', self.config.tie_volumes and mp.get_property('volume') or '100' },
        table.concat { '--oacopts-add=b=', self.config.audio_bitrate },
        table.concat { '-o=', output_path }
    }
end

------------------------------------------------------------
-- main interface

local create_snapshot = function(timestamp, filename)
    if not h.is_empty(self.config.image_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.os_temp_dir(), filename)
        local on_finish = function()
            self.store_fn(filename, output_path)
            os.remove(output_path)
        end
        if not self.config.screenshot then
            local args = self.encoder.make_snapshot_args(source_path, output_path, timestamp)
            h.subprocess(args, on_finish)
        else
            local args = {'screenshot-to-file', output_path, 'video',}
            mp.command_native_async(args, on_finish)
        end
    else
        print("Snapshot will not be created.")
    end
end

local background_play = function(file_path, on_finish)
    return h.subprocess(
            { 'mpv', '--audio-display=no', '--force-window=no', '--keep-open=no', '--really-quiet', file_path },
            on_finish
    )
end

local create_audio = function(start_timestamp, end_timestamp, filename, padding)
    if not h.is_empty(self.config.audio_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.os_temp_dir(), filename)

        if padding > 0 then
            start_timestamp, end_timestamp = pad_timings(padding, start_timestamp, end_timestamp)
        end

        local args = self.encoder.make_audio_args(source_path, output_path, start_timestamp, end_timestamp)
        for arg in string.gmatch(self.config.use_ffmpeg and self.config.ffmpeg_audio_args or self.config.mpv_audio_args, "%S+") do
            -- Prepend before output path
            table.insert(args, #args, arg)
        end
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

local init = function(config, store_fn, os_temp_dir)
    self.config = config
    self.store_fn = store_fn
    self.os_temp_dir = os_temp_dir
    self.encoder = config.use_ffmpeg and ffmpeg or mpv
end

return {
    init = init,
    create_snapshot = create_snapshot,
    create_audio = create_audio,
}
