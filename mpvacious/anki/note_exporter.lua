--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local h = require("helpers")
local note_update_guard = require("anki.note_update_guard")
local note_update_context = require("anki.note_update_context")
local snapshot = require("config.snapshot")
local note_update_workflow = require("anki.note_update_workflow")
local confirmation_module = require("menu.confirmation")

local LOOKUP_WARNING_DURATION_SECONDS = 4

--- Create the public Anki note export command adapter.
local function make_exporter()
    local self = {}
    local pub = {}

    --- Return the current config.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Bind field and media dependencies into a note-update context.
    local function make_update_context(components)
        return note_update_context.new({
            ankiconnect = self.ankiconnect,
            quick_creation_opts = self.quick_creation_opts,
            subs_observer = self.subs_observer,
            encoder = self.encoder,
            forvo = self.forvo,
            cfg_mgr = self.cfg_mgr,
            note_update_guard = self.note_update_guard,
            mp = components.mp,
            notify = self.notify,
        })
    end

    --- Bind the captured context and shared confirmation UI into one request workflow.
    local function make_update_workflow(context)
        return note_update_workflow.new {
            context = context,
            confirmation = self.confirmation,
            notify = self.notify,
            exporter = pub,
        }
    end

    ------------------------------------------------------------
    --- Public

    --- Discard subtitle selection and quick options when the source file changes.
    function pub.reset_for_file_change()
        if self.subs_observer == nil then
            return pub
        end
        self.subs_observer.clear()
        self.quick_creation_opts:clear_options()
        return pub
    end

    --- Cancel any pending note-update confirmation.
    function pub.cancel_pending_update()
        if self.confirmation ~= nil then
            self.confirmation.cancel()
        end
    end

    --- Cancel confirmation and discard timings when the source file changes.
    function pub.cancel_pending_update_for_file_change()
        pub.cancel_pending_update()
        return pub.reset_for_file_change()
    end

    --- Reload configuration before creating a card when configured.
    function pub.maybe_reload_config()
        if config().reload_config_before_card_creation then
            self.cfg_mgr.reload_from_disk()
        end
        return pub
    end

    --- Dispatch new-note export through a context captured before model and media-directory checks.
    function pub.export_to_anki(gui)
        pub.maybe_reload_config()
        self.note_update_context.new(snapshot.new(self.cfg_mgr)).export_note(gui)
        return pub
    end

    --- Dispatch recent-note lookup and updating through one captured context.
    function pub.update_last_note(overwrite)
        pub.maybe_reload_config()
        local context = self.note_update_context.new(snapshot.new(self.cfg_mgr))
        local note_ids, error = context.find_recent_note_ids()
        if error then
            pub.cancel_pending_update()
            self.notify(error, "warn", LOOKUP_WARNING_DURATION_SECONDS)
            return pub
        end
        make_update_workflow(context).update_notes {
            note_ids = note_ids,
            overwrite = overwrite,
            options = { check_recent_notes = true },
        }
        return pub
    end

    --- Dispatch a timer-driven or direct update without changing reload behavior.
    function pub.update_notes(note_ids, overwrite)
        local context = self.note_update_context.new(snapshot.new(self.cfg_mgr))
        make_update_workflow(context).update_notes {
            note_ids = note_ids,
            overwrite = overwrite,
        }
        return pub
    end

    --- Update notes selected in the Anki Browser.
    function pub.update_selected_note(overwrite)
        pub.maybe_reload_config()
        local context = self.note_update_context.new(snapshot.new(self.cfg_mgr))
        local note_ids, error = context.find_selected_note_ids()
        if error then
            pub.cancel_pending_update()
            self.notify(error, "warn", LOOKUP_WARNING_DURATION_SECONDS)
            return pub
        end
        make_update_workflow(context).update_notes { note_ids = note_ids, overwrite = overwrite }
        return pub
    end

    --- Initialize the exporter with its named dependencies.
    function pub.init(components)
        components.cfg_mgr.fail_if_not_ready()
        self.cfg_mgr = components.cfg_mgr
        self.ankiconnect = components.ankiconnect
        self.quick_creation_opts = components.quick_creation_opts
        self.subs_observer = components.subs_observer
        self.encoder = components.encoder
        self.forvo = components.forvo
        self.note_update_guard = components.note_update_guard or note_update_guard.new()
        self.confirmation = components.confirmation or confirmation_module.new()
        self.notify = components.notify or h.notify
        self.note_update_context = make_update_context(components)
        return pub
    end

    return pub
end

return {
    new = make_exporter,
}
