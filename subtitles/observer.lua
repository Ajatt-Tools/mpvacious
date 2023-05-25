--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Observer waits for subtitles to appear on the screen and adds them to a list.
]]

local h = require('helpers')
local timings = require('utils.timings')
local sub_list = require('subtitles.sub_list')
local Subtitle = require('subtitles.subtitle')
local mp = require('mp')
local platform = require('platform.init')

local self = {}

local dialogs = sub_list.new()
local secondary_dialogs = sub_list.new()
local user_timings = timings.new()

local append_dialogue = false
local autoclip_enabled = false

------------------------------------------------------------
-- private

local function external_command_args(lookup_word)
    local args = {}
    for arg in string.gmatch(self.config.autoclip_command, "%S+") do
        table.insert(args, arg)
    end
    table.insert(args, self.clipboard_prepare(lookup_word))
    return args
end

local function on_external_finish(success, result, error)
    if success ~= true or error ~= nil then
        h.notify("Command failed: " .. table.concat(result))
    end
end

local function call_autocopy_command(text)
    if h.is_empty(text) then
        return
    end
    -- If autoclip command is not set, copy to the clipboard.
    -- If it is set, run the external command.
    if h.is_empty(self.config.autoclip_command) then
        self.copy_to_clipboard("autocopy action", text)
    else
        h.subprocess(external_command_args(text), on_external_finish)
    end
end

local function recorded_or_current_text()
    --- Join and return all observed text.
    --- If there's no observed text, return the current text on screen.
    local text = dialogs.get_text()
    if h.is_empty(text) then
        return mp.get_property("sub-text")
    else
        return text
    end
end

local function copy_primary_sub()
    if autoclip_enabled then
        call_autocopy_command(recorded_or_current_text())
    end
end

local function append_primary_sub()
    if append_dialogue and dialogs.insert(Subtitle:now()) then
        self.menu:update()
    end
end

local function append_secondary_sub()
    if append_dialogue and secondary_dialogs.insert(Subtitle:now('secondary')) then
        self.menu:update()
    end
end

local function start_appending()
    append_dialogue = true
    append_primary_sub()
    append_secondary_sub()
end

local function handle_primary_sub()
    append_primary_sub()
    copy_primary_sub()
end

local function handle_secondary_sub()
    append_secondary_sub()
end

------------------------------------------------------------
-- public

self.copy_to_clipboard = function(_, text)
    if not h.is_empty(text) then
        platform.copy_to_clipboard(self.clipboard_prepare(text))
    end
end

self.clipboard_prepare = function(text)
    text = self.config.clipboard_trim_enabled and h.trim(text) or h.remove_newlines(text)
    text = self.maybe_remove_all_spaces(text)
    return text
end

self.maybe_remove_all_spaces = function(str)
    if self.config.nuke_spaces == true and h.contains_non_latin_letters(str) then
        return h.remove_all_spaces(str)
    else
        return str
    end
end

self.copy_current_to_clipboard = function()
    self.copy_to_clipboard("copy-on-demand", mp.get_property("sub-text"))
end

self.user_altered = function()
    --- Return true if the user manually set at least start or end.
    return user_timings.is_set('start') or user_timings.is_set('end')
end

self.get_timing = function(position)
    if user_timings.is_set(position) then
        return user_timings.get(position)
    elseif not dialogs.is_empty() then
        return dialogs.get_time(position)
    end
    return -1
end

self.collect = function()
    --- Return all recorded subtitle lines as one subtitle object.
    --- The caller has to call subs_observer.clear() afterwards.
    if dialogs.is_empty() then
        dialogs.insert(Subtitle:now())
    end
    if secondary_dialogs.is_empty() then
        secondary_dialogs.insert(Subtitle:now('secondary'))
    end
    return Subtitle:new {
        ['text'] = dialogs.get_text(),
        ['secondary'] = secondary_dialogs.get_text(),
        ['start'] = self.get_timing('start'),
        ['end'] = self.get_timing('end'),
    }
end

self.set_manual_timing = function(position)
    user_timings.set(position, mp.get_property_number('time-pos'))
    h.notify(h.capitalize_first_letter(position) .. " time has been set.")
    start_appending()
end

self.set_manual_timing_to_sub = function(position)
    local sub = Subtitle:now()
    if sub then
        user_timings.set(position, sub[position])
        h.notify(h.capitalize_first_letter(position) .. " time has been set.")
        start_appending()
    else
        h.notify("There's no visible subtitle.", "info", 2)
    end
end

self.set_to_current_sub = function()
    self.clear()
    if Subtitle:now() then
        start_appending()
        h.notify("Timings have been set to the current sub.", "info", 2)
    else
        h.notify("There's no visible subtitle.", "info", 2)
    end
end

self.clear = function()
    append_dialogue = false
    dialogs = sub_list.new()
    secondary_dialogs = sub_list.new()
    user_timings = timings.new()
end

self.clear_and_notify = function()
    --- Clear then notify the user.
    --- Called by the OSD menu when the user presses a button to drop recorded subtitles.
    self.clear()
    h.notify("Timings have been reset.", "info", 2)
end

self.is_appending = function()
    return append_dialogue
end

self.recorded_subs = function()
    return dialogs.get_subs_list()
end

self.autocopy_status_str = function()
    return autoclip_enabled and 'enabled' or 'disabled'
end

self.toggle_autocopy = function()
    autoclip_enabled = not autoclip_enabled
    if autoclip_enabled then
        copy_primary_sub()
    end
    h.notify(string.format("Clipboard autocopy has been %s.", self.autocopy_status_str()))
end

self.init = function(menu, config)
    self.menu = menu
    self.config = config

    -- The autoclip state is copied as a local value
    -- to prevent it from being reset when the user reloads the config file.
    autoclip_enabled = self.config.autoclip

    mp.observe_property("sub-text", "string", handle_primary_sub)
    mp.observe_property("secondary-sub-text", "string", handle_secondary_sub)
end

return self
