local mp = require('mp')
local utils = require('mp.utils')
local _config, _store_fn, _os_temp_dir, _subprocess

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

local create_snapshot = function(timestamp, filename)
    local source_path = mp.get_property("path")
    local output_path = utils.join_path(_os_temp_dir(), filename)

    local args = {
        'mpv',
        source_path,
        '--loop-file=no',
        '--audio=no',
        '--no-ocopy-metadata',
        '--no-sub',
        '--frames=1',
        '--ovcopts-add=lossless=0',
        '--ovcopts-add=compression_level=6',
        table.concat { '--ovc=', _config.snapshot_codec },
        table.concat { '-start=', timestamp },
        table.concat { '--ovcopts-add=quality=', tostring(_config.snapshot_quality) },
        table.concat { '--vf-add=scale=', _config.snapshot_width, ':', _config.snapshot_height },
        table.concat { '-o=', output_path }
    }
    local on_finish = function()
        _store_fn(filename, output_path)
        os.remove(output_path)
    end
    _subprocess(args, on_finish)
end

local create_audio = function(start_timestamp, end_timestamp, filename, padding)
    local source_path = mp.get_property("path")
    local audio_track = get_active_track('audio')
    local audio_track_id = mp.get_property("aid")
    local output_path = utils.join_path(_os_temp_dir(), filename)

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'auto'
    end

    if padding > 0 then
        start_timestamp, end_timestamp = pad_timings(padding, start_timestamp, end_timestamp)
    end

    local args = {
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
        table.concat { '--oac=', _config.audio_codec },
        table.concat { '--start=', start_timestamp },
        table.concat { '--end=', end_timestamp },
        table.concat { '--aid=', audio_track_id },
        table.concat { '--volume=', _config.tie_volumes and mp.get_property('volume') or '100' },
        table.concat { '--oacopts-add=b=', _config.audio_bitrate },
        table.concat { '-o=', output_path }
    }
    local on_finish = function()
        _store_fn(filename, output_path)
        os.remove(output_path)
    end
    _subprocess(args, on_finish)
end

local init = function(config, store_fn, os_temp_dir, subprocess)
    _config = config
    _store_fn = store_fn
    _os_temp_dir = os_temp_dir
    _subprocess = subprocess
end

return {
    init = init,
    create_snapshot = create_snapshot,
    create_audio = create_audio,
}
