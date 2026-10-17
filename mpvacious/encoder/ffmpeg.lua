--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder that uses ffmpeg to create media files.
]]

local mp = require("mp")
local codec_support = require("encoder.codec_support")
local h = require("helpers")
local eutils = require("encoder.utils")
local exec = require("encoder.executables")

--- Create an FFmpeg backend with optional codec support and isolated I/O dependencies.
local function make_ffmpeg_encoder(cfg_mgr, support, components)
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
            if support.ffmpeg_support["snapshot"][codec_name] then
                return codec_name
            end
        end
        return nil
    end

    --- Return the active encoding configuration.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Return the selected AVIF codec or the configured fallback.
    local function get_avif_codec(is_still_picture)
        if is_still_picture then
            return self.snapshot_codec
        else
            return self.animated_snapshot_codec
        end
    end

    --- Build codec-specific AVIF options for a still or animated snapshot.
    local function make_avif_encoder_args(quality_value, is_still_picture)
        local avif_codec = get_avif_codec(is_still_picture)
        if avif_codec == "libsvtav1" then
            return {
                "-c:v",
                avif_codec,
                "-preset",
                "8",
                -- Avif quality can be controlled with crf.
                "-crf",
                tostring(eutils.quality_to_crf_avif(quality_value)),
                "-svtav1-params",
                "avif=1",
            }
        else
            local args = {
                "-c:v",
                avif_codec,
                -- cpu-used < 6 can take a lot of time to encode.
                "-cpu-used",
                "6",
                -- Avif quality can be controlled with crf.
                "-crf",
                tostring(eutils.quality_to_crf_avif(quality_value)),
            }
            if is_still_picture then
                table.insert(args, "-still-picture")
                table.insert(args, "1")
            end
            return args
        end
    end

    local function add_filter(filters, filter)
        if #filters == 0 then
            return filter
        else
            return string.format("%s,%s", filters, filter)
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
            if args[i] == "-af" or args[i] == "-filter:a" then
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

    --- Prepend common FFmpeg process arguments.
    local function prepend_common_args(...)
        return {
            exec.ffmpeg,
            "-hide_banner",
            "-nostdin",
            "-y",
            "-loglevel",
            "quiet",
            "-sn",
            ...,
        }
    end

    --- Merge configured audio filters and arguments into a private command.
    local function append_user_audio_args(args)
        local new_args = {}
        local filters = ""

        filters = separate_filters(filters, new_args, args)
        if config().tie_volumes then
            filters = add_filter(filters, string.format("volume=%.1f", mp_api.get_property_native("volume") / 100.0))
        end

        local user_args = {}
        for arg in string.gmatch(config().ffmpeg_audio_args, "%S+") do
            table.insert(user_args, arg)
        end
        filters = separate_filters(filters, new_args, user_args)

        if #filters > 0 then
            table.insert(new_args, "-af")
            table.insert(new_args, filters)
        end
        return new_args
    end

    --- Select the captured cover stream without seeking, or seek ordinary timed video.
    local function make_input_args(track, source_path, timestamp)
        -- track is a table returned by h.get_active_track()
        if track and track.albumart == true then
            local stream = "0:v:0"
            if track["ff-index"] ~= nil then
                stream = string.format("0:%s", tostring(track["ff-index"]))
            end
            return prepend_common_args("-an", "-i", source_path, "-map", stream)
        else
            return prepend_common_args("-an", "-ss", eutils.toms(timestamp), "-i", source_path)
        end
    end

    --- Build codec and quality arguments for the configured static image format.
    local function make_snapshot_encoder_args()
        if config().snapshot_format == "avif" then
            return make_avif_encoder_args(config().snapshot_quality, true)
        elseif config().snapshot_format == "webp" then
            return {
                "-c:v",
                self.snapshot_codec,
                "-compression_level",
                "6",
                "-quality",
                tostring(config().snapshot_quality),
            }
        else
            return {
                "-c:v",
                self.snapshot_codec,
                "-q:v",
                tostring(eutils.quality_to_jpeg_qscale(config().snapshot_quality)),
            }
        end
    end

    --- Build codec and quality arguments for the configured animated image format.
    local function make_animated_encoder_args()
        if config().animated_snapshot_format == "avif" then
            return make_avif_encoder_args(config().animated_snapshot_quality, false)
        else
            -- Documentation: https://www.ffmpeg.org/ffmpeg-all.html#libwebp
            return {
                "-c:v",
                self.animated_snapshot_codec,
                "-compression_level",
                "6",
                "-quality",
                tostring(config().animated_snapshot_quality),
            }
        end
    end

    --- Suppress metadata and apply static image dimensions with a one-frame limit.
    local function make_additional_args()
        return {
            "-map_metadata",
            "-1",
            "-vf",
            eutils.static_scale_filter(config()),
            "-frames:v",
            "1",
        }
    end

    --- Build audio arguments using the captured source, track, and timing window.
    local function make_audio_ffargs(sub, source_path, audio_track_id, ...)
        return append_user_audio_args(
            prepend_common_args(
                "-vn",
                "-ss",
                eutils.toms(sub["start"]),
                "-to",
                eutils.toms(sub["end"]),
                "-i",
                source_path,
                "-map_metadata",
                "-1",
                "-map_chapters",
                "-1",
                "-map",
                string.format("0:%s", tostring(audio_track_id)),
                "-ac",
                "1",
                ...
            )
        )
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
            make_input_args(track, source_path, timestamp),
            make_additional_args(),
            make_snapshot_encoder_args(),
            { output_path }
        )
    end

    --- Build the command for an animated snapshot using initialized codecs.
    public.make_animated_snapshot_args = function(source_path, output_path, start_timestamp, end_timestamp)
        return h.join_lists(
            prepend_common_args(
                "-an",
                "-ss",
                eutils.toms(start_timestamp),
                "-to",
                eutils.toms(end_timestamp),
                "-i",
                source_path,
                "-map_metadata",
                "-1",
                "-loop",
                "0",
                "-vf",
                string.format("fps=%d,%s", config().animated_snapshot_fps, eutils.animated_scale_filter(config()))
            ),
            make_animated_encoder_args(),
            { output_path }
        )
    end

    --- Build audio arguments and deliver them after optional loudness analysis.
    public.make_audio_args = function(source_path, output_path, sub, args_consumer)
        local audio_track = get_active_track("audio")
        local audio_track_id = audio_track and audio_track["ff-index"] or "a"

        if audio_track and audio_track.external == true then
            source_path = audio_track["external-filename"]
            audio_track_id = "a"
        end

        --- Deliver the final audio command with configured codec and normalization options.
        local function make_encoding_args(loudnorm_args)
            local encoder_args
            if config().audio_format == "opus" then
                encoder_args = {
                    "-c:a",
                    config().audio_codec,
                    "-application",
                    "voip",
                    "-apply_phase_inv",
                    "0", -- Improves mono audio.
                }
                if config().opus_container == "m4a" then
                    table.insert(encoder_args, "-f")
                    table.insert(encoder_args, "mp4")
                end
            else
                -- https://wiki.hydrogenaud.io/index.php?title=LAME#Recommended_encoder_settings:
                -- "For very low bitrates, up to 100kbps, ABR is most often the best solution."
                encoder_args = {
                    "-c:a",
                    config().audio_codec,
                    "-compression_level",
                    "0",
                    "-abr",
                    "1",
                }
            end

            encoder_args = { "-b:a", tostring(config().audio_bitrate), h.unpack(encoder_args) }
            if loudnorm_args then
                table.insert(encoder_args, "-af")
                table.insert(encoder_args, loudnorm_args)
            end
            local args = make_audio_ffargs(sub, source_path, audio_track_id, h.unpack(encoder_args))
            table.insert(args, output_path)
            args_consumer(args)
        end

        if not config().loudnorm then
            make_encoding_args(nil)
            return
        end

        local loudnorm_targets = eutils.make_loudnorm_targets(config())
        local args = make_audio_ffargs(
            sub,
            source_path,
            audio_track_id,
            "-loglevel",
            "info",
            "-af",
            loudnorm_targets .. ":print_format=json"
        )
        table.insert(args, "-f")
        table.insert(args, "null")
        table.insert(args, "-")
        subprocess {
            args = args,
            completion_fn = eutils.parse_loudnorm(loudnorm_targets, function(_, stderr)
                -- function takes stdout, stderr
                local _, _, json = string.find(stderr, "%[Parsed_loudnorm_0.-({.-})") -- returns: start, stop, json
                logger.info("json: " .. tostring(json))
                return json
            end, make_encoding_args, components),
        }
    end

    return public
end

return {
    new = make_ffmpeg_encoder,
}
