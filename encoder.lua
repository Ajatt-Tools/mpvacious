--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder creates audio clips and snapshots, both animated and static.
]]

local mp = require('mp')
local utils = require('mp.utils')
local h = require('helpers')
local filename_factory = require('utils.filename_factory')
local msg = require('mp.msg')

--Contains the state of the module
local self = {
    snapshot = {},
    audio = {},
    config = nil,
    store_fn = nil,
    platform = nil,
    encoder = nil,
    output_dir_path = nil,
    max_avif_crf = 63,
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

local function rescale_quality(quality, min_q, max_q)
    local scaled = min_q + (max_q - min_q) * quality / 100
    -- Round to the nearest integer that's better in quality.
    if min_q > max_q then
        return math.floor(scaled)
    end
    return math.ceil(scaled)
end

------------------------------------------------------------
-- ffmpeg encoder

local ffmpeg = {}

ffmpeg.exec = find_exec("ffmpeg")

ffmpeg.prepend = function(...)
    return {
        ffmpeg.exec, "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet", "-sn",
        ...,
    }
end

ffmpeg.make_static_snapshot_args = function(source_path, output_path, timestamp)
    local encoder_args
    if self.config.snapshot_format == 'avif' then
        encoder_args = {
            '-c:v', 'libaom-av1',
            '-cpu-used', '6', -- cpu-used < 6 can take a lot of time to encode.
            '-crf', tostring(rescale_quality(self.config.snapshot_quality, self.max_avif_crf, 0)),
            '-still-picture', '1',
        }
    elseif self.config.snapshot_format == 'webp' then
        encoder_args = {
            '-c:v', 'libwebp',
            '-compression_level', '6',
            '-quality', tostring(self.config.snapshot_quality),
        }
    else
        encoder_args = {
            '-c:v', 'mjpeg',
            '-q:v', tostring(rescale_quality(self.config.snapshot_quality, 31, 2)),
        }
    end

    local args = ffmpeg.prepend(
            '-an',
            '-ss', toms(timestamp),
            '-i', source_path,
            '-map_metadata', '-1',
            '-vf', string.format("scale='min(%d,iw)':'min(%d,ih)':flags=sinc+accurate_rnd",
                    self.config.snapshot_width, self.config.snapshot_height),
            '-frames:v', '1',
            h.unpack(encoder_args)
    )
    table.insert(args, output_path)
    return args
end

ffmpeg.animated_snapshot_filters = function()
    return string.format(
            "fps=%d,scale='min(%d,iw)':'min(%d,ih)':flags=lanczos+accurate_rnd",
            self.config.animated_snapshot_fps,
            self.config.animated_snapshot_width,
            self.config.animated_snapshot_height
    )
end

ffmpeg.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
    local encoder_args
    if self.config.animated_snapshot_format == 'avif' then
        encoder_args = {
            '-c:v', 'libaom-av1',
            '-cpu-used', '6', -- cpu-used < 6 can take a lot of time to encode.
            '-crf', tostring(rescale_quality(self.config.animated_snapshot_quality,
                    self.max_avif_crf, 0)),
        }
    else
        -- Documentation: https://www.ffmpeg.org/ffmpeg-all.html#libwebp
        encoder_args = {
            '-c:v', 'libwebp',
            '-compression_level', '6',
            '-quality', tostring(self.config.animated_snapshot_quality),
        }
    end

    local args = ffmpeg.prepend(
            '-an',
            '-ss', toms(start_timestamp),
            '-to', toms(end_timestamp),
            '-i', source_path,
            '-map_metadata', '-1',
            '-loop', '0',
            '-vf', ffmpeg.animated_snapshot_filters(),
            h.unpack(encoder_args)
    )
    table.insert(args, output_path)
    return args
end

local function make_loudnorm_targets()
    return string.format(
            'loudnorm=I=%s:LRA=%s:TP=%s:dual_mono=true',
            self.config.loudnorm_target,
            self.config.loudnorm_range,
            self.config.loudnorm_peak
    )
end

local function parse_loudnorm(loudnorm_targets, json_extractor, loudnorm_consumer)
    local function warn()
        msg.warn('Failed to measure loudnorm stats, falling back on dynamic loudnorm.')
    end

    return function(success, result)
        local json
        if success and result.status == 0 then
            json = json_extractor(result.stdout, result.stderr)
        end

        if json == nil then
            warn()
            loudnorm_consumer(loudnorm_targets)
            return
        end

        local loudnorm_args = { loudnorm_targets }
        local function add_arg(name, val)
            -- loudnorm sometimes fails to gather stats for extremely short inputs.
            -- Simply omit the stat to fall back on dynamic loudnorm.
            if val ~= '-inf' and val ~= 'inf' then
                table.insert(loudnorm_args, string.format('%s=%s', name, val))
            else
                warn()
            end
        end

        local stats = utils.parse_json(json)
        add_arg('measured_I', stats.input_i)
        add_arg('measured_LRA', stats.input_lra)
        add_arg('measured_TP', stats.input_tp)
        add_arg('measured_thresh', stats.input_thresh)
        add_arg('offset', stats.target_offset)

        loudnorm_consumer(table.concat(loudnorm_args, ':'))
    end
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
            table.insert(args, arg)
        end
    end
    if #filters > 0 then
        table.insert(args, '-af')
        table.insert(args, filters)
    end
    return args
end

ffmpeg.make_audio_args = function(source_path, output_path,
                                  start_timestamp, end_timestamp, args_consumer)
    local audio_track = h.get_active_track('audio')
    local audio_track_id = audio_track['ff-index']

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'a'
    end

    local function make_ffargs(...)
        return ffmpeg.append_user_audio_args(
                ffmpeg.prepend(
                        '-vn',
                        '-ss', toms(start_timestamp),
                        '-to', toms(end_timestamp),
                        '-i', source_path,
                        '-map_metadata', '-1',
                        '-map_chapters', '-1',
                        '-map', string.format("0:%s", tostring(audio_track_id)),
                        '-ac', '1',
                        ...
                )
        )
    end

    local function make_encoding_args(loudnorm_args)
        local encoder_args
        if self.config.audio_format == 'opus' then
            encoder_args = {
                '-c:a', 'libopus',
                '-application', 'voip',
                '-apply_phase_inv', '0', -- Improves mono audio.
            }
            if self.config.opus_container == 'm4a' then
                table.insert(encoder_args, '-f')
                table.insert(encoder_args, 'mp4')
            end
        else
            -- https://wiki.hydrogenaud.io/index.php?title=LAME#Recommended_encoder_settings:
            -- "For very low bitrates, up to 100kbps, ABR is most often the best solution."
            encoder_args = {
                '-c:a', 'libmp3lame',
                '-compression_level', '0',
                '-abr', '1',
            }
        end

        local args = make_ffargs('-b:a', tostring(self.config.audio_bitrate), h.unpack(encoder_args))
        if loudnorm_args then
            table.insert(args, '-af')
            table.insert(args, loudnorm_args)
        end
        table.insert(args, output_path)
        args_consumer(args)
    end

    if not self.config.loudnorm then
        make_encoding_args(nil)
        return
    end

    local loudnorm_targets = make_loudnorm_targets()
    h.subprocess(
            make_ffargs(
                    '-loglevel', 'info',
                    '-af', loudnorm_targets .. ':print_format=json',
                    '-f', 'null',
                    '-'
            ),
            parse_loudnorm(
                    loudnorm_targets,
                    function(stdout, stderr)
                        local start, stop, json = string.find(stderr, '%[Parsed_loudnorm_0.-({.-})')
                        return json
                    end,
                    make_encoding_args
            )
    )
end

------------------------------------------------------------
-- mpv encoder

local mpv = { }

mpv.exec = find_exec("mpv")

mpv.prepend_common_args = function(source_path, ...)
    return {
        mpv.exec,
        source_path,
        '--no-config',
        '--loop-file=no',
        '--keep-open=no',
        '--no-sub',
        '--no-ocopy-metadata',
        ...,
    }
end

mpv.make_static_snapshot_args = function(source_path, output_path, timestamp)
    local encoder_args
    if self.config.snapshot_format == 'avif' then
        encoder_args = {
            '--ovc=libaom-av1',
            '--ovcopts-add=cpu-used=6', -- cpu-used < 6 can take a lot of time to encode.
            string.format(
                    '--ovcopts-add=crf=%d',
                    rescale_quality(self.config.snapshot_quality, self.max_avif_crf, 0)
            ),
            '--ovcopts-add=still-picture=1',
        }
    elseif self.config.snapshot_format == 'webp' then
        encoder_args = {
            '--ovc=libwebp',
            '--ovcopts-add=compression_level=6',
            string.format('--ovcopts-add=quality=%d', self.config.snapshot_quality),
        }
    else
        encoder_args = {
            '--ovc=mjpeg',
            '--vf-add=scale=out_range=jpeg',
            string.format(
                    '--ovcopts=global_quality=%d*QP2LAMBDA,flags=+qscale',
                    rescale_quality(self.config.snapshot_quality, 31, 2)
            ),
        }
    end

    return mpv.prepend_common_args(
            source_path,
            '--audio=no',
            '--frames=1',
            '--start=' .. toms(timestamp),
            string.format(
                    "--vf-add=lavfi=[scale='min(%d,iw)':'min(%d,ih)':flags=sinc+accurate_rnd]",
                    self.config.snapshot_width, self.config.snapshot_height
            ),
            '-o=' .. output_path,
            h.unpack(encoder_args)
    )
end

mpv.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
    local encoder_args
    if self.config.animated_snapshot_format == 'avif' then
        encoder_args = {
            '--ovc=libaom-av1',
            '--ovcopts-add=cpu-used=6', -- cpu-used < 6 can take a lot of time to encode.
            string.format(
                    '--ovcopts-add=crf=%d',
                    rescale_quality(self.config.snapshot_quality, self.max_avif_crf, 0)
            ),
        }
    else
        encoder_args = {
            '--ovc=libwebp',
            '--ovcopts-add=compression_level=6',
            string.format('--ovcopts-add=quality=%d', self.config.snapshot_quality),
        }
    end

    return mpv.prepend_common_args(
            source_path,
            '--audio=no',
            '--start=' .. toms(start_timestamp),
            '--end=' .. toms(end_timestamp),
            '--ofopts-add=loop=0',
            string.format('--vf-add=fps=%d', self.config.animated_snapshot_fps),
            string.format(
                    "--vf-add=lavfi=[scale='min(%d,iw)':'min(%d,ih)':flags=lanczos+accurate_rnd]",
                    self.config.animated_snapshot_width, self.config.animated_snapshot_height
            ),
            '-o=' .. output_path,
            h.unpack(encoder_args)
    )
end

mpv.make_audio_args = function(source_path, output_path,
                               start_timestamp, end_timestamp, args_consumer)
    local audio_track = h.get_active_track('audio')
    local audio_track_id = mp.get_property("aid")

    if audio_track and audio_track.external == true then
        source_path = audio_track['external-filename']
        audio_track_id = 'auto'
    end

    local function make_mpvargs(...)
        local args = mpv.prepend_common_args(
                source_path,
                '--video=no',
                '--aid=' .. audio_track_id,
                '--audio-channels=mono',
                '--start=' .. toms(start_timestamp),
                '--end=' .. toms(end_timestamp),
                string.format(
                        '--volume=%d',
                        self.config.tie_volumes and mp.get_property('volume') or 100
                ),
                ...
        )
        for arg in string.gmatch(self.config.mpv_audio_args, "%S+") do
            table.insert(args, arg)
        end
        return args
    end

    local function make_encoding_args(loudnorm_args)
        local encoder_args
        if self.config.audio_format == 'opus' then
            encoder_args = {
                '--oac=libopus',
                '--oacopts-add=application=voip',
                '--oacopts-add=apply_phase_inv=0', -- Improves mono audio.
            }
            if self.config.opus_container == 'm4a' then
                table.insert(encoder_args, '--of=mp4')
            end
        else
            -- https://wiki.hydrogenaud.io/index.php?title=LAME#Recommended_encoder_settings:
            -- "For very low bitrates, up to 100kbps, ABR is most often the best solution."
            encoder_args = {
                '--oac=libmp3lame',
                '--oacopts-add=compression_level=0',
                '--oacopts-add=abr=1',
            }
        end

        local args = make_mpvargs(
                '--oacopts-add=b=' .. self.config.audio_bitrate,
                '-o=' .. output_path,
                h.unpack(encoder_args)
        )
        if loudnorm_args then
            table.insert(args, '--af-append=' .. loudnorm_args)
        end
        args_consumer(args)
    end

    if not self.config.loudnorm then
        make_encoding_args(nil)
        return
    end

    local loudnorm_targets = make_loudnorm_targets()
    h.subprocess(
            make_mpvargs(
                    '-v',
                    '--af-append=' .. loudnorm_targets .. ':print_format=json',
                    '--ao=null',
                    '--of=null'
            ),
            parse_loudnorm(
                    loudnorm_targets,
                    function(stdout, stderr)
                        local start, stop, json = string.find(stdout, '%[ffmpeg%] ({.-})')
                        if json then
                            json = string.gsub(json, '%[ffmpeg%]', '')
                        end
                        return json
                    end,
                    make_encoding_args
            )
    )
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

local report_creation_result = function(file_path)
    return function(success, result)
        -- result is nil on success for screenshot-to-file.
        if success and (result == nil or result.status == 0) and h.file_exists(file_path) then
            msg.info(string.format("Created file: %s", file_path))
            return true
        else
            msg.error(string.format("Couldn't create file: %s", file_path))
            return false
        end
    end
end

local create_snapshot = function(start_timestamp, end_timestamp, current_timestamp, filename)
    if h.is_empty(self.output_dir_path) then
        return msg.error("Output directory wasn't provided. Image file will not be created.")
    end

    -- Calls the proper function depending on whether or not the snapshot should be animated
    if not h.is_empty(self.config.image_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.output_dir_path, filename)

        local on_finish = report_creation_result(output_path)
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
    if h.is_empty(self.output_dir_path) then
        return msg.error("Output directory wasn't provided. Audio file will not be created.")
    end

    if not h.is_empty(self.config.audio_field) then
        local source_path = mp.get_property("path")
        local output_path = utils.join_path(self.output_dir_path, filename)

        if padding > 0 then
            start_timestamp, end_timestamp = pad_timings(padding, start_timestamp, end_timestamp)
        end

        local function start_encoding(args)
            local on_finish = function(success, result)
                local conversion_check = report_creation_result(output_path)
                if conversion_check(success, result) and self.config.preview_audio then
                    background_play(output_path, function()
                        print("Played file: " .. output_path)
                    end)
                end
            end

            h.subprocess(args, on_finish)
        end

        self.encoder.make_audio_args(
                source_path, output_path, start_timestamp, end_timestamp, start_encoding)
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

local init = function(config)
    -- Sets the module to its preconfigured status
    self.config = config
    self.encoder = config.use_ffmpeg and ffmpeg or mpv
end

local set_output_dir = function(dir_path)
    -- Set directory where media files should be saved.
    -- This function is called every time a card is created or updated.
    self.output_dir_path = dir_path
end

local create_job = function(type, sub, audio_padding)
    local filename, run_async, current_timestamp
    if type == 'snapshot' and h.has_video_track() then
        current_timestamp = mp.get_property_number("time-pos", 0)
        filename = make_snapshot_filename(sub['start'], sub['end'], current_timestamp)
        run_async = function()
            create_snapshot(sub['start'], sub['end'], current_timestamp, filename)
        end
    elseif type == 'audioclip' and h.has_audio_track() then
        filename = make_audio_filename(sub['start'], sub['end'])
        run_async = function()
            create_audio(sub['start'], sub['end'], filename, audio_padding)
        end
    else
        run_async = function()
            print(type .. " will not be created.")
        end
    end
    return {
        filename = filename,
        run_async = run_async,
    }
end

return {
    init = init,
    set_output_dir = set_output_dir,
    snapshot = {
        create_job = function(sub)
            return create_job('snapshot', sub)
        end,
        toggle_animation = toggle_animation,
    },
    audio = {
        create_job = function(sub, padding)
            return create_job('audioclip', sub, padding)
        end,
    },
}
