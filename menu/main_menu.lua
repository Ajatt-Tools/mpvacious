--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Main Menu for mpvacious
]]

local OSD = require('menu.osd_styler')
local Menu = require('menu.menu')
local h = require('helpers')

-- create MainMenu object by extending Menu class
local MainMenu = Menu:new()
MainMenu.subs2srs = nil -- pass subs2srs object to main menu

-- Derived class method new
function MainMenu:new(o)
    o = o or Menu:new(o)
    setmetatable(o, self)
    self.__index = self
    return o
end

function MainMenu:open()
    if h.is_empty(self.subs2srs) then
        error("subs2srs object is not set.")
    end
    return Menu.open(self)
end

-- Menu bindings work only when the menu is open.
function MainMenu:make_key_bindings()
    if h.is_empty(self.subs2srs) then
        error("subs2srs object is not set.")
    end
    return {
        -- change hint state
        { key = 'i', fn = self:with_update { self.subs2srs.next_hint_page } },

        -- change profile
        { key = 'p', fn = self:with_update { self.subs2srs.load_next_profile }, text = "Switch to next profile" },

        -- subs selector
        { key = 'v', fn = self:with_update { self.subs2srs.subs_menu_open }, text = "Open subtitle selection menu" },

        -- subs observer
        { key = 'S', fn = self:with_update { self.subs2srs.subs_observer.set_manual_timing_to_sub, 'start' }, text = "Set start time to current subtitle" },
        { key = 'E', fn = self:with_update { self.subs2srs.subs_observer.set_manual_timing_to_sub, 'end' }, text = "Set end time to current subtitle" },
        { key = 's', fn = self:with_update { self.subs2srs.subs_observer.set_manual_timing, 'start' }, text = "Set start time to current position" },
        { key = 'e', fn = self:with_update { self.subs2srs.subs_observer.set_manual_timing, 'end' }, text = "Set end time to current position" },
        { key = 'c', fn = self:with_update { self.subs2srs.subs_observer.set_to_current_sub }, text = "Set timings to the current sub" },
        { key = 'r', fn = self:with_update { self.subs2srs.subs_observer.clear_and_notify }, text = "Reset timings" },
        { key = 't', fn = self:with_update { self.subs2srs.subs_observer.toggle_autocopy }, text = "Toggle autocopy" },
        { key = 'T', fn = self:with_update { self.subs2srs.subs_observer.next_autoclip_method }, text = "Switch to the next autocopy method" },

        -- note exporter
        { key = 'g', fn = self:with_update { self.subs2srs.note_exporter.export_to_anki, true }, text = "GUI export" },
        { key = 'n', fn = self:with_update { self.subs2srs.note_exporter.export_to_anki, false }, text = "Export note" },
        { key = 'b', fn = self:with_update { self.subs2srs.note_exporter.update_selected_note, false }, text = "Update the selected note" },
        { key = 'B', fn = self:with_update { self.subs2srs.note_exporter.update_selected_note, true }, text = "Overwrite the selected note" },
        { key = 'm', fn = self:with_update { self.subs2srs.note_exporter.update_last_note, false }, text = "Update the last added note" },
        { key = 'M', fn = self:with_update { self.subs2srs.note_exporter.update_last_note, true }, text = "Overwrite the last added note" },

        -- quick card creation
        { key = 'f', fn = self:with_update { self.subs2srs.quick_creation_opts.increment_cards, self.subs2srs.quick_creation_opts }, text = "Increment # cards to update" },
        { key = 'F', fn = self:with_update { self.subs2srs.quick_creation_opts.decrement_cards, self.subs2srs.quick_creation_opts }, text = "Decrement # cards to update" },

        -- Close
        { key = 'ESC', fn = self:with_update { self.close, self }, text = "Close" },
        { key = 'q', fn = self:with_update { self.close, self }, text = "Close" },
    }
end

function MainMenu:print_legend()
    error("not implemented.")
end

function MainMenu:make_osd()
    if h.is_empty(self.subs2srs.cfg_mgr) then
        error("config manager is not set.")
    end
    local osd = OSD:new()
    osd:new_layer()
       :border(self.subs2srs.consts.border_size)
       :fsize(self.subs2srs.cfg_mgr.query("menu_font_size"))
       :font(self.subs2srs.cfg_mgr.query("menu_font_name"))
       :pos(self.subs2srs.consts.start_x, self.subs2srs.consts.start_y)
    self:print_legend(osd)
    return osd
end

return MainMenu
