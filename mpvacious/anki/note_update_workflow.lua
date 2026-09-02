--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Coordinate guarded Anki note updates and their confirmation lifecycle.
]]

local h = require("helpers")

--- Return the confirmation question for the number of target notes.
local function update_question(note_count)
    if note_count == 1 then
        return "Update this note anyway?"
    else
        return string.format("Update all %i notes anyway?", note_count)
    end
end

--- Create the workflow that validates, confirms, and performs note updates.
local function make_note_update_workflow(components)
    local self = {
        context = components.context,
        confirmation = components.confirmation,
        notify = components.notify,
        exporter = components.exporter,
    }
    local pub = {}

    --- Queue a confirmation after sentence validation reports a mismatch.
    local function confirm_update(request, warning)
        self.confirmation.confirm {
            prompt = warning .. "\n" .. update_question(#request.target_notes),
            on_accept = function()
                self.context.perform_update(request)
            end,
            -- A declined prompt is not an update, so timings remain available for a retry.
            on_cancel = h.noop,
        }
        return self.exporter
    end

    --- Collect one subtitle and either update immediately or ask for confirmation.
    function pub.update_notes(request)
        self.confirmation.cancel()
        local subtitle = self.context.collect_subtitle()
        if not subtitle:is_valid() then
            self.notify("Nothing to export. Have you set the timings?", "warn", 4)
            return self.exporter
        end
        local preparation = self.context.prepare_update_request {
            note_ids = h.itable_slice(request.note_ids),
            overwrite = request.overwrite,
            options = request.options or {},
            subtitle = subtitle,
        }
        if preparation.error then
            self.notify(preparation.error, "error", 3)
            return self.exporter
        end
        if h.is_empty(preparation.warning) then
            self.context.perform_update(preparation.request)
            return self.exporter
        end
        return confirm_update(preparation.request, preparation.warning)
    end

    return pub
end

return { new = make_note_update_workflow }
