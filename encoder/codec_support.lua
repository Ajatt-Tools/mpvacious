--[[
Copyright: Ajatt-Tools and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Check what codecs are supported by mpv.
If a desired codec is not supported, set the "use_ffmpeg" config option to "yes".
]]

local mp = require('mp')
local h = require('helpers')

local ovc_help = h.subprocess { 'mpv', '--ovc=help' }
local oac_help = h.subprocess { 'mpv', '--oac=help' }

local function is_audio_supported(codec)
    return oac_help.status == 0 and oac_help.stdout:find('--oac=' .. codec, 1, true) ~= nil
end

local function is_image_supported(codec)
    return ovc_help.status == 0 and ovc_help.stdout:find('--ovc=' .. codec, 1, true) ~= nil
end

local inspection_result = {
    snapshot = {
        ['libaom-av1'] = is_image_supported('libaom-av1'),
        libwebp = is_image_supported('libwebp'),
        mjpeg = is_image_supported('mjpeg'),
    },
    audio = {
        libmp3lame = is_audio_supported('libmp3lame'),
        libopus = is_audio_supported('libopus'),
    },
}
for type, codecs in pairs(inspection_result) do
    for codec, supported in pairs(codecs) do
        mp.msg.info(string.format("mpv supports %s codec %s: %s", type, codec, tostring(supported)))
    end
end

return inspection_result
