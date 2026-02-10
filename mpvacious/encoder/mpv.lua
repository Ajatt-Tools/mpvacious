--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder that uses mpv to create media files.
]]

local mp = require('mp')
local codec_support = require('encoder.codec_support')
local h = require('helpers')
local eutils = require('encoder.utils')
local exec = require('encoder.executables')

local function make_mpv_encoder(cfg_mgr)
    local self = { }
    self.cfg_mgr = cfg_mgr
    self.config = cfg_mgr.config()

    self.choose_avif_encoder = function()
        for _, codec_name in ipairs(codec_support.avif_encoders) do
            if codec_support.mpv_support['snapshot'][codec_name] then
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

    self.prepend_common_args = function(source_path, ...)
        return {
            exec.mpv,
            source_path,
            '--no-config',
            '--loop-file=no',
            '--keep-open=no',
            '--no-sub',
            '--no-ocopy-metadata',
            ...,
        }
    end

    self.make_static_snapshot_args = function(source_path, output_path, timestamp)
        local encoder_args
        if self.config.snapshot_format == 'avif' then
            encoder_args = {
                '--ovc=' .. self.config.snapshot_codec,
                -- cpu-used < 6 can take a lot of time to encode.
                '--ovcopts-add=cpu-used=6',
                string.format('--ovcopts-add=crf=%d', eutils.quality_to_crf_avif(self.config.snapshot_quality)),
                '--ovcopts-add=still-picture=1',
            }
        elseif self.config.snapshot_format == 'webp' then
            encoder_args = {
                '--ovc=' .. self.config.snapshot_codec,
                '--ovcopts-add=compression_level=6',
                string.format('--ovcopts-add=quality=%d', self.config.snapshot_quality),
            }
        else
            encoder_args = {
                '--ovc=' .. self.config.snapshot_codec,
                '--vf-add=scale=out_range=jpeg',
                string.format(
                        '--ovcopts=global_quality=%d*QP2LAMBDA,flags=+qscale',
                        eutils.quality_to_jpeg_qscale(self.config.snapshot_quality)
                ),
            }
        end

        return self.prepend_common_args(
                source_path,
                '--audio=no',
                '--frames=1',
                '--start=' .. eutils.toms(timestamp),
                string.format('--vf-add=lavfi=[%s]', eutils.static_scale_filter(self.config)),
                '-o=' .. output_path,
                h.unpack(encoder_args)
        )
    end

    self.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
        local encoder_args
        if self.config.animated_snapshot_format == 'avif' then
            encoder_args = {
                '--ovc=' .. self.config.animated_snapshot_codec,
                -- cpu-used < 6 can take a lot of time to encode.
                '--ovcopts-add=cpu-used=6',
                string.format('--ovcopts-add=crf=%d', eutils.quality_to_crf_avif(self.config.animated_snapshot_quality)),
            }
        else
            encoder_args = {
                '--ovc=' .. self.config.animated_snapshot_codec,
                '--ovcopts-add=compression_level=6',
                string.format('--ovcopts-add=quality=%d', self.config.animated_snapshot_quality),
            }
        end

        return self.prepend_common_args(
                source_path,
                '--audio=no',
                '--start=' .. eutils.toms(start_timestamp),
                '--end=' .. eutils.toms(end_timestamp),
                '--ofopts-add=loop=0',
                string.format('--vf-add=fps=%d', self.config.animated_snapshot_fps),
                string.format('--vf-add=lavfi=[%s]', eutils.animated_scale_filter(self.config)),
                '-o=' .. output_path,
                h.unpack(encoder_args)
        )
    end

    self.make_audio_args = function(source_path, output_path,
                                    start_timestamp, end_timestamp, args_consumer)
        local audio_track = h.get_active_track('audio')
        local audio_track_id = mp.get_property("aid")

        if audio_track and audio_track.external == true then
            source_path = audio_track['external-filename']
            audio_track_id = 'auto'
        end

        local function make_mpvargs(...)
            local args = self.prepend_common_args(
                    source_path,
                    '--video=no',
                    '--aid=' .. audio_track_id,
                    '--audio-channels=mono',
                    '--start=' .. eutils.toms(start_timestamp),
                    '--end=' .. eutils.toms(end_timestamp),
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
                    '--oac=' .. self.config.audio_codec,
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
                    '--oac=' .. self.config.audio_codec,
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

        local loudnorm_targets = eutils.make_loudnorm_targets(self.config)
        h.subprocess {
            args = make_mpvargs(
                    '-v',
                    '--af-append=' .. loudnorm_targets .. ':print_format=json',
                    '--ao=null',
                    '--of=null'
            ),
            completion_fn = eutils.parse_loudnorm(
                    loudnorm_targets,
                    function(stdout, _) -- function takes stdout, stderr
                        local _, _, json = string.find(stdout, '%[ffmpeg%] ({.-})') -- returns: start, stop, json
                        if json then
                            json = string.gsub(json, '%[ffmpeg%]', '')
                            mp.msg.info("json: " .. tostring(json))
                        end
                        return json
                    end,
                    make_encoding_args
            )
        }
    end

    return self
end

return {
    new = make_mpv_encoder,
}
