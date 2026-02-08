--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Check what codecs are supported by mpv.
If a desired codec is not supported, set the "use_ffmpeg" config option to "yes".
]]

local mp = require('mp')
local h = require('helpers')
local exec = require('encoder.executables')

local self = {}

self.avif_encoders = {
    'av1_qsv',
    'libaom-av1',
    'libsvtav1',
}

local function result_to_str(result)
    if result and result.status == 0 then
        return (result.stdout or "") .. (result.stderr or "")
    else
        return ""
    end
end

local function query_mpv_codec_support()
    local ovc_help = result_to_str(h.subprocess { args = { exec.mpv, '--ovc=help' } })
    local oac_help = result_to_str(h.subprocess { args = { exec.mpv, '--oac=help' } })

    local function is_audio_supported(codec)
        return h.is_substr(oac_help, '--oac=' .. codec)
    end

    local function is_image_supported(codec)
        return h.is_substr(ovc_help, '--ovc=' .. codec)
    end

    local results = {
        snapshot = {
            libwebp = is_image_supported('libwebp'),
            mjpeg = is_image_supported('mjpeg'),
        },
        audio = {
            libmp3lame = is_audio_supported('libmp3lame'),
            libopus = is_audio_supported('libopus'),
        },
    }

    for _, avif_codec in ipairs(self.avif_encoders) do
        results['snapshot'][avif_codec] = is_image_supported(avif_codec)
    end
    return results
end

local function query_ffmpeg_codec_support()
    local encoders_list = result_to_str(h.subprocess { args = { exec.ffmpeg, "-hide_banner", "-encoders" } })

    local function has_ffmpeg_encoder(codec_name)
        return h.is_substr(encoders_list, codec_name)
    end

    local results = {
        snapshot = {
            libwebp = has_ffmpeg_encoder('libwebp'),
            mjpeg = has_ffmpeg_encoder('mjpeg'),
        },
        audio = {
            libmp3lame = has_ffmpeg_encoder('libmp3lame'),
            libopus = has_ffmpeg_encoder('libopus'),
        },
    }
    for _, avif_codec in ipairs(self.avif_encoders) do
        results['snapshot'][avif_codec] = has_ffmpeg_encoder(avif_codec)
    end
    return results
end

local function msg_print_results(program, result_table)
    for type, codecs in pairs(result_table) do
        for codec, supported in pairs(codecs) do
            mp.msg.info(string.format("program %s %s %s codec %s.", program, (supported and "supports" or "does NOT support"), type, codec))
        end
    end
end

self.mpv_support = query_mpv_codec_support()
self.ffmpeg_support = query_ffmpeg_codec_support()

msg_print_results('mpv', self.mpv_support)
msg_print_results('ffmpeg', self.ffmpeg_support)

return self
