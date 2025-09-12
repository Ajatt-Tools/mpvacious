--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

AnkiConnect requests
]]

local utils = require('mp.utils')
local msg = require('mp.msg')
local h = require('helpers')
local self = {}

self.execute = function(request, completion_fn)
    if not h.is_empty(self.config.ankiconnect_api_key) then
        request.key = self.config.ankiconnect_api_key
    end

    -- utils.format_json returns a string
    -- On error, request_json will contain "null", not nil.
    local request_json, error = utils.format_json(request)

    if error ~= nil or request_json == "null" then
        return completion_fn and completion_fn()
    else
        return self.platform.curl_request(self.config.ankiconnect_url, request_json, completion_fn)
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

self.get_media_dir_path = function()
    -- Ask AnkiConnect where to store media files.
    -- If AnkiConnect isn't running, returns nil.

    local ret = self.execute({
        action = "getMediaDirPath",
        version = 6,
    })
    local dir_path, error = self.parse_result(ret)
    if not error then
        return dir_path
    else
        msg.error(string.format("Couldn't retrieve path to collection.media folder: %s", error))
        return nil
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
            self.gui_browse("nid:" .. note_id) -- show the added note
        else
            h.notify(string.format("Error: %s.", error), "error", 2)
        end
    end
    self.execute(args, result_notify)
end

self.get_last_note_ids = function(n_cards)
    local ret = self.execute {
        action = "findNotes",
        version = 6,
        params = {
            query = "added:1" -- find all notes added today
        }
    }

    local note_ids, _ = self.parse_result(ret)

    if not h.is_empty(note_ids) then
        return h.get_last_n_added_notes(note_ids, n_cards)
    else
        return {}
    end
end

self.get_selected_note_ids = function()
    local ret = self.execute {
        action = "guiSelectedNotes",
        version = 6
    }

    local note_ids, _ = self.parse_result(ret)
    return note_ids
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

self.get_first_field = function(model_name)
    local ret = self.execute {
        action = "findModelsByName",
        version = 6,
        params = {
            modelNames = { model_name }
        }
    }

    local result, error = self.parse_result(ret)

    if error == nil then
        for _, field in pairs(result[1].flds) do
            if field.ord == 0 then
                return field.name
            end
        end
    else
        msg.error(string.format("Couldn't retrieve the first field's name of note type %s: %s", model_name, error))
        return nil
    end
end

self.gui_browse = function(query)
    --- query is a string, e.g. "deck:current", "nid:12345"
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

self.append_media = function(note_id, fields, tag, on_finish_fn)
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

    local on_finish_wrap = function(_, result, _)
        local _, error = self.parse_result(result)
        if not error then
            self.add_tag(note_id, tag)
        else
            h.notify(string.format("Error: %s.", error), "error", 2)
        end
        on_finish_fn(error)
    end

    self.execute(args, on_finish_wrap)
end

self.init = function(config, platform)
    self.config = config
    self.platform = platform
end

return self
