--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

The new note timer feature allows mpvacious to automatically detect and update new Anki notes.
When enabled, mpvacious will periodically check for new notes
and automatically add media (audio and images) to them if they match your configured note type.
]]

local mp = require("mp")
local msg = require("mp.msg")
local h = require("helpers")

--- Create a new-note checker with optional mpv-compatible dependencies.
local function make_anki_new_note_checker(components)
    components = components or {}
    local mp_api = components.mp or mp
    local logger = components.logger or msg
    -- Once every X seconds, check if there's a new note.
    -- If a new note has been added, check if it matches the configured note type (see the config file):
    -- * deck_name
    -- * model_name
    -- * sentence_field
    -- If it matches, update the note and add its note_id to a local ignore list because we don't want to update it again.

    local ignore_note_ids = {}
    local accept_notes_made_within_last_minutes = 2
    local self = {}

    local function is_note_ignored(note_id)
        return ignore_note_ids[note_id] == true
    end

    local function add_to_ignore_list(note_id)
        ignore_note_ids[note_id] = true
    end

    local function is_note_recent(note_id)
        return note_id >= h.minutes_ago(accept_notes_made_within_last_minutes)
    end

    --- on_completed = fn(note_ids, error)
    local function find_notes_added_today(on_completed)
        return self.ankiconnect.find_notes {
            query = string.format('added:1 "note:%s" "deck:%s"', self.config.model_name, self.config.deck_name),
            suppress_log = true,
            completion_fn = on_completed,
        }
    end

    local function ignore_all_cards_added_today()
        -- initially, ignore all existing cards.
        local function on_completed(note_ids, error)
            if not h.is_empty(error) then
                logger.error(error)
            end
            if not h.is_empty(note_ids) then
                for _, note_id in ipairs(note_ids) do
                    add_to_ignore_list(note_id)
                end
            end
        end
        return find_notes_added_today(on_completed)
    end

    local function has_no_media(note_fields)
        -- Mpvacious will try to update every new note, including the ones added by Mpvacious itself.
        -- To avoid updating notes added by mpvacious, check if the note already has media.
        return h.is_empty(note_fields[self.config.audio_field]) and h.is_empty(note_fields[self.config.image_field])
    end

    --- Return whether the note has the configured sentence field, is recent, and has no media.
    local function is_note_eligible_for_update(note_id, note_fields)
        -- The configured sentence field identifies the expected note type, even when its value is blank.
        -- Notes added by mpvacious already have media and must not be updated again.
        return not h.is_empty(note_fields)
            and note_fields[self.config.sentence_field] ~= nil
            and is_note_recent(note_id)
            and has_no_media(note_fields)
    end

    --- Inspect one note once per checker session and add it to `to_update` when eligible.
    local function collect_note_for_update(note_id, to_update)
        if is_note_ignored(note_id) then
            return
        end
        -- Get note info to check whether it matches the user's configured note type.
        local note_fields, error = self.ankiconnect.get_note_fields(note_id)
        if error then
            -- An unavailable server or deleted note cannot be updated safely.
            -- Log the failed read once rather than repeating it on every timer tick.
            logger.error(string.format("failed to retrieve note %s: %s", tostring(note_id), error))
        elseif is_note_eligible_for_update(note_id, note_fields) then
            -- The note matches the configured type and can be updated (just like pressing Ctrl+M does).
            table.insert(to_update, note_id)
        end
        -- Process each discovered ID once per checker session, including failed
        -- reads and ineligible notes. Manual updates remain available for a retry.
        add_to_ignore_list(note_id)
    end

    --- Inspect newly discovered note IDs, skipping those already handled in this checker session.
    local function process_new_notes(note_ids, error)
        if not h.is_empty(error) and not h.is_substr(error, "isn't running") then
            logger.error("failed to check new notes: " .. error)
        end
        if h.is_empty(note_ids) then
            -- no new notes added today yet.
            return
        end
        local to_update = {}
        for _, note_id in ipairs(note_ids) do
            collect_note_for_update(note_id, to_update)
        end
        if not h.is_empty(to_update) then
            self.update_notes_fn(to_update, false)
        end
    end

    local function check_for_new_notes()
        return find_notes_added_today(process_new_notes)
    end

    local function start_timer()
        if h.is_empty(self.config) then
            logger.error("attempt to start new note checker before init.")
            return
        end
        if not self.config.enable_new_note_timer then
            logger.info("new note checker disabled.")
            return
        end
        ignore_all_cards_added_today()
        -- docs: https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
        if self.timer == nil then
            self.timer = mp_api.add_periodic_timer(self.config.new_note_timer_interval_seconds, check_for_new_notes)
        end
        logger.info("new note checker started.")
    end

    local function stop_timer()
        if self.timer ~= nil then
            self.timer:kill()
            self.timer = nil
        end
        logger.info("new note checker stopped.")
    end

    local function init(ankiconnect, update_notes_fn, cfg_mgr)
        cfg_mgr.fail_if_not_ready()
        self.ankiconnect = ankiconnect
        self.update_notes_fn = update_notes_fn
        self.config = cfg_mgr.config()
    end

    return {
        start_timer = start_timer,
        stop_timer = stop_timer,
        init = init,
    }
end

return {
    new = make_anki_new_note_checker,
}
