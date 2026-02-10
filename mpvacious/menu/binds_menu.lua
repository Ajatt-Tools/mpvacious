--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Binds Menu for mpvacious
]]

local MainMenu = require('menu.main_menu')
local h = require('helpers')

-- create BindsMenu object by extending MainMenu class
local BindsMenu = MainMenu:new()

-- Derived class method new
function BindsMenu:new(o)
    o = o or MainMenu:new(o)
    setmetatable(o, self)
    self.__index = self
    return o
end

function BindsMenu:_make_selection_bindings()
    return {
        -- commit
        { key = 'MBTN_LEFT', fn = self:with_update { self.trigger_selected_item, self } },
        { key = 'ENTER', fn = self:with_update { self.trigger_selected_item, self } },
        -- vim keys
        { key = 'k', fn = self:with_update { self.change_selection, self, -1 } },
        { key = 'j', fn = self:with_update { self.change_selection, self, 1 } },
        { key = 'h', fn = self:with_update { h.noop } },
        { key = 'l', fn = self:with_update { self.trigger_selected_item, self } },
        -- arrows
        { key = 'up', fn = self:with_update { self.change_selection, self, -1 } },
        { key = 'down', fn = self:with_update { self.change_selection, self, 1 } },
        { key = 'left', fn = self:with_update { h.noop } },
        { key = 'right', fn = self:with_update { self.trigger_selected_item, self } },
        -- mouse
        { key = 'WHEEL_UP', fn = self:with_update { self.change_selection, self, -1 } },
        { key = 'WHEEL_DOWN', fn = self:with_update { self.change_selection, self, 1 } },
    }
end

function BindsMenu:trigger_selected_item()
    if h.is_empty(self.bindings_switch) then
        error("bindings_switch is not set")
    end
    return self.bindings_switch.get().fn()
end

function BindsMenu:change_selection(step)
    if h.is_empty(self.bindings_switch) then
        error("bindings_switch is not set")
    end
    self.bindings_switch.change_menu_item(step)
end

function BindsMenu:make_key_bindings()
    return h.join_lists(
            MainMenu.make_key_bindings(self),
            self:_make_selection_bindings(),
            {
                { key = 'a', fn = self:with_update { h.noop } }, -- occupy 'a' to prevent surprises
            }
    )
end

function BindsMenu:print_controls(osd)
    osd:submenu('Controls'):newline()
    osd:tab():item('j/↓/wheel: '):text('down'):newline()
    osd:tab():item('k/↑/wheel: '):text('up'):newline()
    osd:tab():item('l/ENTER/mouse left: '):text('activate'):newline()
    osd:tab():item('q/ESC: '):text('finish'):newline()
end

return BindsMenu
