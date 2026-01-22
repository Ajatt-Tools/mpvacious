--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local mp = require('mp')
local msg = require('mp.msg')
local h = require('helpers')

local function make_anki_new_note_checker()
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

    local function check_for_new_notes()
        -- Find notes added today.
        local note_ids = self.ankiconnect.find_notes(string.format("added:1 \"note:%s\" \"deck:%s\"", self.config.model_name, self.config.deck_name))
        if h.is_empty(note_ids) then
            msg.info("no new notes added today yet.")
            return
        end
        for _, note_id in ipairs(note_ids) do
            if not is_note_ignored(note_id) then
                -- Get note info to check if it matches the user's config
                local note_fields = self.ankiconnect.get_note_fields(note_id)
                -- Check if the note has the configured sentence field.
                if not h.is_empty(note_fields) and note_fields[self.config.sentence_field] ~= nil and is_note_recent(note_id) then
                    -- Note matches our criteria, update it (just like pressing Ctrl+M does).
                    self.update_notes_fn({note_id}, false)
                end
                -- Add to ignore list regardless of whether we updated it or not.
                -- This prevents the function from processing the same notes over and over.
                add_to_ignore_list(note_id)
            end
        end
    end

    return {
        start_timer = function()
            if h.is_empty(self.config) then
                msg.error("attempt to start new note checker before init.")
                return
            end
            if not self.config.enable_new_note_timer then
                msg.info("new note checker disabled.")
                return
            end
            -- docs: https://github.com/mpv-player/mpv/blob/master/DOCS/man/lua.rst#mp-functions
            if self.timer == nil then
                self.timer = mp.add_periodic_timer(self.config.new_note_timer_interval_seconds, check_for_new_notes)
            end
            msg.info("new note checker started.")
        end,
        stop_timer = function()
            if self.timer ~= nil then
                self.timer:kill()
                self.timer = nil
            end
            msg.info("new note checker stopped.")
        end,
        init = function(ankiconnect, update_notes_fn, config)
            self.ankiconnect = ankiconnect
            self.update_notes_fn = update_notes_fn
            self.config = config
        end
    }
end

return {
    new = make_anki_new_note_checker
}
