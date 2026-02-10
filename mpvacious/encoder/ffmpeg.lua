--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder that uses ffmpeg to create media files.
]]

local mp = require('mp')
local codec_support = require('encoder.codec_support')
local h = require('helpers')
local eutils = require('encoder.utils')
local exec = require('encoder.executables')

local function make_ffmpeg_encoder(cfg_mgr)
    local self = { }
    self.cfg_mgr = cfg_mgr
    self.config = cfg_mgr.config()

    self.prepend = function(...)
        return {
            exec.ffmpeg, "-hide_banner", "-nostdin", "-y", "-loglevel", "quiet", "-sn",
            ...,
        }
    end

    self.choose_avif_encoder = function()
        for _, codec_name in ipairs(codec_support.avif_encoders) do
            if codec_support.ffmpeg_support['snapshot'][codec_name] then
                return codec_name
            end
        end
        return nil
    end

    self.set_avif_encoder = function()
        local chosen = self.choose_avif_encoder()
        if h.is_empty(chosen) then
            return
        end

        if self.config.snapshot_format == 'avif' then
            self.config.snapshot_codec = chosen
        end
        if self.config.animated_snapshot_format == 'avif' then
            self.config.animated_snapshot_codec = chosen
        end
    end

    local function make_avif_encoder_args(quality_value, is_still_picture)
        local codec = (function()
            if is_still_picture then
                return self.config.snapshot_codec
            else
                return self.config.animated_snapshot_codec
            end
        end)()

        if codec == 'libsvtav1' then
            return {
                '-c:v', codec,
                '-preset', '8',
                -- Avif quality can be controlled with crf.
                '-crf', tostring(eutils.quality_to_crf_avif(quality_value)),
                '-svtav1-params', 'avif=1',
            }
        else
            local args = {
                '-c:v', codec,
                -- cpu-used < 6 can take a lot of time to encode.
                '-cpu-used', '6',
                -- Avif quality can be controlled with crf.
                '-crf', tostring(eutils.quality_to_crf_avif(quality_value)),
            }
            if is_still_picture then
                table.insert(args, '-still-picture')
                table.insert(args, '1')
            end
            return args
        end
    end

    self.make_static_snapshot_args = function(source_path, output_path, timestamp)
        local encoder_args
        if self.config.snapshot_format == 'avif' then
            encoder_args = make_avif_encoder_args(self.config.snapshot_quality, true)
        elseif self.config.snapshot_format == 'webp' then
            encoder_args = {
                '-c:v', self.config.snapshot_codec,
                '-compression_level', '6',
                '-quality', tostring(self.config.snapshot_quality),
            }
        else
            encoder_args = {
                '-c:v', self.config.snapshot_codec,
                '-q:v', tostring(eutils.quality_to_jpeg_qscale(self.config.snapshot_quality)),
            }
        end

        local args = self.prepend(
                '-an',
                '-ss', eutils.toms(timestamp),
                '-i', source_path,
                '-map_metadata', '-1',
                '-vf', eutils.static_scale_filter(self.config),
                '-frames:v', '1',
                h.unpack(encoder_args)
        )
        table.insert(args, output_path)
        return args
    end

    self.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
        local encoder_args
        if self.config.animated_snapshot_format == 'avif' then
            encoder_args = make_avif_encoder_args(self.config.animated_snapshot_quality, false)
        else
            -- Documentation: https://www.ffmpeg.org/ffmpeg-all.html#libwebp
            encoder_args = {
                '-c:v', self.config.animated_snapshot_codec,
                '-compression_level', '6',
                '-quality', tostring(self.config.animated_snapshot_quality),
            }
        end

        local args = self.prepend(
                '-an',
                '-ss', eutils.toms(start_timestamp),
                '-to', eutils.toms(end_timestamp),
                '-i', source_path,
                '-map_metadata', '-1',
                '-loop', '0',
                '-vf', string.format(
                        'fps=%d,%s',
                        self.config.animated_snapshot_fps,
                        eutils.animated_scale_filter(self.config)
                ),
                h.unpack(encoder_args)
        )
        table.insert(args, output_path)
        return args
    end

    local function add_filter(filters, filter)
        if #filters == 0 then
            return filter
        else
            return string.format('%s,%s', filters, filter)
        end
    end

    local function separate_filters(filters, new_args, args)
        -- Would've strongly preferred
        --     if args[i] == '-af' or args[i] == '-filter:a' then
        --         i = i + 1
        --         add_filter(args[i])
        -- but https://lua.org/manual/5.4/manual.html#3.3.5 says that
        -- "You should not change the value of the control variable during the loop."
        local expect_filter = false
        for i = 1, #args do
            if args[i] == '-af' or args[i] == '-filter:a' then
                expect_filter = true
            else
                if expect_filter then
                    filters = add_filter(filters, args[i])
                else
                    table.insert(new_args, args[i])
                end
                expect_filter = false
            end
        end
        return filters
    end

    self.append_user_audio_args = function(args)
        local new_args = {}
        local filters = ''

        filters = separate_filters(filters, new_args, args)
        if self.config.tie_volumes then
            filters = add_filter(filters, string.format("volume=%.1f", mp.get_property_native('volume') / 100.0))
        end

        local user_args = {}
        for arg in string.gmatch(self.config.ffmpeg_audio_args, "%S+") do
            table.insert(user_args, arg)
        end
        filters = separate_filters(filters, new_args, user_args)

        if #filters > 0 then
            table.insert(new_args, '-af')
            table.insert(new_args, filters)
        end
        return new_args
    end

    self.make_audio_args = function(
            source_path, output_path, start_timestamp, end_timestamp, args_consumer
    )
        local audio_track = h.get_active_track('audio')
        local audio_track_id = audio_track and audio_track['ff-index'] or 'a'

        if audio_track and audio_track.external == true then
            source_path = audio_track['external-filename']
            audio_track_id = 'a'
        end

        local function make_ffargs(...)
            return self.append_user_audio_args(
                    self.prepend(
                            '-vn',
                            '-ss', eutils.toms(start_timestamp),
                            '-to', eutils.toms(end_timestamp),
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
                    '-c:a', self.config.audio_codec,
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
                    '-c:a', self.config.audio_codec,
                    '-compression_level', '0',
                    '-abr', '1',
                }
            end

            encoder_args = { '-b:a', tostring(self.config.audio_bitrate), h.unpack(encoder_args) }
            if loudnorm_args then
                table.insert(encoder_args, '-af')
                table.insert(encoder_args, loudnorm_args)
            end
            local args = make_ffargs(h.unpack(encoder_args))
            table.insert(args, output_path)
            args_consumer(args)
        end

        if not self.config.loudnorm then
            make_encoding_args(nil)
            return
        end

        local loudnorm_targets = eutils.make_loudnorm_targets(self.config)
        local args = make_ffargs(
                '-loglevel', 'info',
                '-af', loudnorm_targets .. ':print_format=json'
        )
        table.insert(args, '-f')
        table.insert(args, 'null')
        table.insert(args, '-')
        h.subprocess {
            args = args,
            completion_fn = eutils.parse_loudnorm(
                    loudnorm_targets,
                    function(_, stderr) -- function takes stdout, stderr
                        local _, _, json = string.find(stderr, '%[Parsed_loudnorm_0.-({.-})') -- returns: start, stop, json
                        mp.msg.info("json: " .. tostring(json))
                        return json
                    end,
                    make_encoding_args
            )
        }
    end

    return self
end

return {
    new = make_ffmpeg_encoder,
}
