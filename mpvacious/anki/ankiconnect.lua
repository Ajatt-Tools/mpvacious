--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

AnkiConnect requests
]]

local utils = require('mp.utils')
local msg = require('mp.msg')
local h = require('helpers')
local platform = require('platform.init')

--- Extract plain fields from one notesInfo item without mutating it.
--- Missing notes/fields are errors, but an empty string is a valid field value.
local function extract_note_fields(raw_fields, note_id)
    if type(raw_fields) ~= 'table' or h.is_empty(raw_fields) then
        return nil, string.format("AnkiConnect returned no fields for note %s", tostring(note_id))
    end
    local fields = {}
    for name, field in pairs(raw_fields) do
        if type(field) ~= 'table' or type(field.value) ~= 'string' then
            return nil, string.format("AnkiConnect returned invalid fields for note %s", tostring(note_id))
        end
        fields[name] = field.value
    end
    return fields, nil
end

--- Decode notesInfo items and verify every requested note ID is present.
local function decode_note_fields(result, note_ids)
    if type(result) ~= 'table' or h.is_empty(result) then
        return nil, "AnkiConnect returned no requested notes"
    end
    local fields_by_note_id = {}
    for _, note_info in pairs(result) do
        if type(note_info) ~= 'table' or note_info.noteId == nil then
            return nil, "AnkiConnect returned note fields without a note ID"
        end
        local fields, error = extract_note_fields(note_info.fields, note_info.noteId)
        if error then
            return nil, error
        end
        fields_by_note_id[note_info.noteId] = fields
    end
    -- Prove the snapshot is complete independently of AnkiConnect's response order.
    for _, note_id in pairs(note_ids) do
        if fields_by_note_id[note_id] == nil then
            return nil, string.format("AnkiConnect returned no fields for note %s", tostring(note_id))
        end
    end
    return fields_by_note_id, nil
end

