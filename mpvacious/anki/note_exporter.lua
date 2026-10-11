--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html
]]

local h = require('helpers')
local note_update_context = require('anki.note_update_context')
local snapshot = require('config.snapshot')

--- Create the public Anki note export command adapter.
local function make_exporter()
    local self = {}
    local pub = {}

    --- Return the current config.
    local function config()
        return self.cfg_mgr.config()
    end

    --- Discard subtitle selection and quick options when the source file changes.
    function pub.reset_for_file_change()
        if self.subs_observer == nil then
            return pub
        end
        self.subs_observer.clear()
        self.quick_creation_opts:clear_options()
        return pub
    end

    --- Reload configuration before creating a card when configured.
    function pub.maybe_reload_config()
        if config().reload_config_before_card_creation then
            self.cfg_mgr.reload_from_disk()
        end
        return pub
    end

    --- Dispatch new-note export through a context captured before preflight.
    function pub.export_to_anki(gui)
        pub.maybe_reload_config()
        self.note_update_context
            .new(snapshot.new(self.cfg_mgr))
            .export_note(gui)
        return pub
    end

    --- Dispatch recent-note lookup and updating through one captured context.
    function pub.update_last_note(overwrite)
        pub.maybe_reload_config()
        self.note_update_context
            .new(snapshot.new(self.cfg_mgr))
            .update_last_note(overwrite)
        return pub
    end

    --- Dispatch a timer-driven or direct update without changing reload behavior.
    function pub.update_notes(note_ids, overwrite)
        self.note_update_context
            .new(snapshot.new(self.cfg_mgr))
            .update_notes(note_ids, overwrite)
        return pub
    end

    --- Dispatch selected-note lookup and updating through one captured context.
    function pub.update_selected_note(overwrite)
        pub.maybe_reload_config()
        self.note_update_context
            .new(snapshot.new(self.cfg_mgr))
            .update_selected_note(overwrite)
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
        self.notify = components.notify or h.notify
        self.note_update_context = note_update_context.new({
            ankiconnect = self.ankiconnect,
            quick_creation_opts = self.quick_creation_opts,
            subs_observer = self.subs_observer,
            encoder = self.encoder,
            forvo = self.forvo,
            cfg_mgr = self.cfg_mgr,
            mp = components.mp,
        })
        return pub
    end

    return pub
end

return {
    new = make_exporter,
}
