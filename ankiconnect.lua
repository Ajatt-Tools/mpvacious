--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

AnkiConnect requests
]]

local utils = require('mp.utils')
local msg = require('mp.msg')
local h = require('helpers')
local base64 = require('utils.base64')
local self = {}

self.execute = function(request, completion_fn)
    -- utils.format_json returns a string
    -- On error, request_json will contain "null", not nil.
    local request_json, error = utils.format_json(request)

    if error ~= nil or request_json == "null" then
        return completion_fn and completion_fn()
    else
        return self.platform.curl_request(request_json, completion_fn)
    end
end

self.parse_result = function(curl_output)
    -- there are two values that we actually care about: result and error
    -- but we need to crawl inside to get them.

    if curl_output == nil then
        return nil, "Failed to format json or no args passed"
    end

    if curl_output.status ~= 0 then
        return nil, "Ankiconnect isn't running"
    end

    local stdout_json = utils.parse_json(curl_output.stdout)

    if stdout_json == nil then
        return nil, "Fatal error from Ankiconnect"
    end

    if stdout_json.error ~= nil then
        return nil, tostring(stdout_json.error)
    end

    return stdout_json.result, nil
end

self.store_file = function(filename, file_path)
    -- read the contents of the file and encode it in base64
    -- this allows files to be stored even if Anki runs in a sandboxed environment
    -- and thus doesn not have access to the host filesystem
    local file = io.open(file_path, "rb")
    if file == nil then
        msg.error(string.format("Couldn't open for reading: '%s'", filename))
        return false
    end
    local data = base64.enc(file:read("*a"))
    file:close()

    -- construct args
    local args = {
        action = "storeMediaFile",
        version = 6,
        params = {
            filename = filename,
            data = data,
        }
    }

    local ret = self.execute(args)
    local _, error = self.parse_result(ret)
    if not error then
        msg.info(string.format("File stored: '%s'.", filename))
        return true
    else
        msg.error(string.format("Couldn't store file '%s': %s", filename, error))
        return false
    end
end

self.create_deck = function(deck_name)
    local args = {
        action = "changeDeck",
        version = 6,
        params = {
            cards = {},
            deck = deck_name
        }
    }
    local result_notify = function(_, result, _)
        local _, error = self.parse_result(result)
        if not error then
            msg.info(string.format("Deck %s: check completed.", deck_name))
        else
            msg.warn(string.format("Deck %s: check failed. Reason: %s.", deck_name, error))
        end
    end
    self.execute(args, result_notify)
end

self.add_note = function(note_fields, tag, gui)
    local action = gui and 'guiAddCards' or 'addNote'
    local args = {
        action = action,
        version = 6,
        params = {
            note = {
                deckName = self.config.deck_name,
                modelName = self.config.model_name,
                fields = note_fields,
                options = {
                    allowDuplicate = self.config.allow_duplicates,
                    duplicateScope = "deck",
                },
                tags = h.is_empty(tag) and {} or { tag, },
            }
        }
    }
    local result_notify = function(_, result, _)
        local note_id, error = self.parse_result(result)
        if not error then
            h.notify(string.format("Note added. ID = %s.", note_id))
        else
            h.notify(string.format("Error: %s.", error), "error", 2)
        end
    end
    self.execute(args, result_notify)
end

self.get_last_note_id = function()
    local ret = self.execute {
        action = "findNotes",
        version = 6,
        params = {
            query = "added:1" -- find all notes added today
        }
    }

    local note_ids, _ = self.parse_result(ret)

    if not h.is_empty(note_ids) then
        return h.max_num(note_ids)
    else
        return -1
    end
end

self.get_note_fields = function(note_id)
    local ret = self.execute {
        action = "notesInfo",
        version = 6,
        params = {
            notes = { note_id }
        }
    }

    local result, error = self.parse_result(ret)

    if error == nil then
        result = result[1].fields
        for key, value in pairs(result) do
            result[key] = value.value
        end
        return result
    else
        return nil
    end
end

self.gui_browse = function(query)
    if not self.config.disable_gui_browse then
        self.execute {
            action = 'guiBrowse',
            version = 6,
            params = {
                query = query
            }
        }
    end
end

self.add_tag = function(note_id, tag)
    if not h.is_empty(tag) then
        self.execute {
            action = 'addTags',
            version = 6,
            params = {
                notes = { note_id },
                tags = tag
            }
        }
    end
end

self.append_media = function(note_id, fields, create_media_fn, tag)
    -- AnkiConnect will fail to update the note if it's selected in the Anki Browser.
    -- https://github.com/FooSoft/anki-connect/issues/82
    -- Switch focus from the current note to avoid it.
    self.gui_browse("nid:1") -- impossible nid

    local args = {
        action = "updateNoteFields",
        version = 6,
        params = {
            note = {
                id = note_id,
                fields = fields,
            }
        }
    }

    local on_finish = function(_, result, _)
        local _, error = self.parse_result(result)
        if not error then
            create_media_fn()
            self.add_tag(note_id, tag)
            self.gui_browse(string.format("nid:%s", note_id)) -- select the updated note in the card browser
            h.notify(string.format("Note #%s updated.", note_id))
        else
            h.notify(string.format("Error: %s.", error), "error", 2)
        end
    end

    self.execute(args, on_finish)
end

self.init = function(config, platform)
    self.config = config
    self.platform = platform
end

return self
