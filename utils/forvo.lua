--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Utils for downloading pronunciations from Forvo
]]

local utils = require('mp.utils')
local msg = require('mp.msg')
local h = require('helpers')
local base64 = require('utils.base64')
local self = {
    output_dir_path = nil,
}

local function url_encode(url)
    -- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
    local char_to_hex = function(c)
        return string.format("%%%02X", string.byte(c))
    end
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w _%%%-%.~])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

local function reencode(source_path, dest_path)
    local args = {
        'mpv',
        source_path,
        '--loop-file=no',
        '--keep-open=no',
        '--video=no',
        '--no-ocopy-metadata',
        '--no-sub',
        '--audio-channels=mono',
        '--oacopts-add=vbr=on',
        '--oacopts-add=application=voip',
        '--oacopts-add=compression_level=10',
        '--af-append=silenceremove=1:0:-50dB',
        table.concat { '--oac=', self.config.audio_codec },
        table.concat { '--of=', self.config.audio_format },
        table.concat { '--oacopts-add=b=', self.config.audio_bitrate },
        table.concat { '-o=', dest_path }
    }
    return h.subprocess(args)
end

local function reencode_and_store(source_path, filename)
    local reencoded_path = utils.join_path(self.output_dir_path, filename)
    local result = reencode(source_path, reencoded_path)
    return result.status == 0
end

local function curl_save(source_url, save_location)
    local curl_args = { 'curl', source_url, '-s', '-L', '-o', save_location }
    return h.subprocess(curl_args).status == 0
end

local function get_pronunciation_url(word)
    local file_format = self.config.audio_extension:sub(2)
    local forvo_page = h.subprocess { 'curl', '-s', string.format('https://forvo.com/search/%s/ja', url_encode(word)) }.stdout
    local play_params = string.match(forvo_page, "Play%((.-)%);")

    if play_params then
        local iter = string.gmatch(play_params, "'(.-)'")
        local formats = { mp3 = iter(), ogg = iter() }
        return string.format('https://audio00.forvo.com/%s/%s', file_format, base64.dec(formats[file_format]))
    end
end

local function make_forvo_filename(word)
    return string.format('forvo_%s%s', self.platform.windows and os.time() or word, self.config.audio_extension)
end

local function get_forvo_pronunciation(word)
    local audio_url = get_pronunciation_url(word)

    if h.is_empty(audio_url) then
        msg.warn(string.format("Seems like Forvo doesn't have audio for word %s.", word))
        return
    end

    local filename = make_forvo_filename(word)
    local tmp_filepath = utils.join_path(self.platform.tmp_dir(), filename)

    local result
    if curl_save(audio_url, tmp_filepath) and reencode_and_store(tmp_filepath, filename) then
        result = string.format(self.config.audio_template, filename)
    else
        msg.warn(string.format("Couldn't download audio for word %s from Forvo.", word))
    end

    os.remove(tmp_filepath)
    return result
end

local append = function(new_data, stored_data)
    if self.config.use_forvo == 'no' then
        -- forvo functionality was disabled in the config file
        return new_data
    end

    if type(stored_data[self.config.vocab_audio_field]) ~= 'string' then
        -- there is no field configured to store forvo pronunciation
        return new_data
    end

    if h.is_empty(stored_data[self.config.vocab_field]) then
        -- target word field is empty. can't continue.
        return new_data
    end

    if self.config.use_forvo == 'always' or h.is_empty(stored_data[self.config.vocab_audio_field]) then
        local forvo_pronunciation = get_forvo_pronunciation(stored_data[self.config.vocab_field])
        if not h.is_empty(forvo_pronunciation) then
            if self.config.vocab_audio_field == self.config.audio_field then
                -- improperly configured fields. don't lose sentence audio
                new_data[self.config.audio_field] = forvo_pronunciation .. new_data[self.config.audio_field]
            else
                new_data[self.config.vocab_audio_field] = forvo_pronunciation
            end
        end
    end

    return new_data
end

local set_output_dir = function(dir_path)
    self.output_dir_path = dir_path
end

local function init(config, platform)
    self.config = config
    self.platform = platform
end

return {
    append = append,
    init = init,
    set_output_dir = set_output_dir,
}
