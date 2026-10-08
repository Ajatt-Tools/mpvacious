--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Utils for downloading pronunciations from Forvo
]]

local utils = require('mp.utils')
local msg = require('mp.msg')
local h = require('helpers')
local base64 = require('utils.base64')
local platform = require('platform.init')

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

--- Accept only explicit successful command results.
local function command_succeeded(result)
    return type(result) == 'table' and result.status == 0
end

local function curl_save(source_url, save_location, platform_api)
    local curl_args = { source_url, '-s', '-L', '-o', save_location }
    return command_succeeded(platform_api.curl_request { args = curl_args })
end

--- Create a pronunciation downloader with optional platform, encoding, cleanup, and logging dependencies.
local function make_forvo(components)
    components = components or {}
    local self = {
        output_dir_path = nil,
        platform_api = components.platform or platform,
        subprocess = components.subprocess or h.subprocess,
        remove_file = components.remove_file or os.remove,
        logger = components.logger or msg,
    }
    local pub = {}

    --- Private

    local function config()
        return self.cfg_mgr.config()
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
            table.concat { '--oac=', config().audio_codec },
            table.concat { '--of=', config().audio_format },
            table.concat { '--oacopts-add=b=', config().audio_bitrate },
            table.concat { '-o=', dest_path }
        }
        return self.subprocess { args = args }
    end

    local function reencode_and_store(source_path, filename)
        local reencoded_path = utils.join_path(self.output_dir_path, filename)
        local result = reencode(source_path, reencoded_path)
        return command_succeeded(result)
    end

    local function make_forvo_filename(word)
        return string.format('forvo_%s%s', self.platform_api.windows and os.time() or word, config().audio_extension)
    end

    --- Return the pronunciation search page or a fetch error.
    local function fetch_pronunciation_page(word)
        -- Search this word on forvo.
        local curl_args = { '-s', string.format('https://forvo.com/search/%s/ja', url_encode(word)) }
        local response = self.platform_api.curl_request { args = curl_args }
        -- Only a successful request with a nonempty page can contain usable pronunciation data.
        if not command_succeeded(response) or not h.is_non_empty_str(response.stdout) then
            return nil, "forvo pronunciation webpage fetch failed"
        end
        return response.stdout, nil
    end

    local function get_pronunciation_url(word)
        -- Forvo offers MP3 and OGG sources, regardless of the destination container.
        local file_format = 'ogg'
        if config().audio_format == 'mp3' then
            file_format = 'mp3'
        end

        local forvo_page, error = fetch_pronunciation_page(word)
        if error then
            return nil, error
        end
        local play_params = string.match(forvo_page, "Play%((.-)%);")

        if play_params then
            local iter = string.gmatch(play_params, "'(.-)'")
            local formats = { mp3 = iter(), ogg = iter() }
            return string.format('https://audio00.forvo.com/%s/%s', file_format, base64.dec(formats[file_format]))
        end
    end

    local function get_forvo_pronunciation(word)
        local audio_url, error = get_pronunciation_url(word)
        if error then
            self.logger.warn(error)
            return
        end

        if h.is_empty(audio_url) then
            self.logger.warn(string.format("Seems like Forvo doesn't have audio for word %s.", word))
            return
        end

        local filename = make_forvo_filename(word)
        local tmp_filepath = utils.join_path(self.platform_api.tmp_dir(), filename)

        local result
        if curl_save(audio_url, tmp_filepath, self.platform_api) and reencode_and_store(tmp_filepath, filename) then
            result = string.format(config().audio_template, filename)
        else
            self.logger.warn(string.format("Couldn't download audio for word %s from Forvo.", word))
        end

        self.remove_file(tmp_filepath)
        return result
    end

    --- Public

    function pub.append(new_data, stored_data)
        if config().use_forvo == 'no' then
            -- forvo functionality was disabled in the config file
            return new_data
        end

        if type(stored_data[config().vocab_audio_field]) ~= 'string' then
            -- there is no field configured to store forvo pronunciation
            return new_data
        end

        if h.is_empty(stored_data[config().vocab_field]) then
            -- target word field is empty. can't continue.
            return new_data
        end

        if config().use_forvo == 'always' or h.is_empty(stored_data[config().vocab_audio_field]) then
            local forvo_pronunciation = get_forvo_pronunciation(stored_data[config().vocab_field])
            if not h.is_empty(forvo_pronunciation) then
                if config().vocab_audio_field == config().audio_field then
                    -- improperly configured fields. don't lose sentence audio
                    new_data[config().audio_field] = forvo_pronunciation .. new_data[config().audio_field]
                else
                    new_data[config().vocab_audio_field] = forvo_pronunciation
                end
            end
        end

        return new_data
    end

    function pub.set_output_dir(dir_path)
        self.output_dir_path = dir_path
    end

    function pub.init(cfg_mgr)
        self.cfg_mgr = cfg_mgr
        self.cfg_mgr.fail_if_not_ready()
    end

    return pub
end

return {
    new = make_forvo,
}