--- Create an AnkiConnect client for note and media requests.
local function make_ankiconnect(components)
    components = components or {}
    local logger = components.logger or msg
    local self = {}

    --- Parameters: request, completion_fn, suppress_log
    --- completion_fn = fn(success, result, error)
    --- https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
    self.execute = function(o)
        if not h.is_empty(self.config.ankiconnect_api_key) then
            o.request.key = self.config.ankiconnect_api_key
        end

        -- utils.format_json returns a string
        -- On error, request_json will contain "null", not nil.
        local request_json, error = utils.format_json(o.request)

        if error ~= nil or request_json == "null" then
            return o.completion_fn and o.completion_fn()
        else
            return platform.json_curl_request {
                url = self.config.ankiconnect_url,
                request_json = request_json,
                completion_fn = o.completion_fn,
                suppress_log = o.suppress_log,
            }
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

    --- Note: h.subprocess() accepts completion_fn with args (success, result, error)
    --- But this function accepts completion_fn with args (parsed_json, error)
    self.make_result_parser_async = function(on_completed)
        if on_completed == nil then
            on_completed = function(_, _)
                -- parsed_json, error
                msg.warn("Ignoring Ankiconnect result")
            end
        end
        return function(success, result, error)
            local parsed_json
            if success and not error then
                parsed_json, error = self.parse_result(result)
                on_completed(parsed_json, error)
            else
                on_completed(nil, tostring(error))
            end
        end
    end

    --- Return the Anki media directory, or an error when it cannot be retrieved.
    self.get_media_dir_path = function()
        -- Ask AnkiConnect where to store media files.
        -- If AnkiConnect isn't running, returns nil.
        local request = {
            action = "getMediaDirPath",
            version = 6,
        }
        local ret = self.execute { request = request }
        local dir_path, error = self.parse_result(ret)
        if error then
            return nil, error
        end
        if not h.is_non_empty_str(dir_path) then
            return nil, 'AnkiConnect returned no media directory'
        end
        return dir_path, nil
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
        local result_notify = function(_, error)
            if not error then
                msg.info(string.format("Deck %s: check completed.", deck_name))
            else
                msg.warn(string.format("Deck %s: check failed. Reason: %s.", deck_name, error))
            end
        end
        self.execute { request = args, completion_fn = self.make_result_parser_async(result_notify) }
    end

    self.add_note = function(note_fields, tag, gui)
        -- https://git.sr.ht/~foosoft/anki-connect#codeaddnotecode
        -- "result" is integer
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
        local result_notify = function(note_id, error)
            if not error then
                h.notify(string.format("Note added. ID = %s.", note_id))
                self.gui_browse("nid:" .. note_id) -- show the added note
            else
                h.notify(string.format("Error: %s.", error), "error", 2)
            end
        end
        self.execute { request = args, completion_fn = self.make_result_parser_async(result_notify) }
    end

    --- Parameters; query, completion_fn, suppress_log
    --- completion_fn = fn(note_ids, error) where note_ids is None | list
    --- https://git.sr.ht/~foosoft/anki-connect#codefindnotescode
    self.find_notes = function(o)
        local request = {
            action = "findNotes",
            version = 6,
            params = {
                query = o.query
            }
        }
        if o.completion_fn then
            return self.execute {
                request = request,
                suppress_log = (not not o.suppress_log),
                completion_fn = self.make_result_parser_async(o.completion_fn)
            }
        else
            return self.parse_result(self.execute {
                request = request,
                suppress_log = (not not o.suppress_log)
            })
        end
    end

    self.get_last_note_ids = function(n_cards)
        local note_ids = self.find_notes { query = "added:1" } -- find all notes added today
        if not h.is_empty(note_ids) then
            return h.get_last_n_added_notes(note_ids, n_cards)
        else
            return {}
        end
    end

    self.get_selected_note_ids = function()
        local request = {
            action = "guiSelectedNotes",
            version = 6
        }
        local ret = self.execute { request = request }

        local note_ids, _ = self.parse_result(ret)
        return note_ids
    end

    --- Return note fields keyed by note ID, or an AnkiConnect error.
    --- https://git.sr.ht/~foosoft/anki-connect/tree/master/item/README.md#codenotesinfocode
    self.get_notes_fields = function(note_ids)
        local request = {
            action = "notesInfo",
            version = 6,
            params = {
                notes = note_ids
            }
        }
        local ret = self.execute { request = request }

        local result, error = self.parse_result(ret)

        if error ~= nil then
            return nil, error
        end
        local fields_by_note_id, fields_error = decode_note_fields(result, note_ids)
        if fields_error then
            return nil, fields_error
        end
        return fields_by_note_id, nil
    end

    --- Return (fields, nil) on success or (nil, error) when one note cannot be read.
    self.get_note_fields = function(note_id)
        local fields_by_note_id, error = self.get_notes_fields({ note_id })
        if error then
            return nil, error
        end
        return fields_by_note_id[note_id], nil
    end

    self.get_first_field = function(model_name)
        local request = {
            action = "findModelsByName",
            version = 6,
            params = {
                modelNames = { model_name }
            }
        }
        local ret = self.execute { request = request }
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
            local request = {
                action = 'guiBrowse',
                version = 6,
                params = {
                    query = query
                }
            }
            self.execute { request = request }
        end
    end

    self.add_tag = function(note_id, tag)
        if not h.is_empty(tag) then
            local request = {
                action = 'addTags',
                version = 6,
                params = {
                    notes = { note_id },
                    tags = tag
                }
            }
            self.execute { request = request }
        end
    end

    self.append_media = function(note_id, fields, tag, on_finish_fn)
        -- AnkiConnect will fail to update the note if it's selected in the Anki Browser.
        -- https://github.com/FooSoft/anki-connect/issues/82
        -- Switch focus from the current note to avoid it.
        self.gui_browse("nid:1") -- impossible nid

        local request = {
            action = "updateNoteFields",
            version = 6,
            params = {
                note = {
                    id = note_id,
                    fields = fields,
                }
            }
        }

        local on_finish_wrap = function(result, error)
            if not error then
                self.add_tag(note_id, tag)
            else
                -- The update context reports combined write errors after all targets finish.
                logger.error(string.format("Failed to update note %s: %s", tostring(note_id), tostring(error)))
            end
            on_finish_fn(result, error)
        end

        self.execute { request = request, completion_fn = self.make_result_parser_async(on_finish_wrap) }
    end

    self.init = function(cfg_mgr)
        cfg_mgr.fail_if_not_ready()
        self.config = cfg_mgr.config()
    end

    return self
end

return {
    new = make_ankiconnect,
}
