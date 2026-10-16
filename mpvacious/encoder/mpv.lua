--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder that uses mpv to create media files.
]]

local mp = require("mp")
local codec_support = require("encoder.codec_support")
local h = require("helpers")
local eutils = require("encoder.utils")
local exec = require("encoder.executables")

--- Create an mpv backend with optional codec support and isolated I/O dependencies.
local function make_mpv_encoder(cfg_mgr, support, components)
    support = support or codec_support
    components = components or {}
    local subprocess = components.subprocess or h.subprocess
    local get_active_track = components.get_active_track or h.get_active_track
    local mp_api = components.mp or mp
    local logger = components.logger or mp.msg
    local self = {}
    local public = {}

    ------------------------------------------------------------
    --- Private

    self.cfg_mgr = cfg_mgr

    --- Select the first supported AVIF encoder for private codec initialization.
    function self.choose_avif_encoder()
        for _, codec_name in ipairs(support.avif_encoders) do
            if support.mpv_support["snapshot"][codec_name] then
                return codec_name
            end
        end
        return nil
    end

    --- Return the active encoding configuration.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Prepend private mpv process arguments for the supplied source.
    local function prepend_common_args(source_path, ...)
        return {
            exec.mpv,
            source_path,
            "--no-config",
            "--loop-file=no",
            "--keep-open=no",
            "--no-sub",
            "--no-ocopy-metadata",
            ...,
        }
    end

    --- Build shared AVIF options and enable still-picture mode only for static snapshots.
    local function make_avif_encoder_args(codec, quality, still_picture)
        local args = {
            "--ovc=" .. codec,
            -- cpu-used < 6 can take a lot of time to encode.
            "--ovcopts-add=cpu-used=6",
            string.format("--ovcopts-add=crf=%d", eutils.quality_to_crf_avif(quality)),
        }
        if still_picture then
            table.insert(args, "--ovcopts-add=still-picture=1")
        end
        return args
    end

    --- Build codec and quality arguments for the configured static image format.
    local function make_encoder_args()
        if config().snapshot_format == "avif" then
            return make_avif_encoder_args(self.snapshot_codec, config().snapshot_quality, true)
        elseif config().snapshot_format == "webp" then
            return {
                "--ovc=" .. self.snapshot_codec,
                "--ovcopts-add=compression_level=6",
                string.format("--ovcopts-add=quality=%d", config().snapshot_quality),
            }
        else
            return {
                "--ovc=" .. self.snapshot_codec,
                "--vf-add=scale=out_range=jpeg",
                string.format(
                    "--ovcopts=global_quality=%d*QP2LAMBDA,flags=+qscale",
                    eutils.quality_to_jpeg_qscale(config().snapshot_quality)
                ),
            }
        end
    end

    --- Build codec and quality arguments for the configured animated image format.
    local function make_animated_encoder_args()
        if config().animated_snapshot_format == "avif" then
            return make_avif_encoder_args(self.animated_snapshot_codec, config().animated_snapshot_quality, false)
        else
            return {
                "--ovc=" .. self.animated_snapshot_codec,
                "--ovcopts-add=compression_level=6",
                string.format("--ovcopts-add=quality=%d", config().animated_snapshot_quality),
            }
        end
    end

    --- Build static snapshot selection, scaling, and destination arguments.
    local function make_additional_args(track, output_path, timestamp)
        local additional_args = {}
        if track and track.albumart == true then
            table.insert(additional_args, "--vid=" .. tostring(track.id or "auto"))
        else
            table.insert(additional_args, "--start=" .. eutils.toms(timestamp))
        end
        table.insert(additional_args, string.format("--vf-add=lavfi=[%s]", eutils.static_scale_filter(config())))
        table.insert(additional_args, "-o=" .. output_path)
        return additional_args
    end

    ------------------------------------------------------------
    --- Public

    --- Refresh backend-local codecs without modifying configuration.
    public.init = function()
        eutils.set_codecs(self, config())
    end

    --- Build a static snapshot, selecting attached cover art without a timestamp seek.
    public.make_static_snapshot_args = function(source_path, output_path, timestamp, track)
        return h.join_lists(
            prepend_common_args(source_path, "--audio=no", "--frames=1"),
            make_additional_args(track, output_path, timestamp),
            make_encoder_args()
        )
    end

    --- Build the command for an animated snapshot using initialized codecs.
    public.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
        return prepend_common_args(
            source_path,
            "--audio=no",
            "--start=" .. eutils.toms(start_timestamp),
            "--end=" .. eutils.toms(end_timestamp),
            "--ofopts-add=loop=0",
            string.format("--vf-add=fps=%d", config().animated_snapshot_fps),
            string.format("--vf-add=lavfi=[%s]", eutils.animated_scale_filter(config())),
            "-o=" .. output_path,
            h.unpack(make_animated_encoder_args())
        )
    end

    --- Build audio arguments and deliver them after optional loudness analysis.
    public.make_audio_args = function(source_path, output_path, sub, args_consumer)
        local audio_track = get_active_track("audio")
        local audio_track_id = mp_api.get_property("aid")

        if audio_track and audio_track.external == true then
            source_path = audio_track["external-filename"]
            audio_track_id = "auto"
        end

        --- Build audio arguments using the captured source, track, and timing window.
        local function make_mpvargs(...)
            local args = prepend_common_args(
                source_path,
                "--video=no",
                "--aid=" .. audio_track_id,
                "--audio-channels=mono",
                "--start=" .. eutils.toms(sub["start"]),
                "--end=" .. eutils.toms(sub["end"]),
                string.format("--volume=%d", config().tie_volumes and mp_api.get_property("volume") or 100),
                ...
            )
            for arg in string.gmatch(config().mpv_audio_args, "%S+") do
                table.insert(args, arg)
            end
            return args
        end

        --- Deliver the final audio command with configured codec and normalization options.
        local function make_encoding_args(loudnorm_args)
            local encoder_args
            if config().audio_format == "opus" then
                encoder_args = {
                    "--oac=" .. config().audio_codec,
                    "--oacopts-add=application=voip",
                    "--oacopts-add=apply_phase_inv=0", -- Improves mono audio.
                }
                if config().opus_container == "m4a" then
                    table.insert(encoder_args, "--of=mp4")
                end
            else
                -- https://wiki.hydrogenaud.io/index.php?title=LAME#Recommended_encoder_settings:
                -- "For very low bitrates, up to 100kbps, ABR is most often the best solution."
                encoder_args = {
                    "--oac=" .. config().audio_codec,
                    "--oacopts-add=compression_level=0",
                    "--oacopts-add=abr=1",
                }
            end

            local args =
                make_mpvargs("--oacopts-add=b=" .. config().audio_bitrate, "-o=" .. output_path, h.unpack(encoder_args))
            if loudnorm_args then
                table.insert(args, "--af-append=" .. loudnorm_args)
            end
            args_consumer(args)
        end

        if not config().loudnorm then
            make_encoding_args(nil)
            return
        end

        local loudnorm_targets = eutils.make_loudnorm_targets(config())
        subprocess {
            args = make_mpvargs(
                "-v",
                "--af-append=" .. loudnorm_targets .. ":print_format=json",
                "--ao=null",
                "--of=null"
            ),
            completion_fn = eutils.parse_loudnorm(loudnorm_targets, function(stdout, _)
                -- function takes stdout, stderr
                local _, _, json = string.find(stdout, "%[ffmpeg%] ({.-})") -- returns: start, stop, json
                if json then
                    json = string.gsub(json, "%[ffmpeg%]", "")
                    logger.info("json: " .. tostring(json))
                end
                return json
            end, make_encoding_args, components),
        }
    end

    return public
end

return {
    new = make_mpv_encoder,
}
