--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

Requirements:
* mpv >= 0.32.0
* AnkiConnect
* curl
* xclip (when running X11)
* wl-copy (when running Wayland)

Usage:
1. Change `config` according to your needs
* Config path: ~/.config/mpv/script-opts/subs2srs.conf
* Config file isn't created automatically.

2. Open a video

3. Use key bindings to manipulate the script
* Open mpvacious menu - `a`
* Create a note from the current subtitle line - `Ctrl + n`

For complete usage guide, see <https://github.com/Ajatt-Tools/mpvacious/blob/master/README.md>
]]

local mp = require('mp')
local OSD = require('menu.osd_styler')
local make_cfg_mgr = require('config.cfg_mgr')
local encoder = require('encoder.encoder')
local h = require('helpers')
local Menu = require('menu.menu')
local MainMenu = require('menu.main_menu')
local BindsMenu = require('menu.binds_menu')
local make_ankiconnect = require('anki.ankiconnect')
local switch = require('utils.switch')
local play_control = require('utils.play_control')
local secondary_sid = require('subtitles.secondary_sid')
local platform = require('platform.init')
local forvo = require('utils.forvo')
local subs_observer = require('subtitles.observer')
local codec_support = require('encoder.codec_support')
local make_new_note_checker = require('anki.new_note_checker')
local make_note_exporter = require('anki.note_exporter')
local Subtitle = require('subtitles.subtitle')
local make_release_checker = require('utils.release_checker')

local quick_creation_opts = {
    _n_lines = nil,
    _n_cards = 1,
    set_cards = function(self, n)
        self._n_cards = math.max(0, n)
    end,
    set_lines = function(self, n)
        self._n_lines = math.max(0, n)
    end,
    get_cards = function(self)
        return self._n_cards
    end,
    get_lines = function(self)
        return self._n_lines
    end,
    increment_cards = function(self)
        self:set_cards(self._n_cards + 1)
    end,
    decrement_cards = function(self)
        self:set_cards(self._n_cards - 1)
    end,
    clear_options = function(self)
        self._n_lines = nil
        self._n_cards = 1
    end
}

local menu_consts = {
    border_size = 2.5,
    start_y = 55,
    start_x = 5,
    start_x_second_pane = 640,
    max_shown_line_length = 30,
}

------------------------------------------------------------
-- utility functions

local new_note_checker = make_new_note_checker.new()
local note_exporter = make_note_exporter.new()
local cfg_mgr = make_cfg_mgr.new()
local ankiconnect = make_ankiconnect.new()
local release_checker = make_release_checker.new()

local function _run(params)
    return function()
        local status, err = pcall(h.unpack(params))
        if not status then
            h.notify(err, "error", 5)
        end
    end
end

local function escape_for_osd(str)
    str = h.trim(str)
    str = str:gsub('[%[%]{}]', '')
    return h.str_limit(str, menu_consts.max_shown_line_length)
end

local function ensure_deck()
    if cfg_mgr.query("create_deck") == true then
        ankiconnect.create_deck(cfg_mgr.query("deck_name"))
    end
end

local function switch_to_osd(bindings_switch, osd)
    --- Use osd to print menu bindings contained within the switch.
    if h.is_empty(bindings_switch) or h.is_empty(osd) then
        error("invalid parameters passed.")
    end
    local function adjust_shift(binding)
        local parts = {}
        for part in string.gmatch(binding, "[^+]+") do
            if #part == 1 and not h.is_lower(part) then
                table.insert(parts, "Shift")
            end
            table.insert(parts, part)
        end
        return table.concat(parts, "+")
    end

    for _, item in ipairs(bindings_switch.adjacent_items(5, 5)) do
        local key_text = string.format("%s: ", adjust_shift(item.item.key))
        if item.idx == bindings_switch.get_index() then
            osd:tab():blue(key_text):blue(item.item.text):newline()
        else
            osd:tab():item(key_text):text(item.item.text):newline()
        end
    end
    return osd
end

local function make_menu_controller()
    --- A menu object can request a seat, which causes a previous menu to be kicked out.
    local private = {}
    local public = {}

    function public.request_seat(menu_instance)
        if not h.is_empty(private.open_instance) and private.open_instance.active and menu_instance ~= private.open_instance then
            mp.msg.info("kicked from seat: " .. private.open_instance.name)
            private.open_instance:close()
        end
        private.open_instance = menu_instance
        mp.msg.info("new seat: " .. private.open_instance.name)
    end

    return public
end

------------------------------------------------------------
-- main menu

local menu, quick_menu, quick_menu_card, subs_menu, binds_menu, global_binds_menu
local menu_controller = make_menu_controller()
local hints_switch = switch.new { 'shown', 'binds_menu', 'global', 'hidden' }

local self = {}
self.consts = menu_consts
self.subs_observer = subs_observer
self.note_exporter = note_exporter
self.quick_creation_opts = quick_creation_opts
self.cfg_mgr = cfg_mgr

function self.next_hint_page()
    local hint_type_to_menu = {
        ['shown'] = menu,
        ['binds_menu'] = binds_menu,
        ['global'] = global_binds_menu,
        ['hidden'] = menu,
    }
    local prev_state = hints_switch.get()
    local new_state = hints_switch.bump()
    if hint_type_to_menu[new_state] ~= hint_type_to_menu[prev_state] then
        hint_type_to_menu[new_state]:open()
    end
end

function self.subs_menu_open()
    subs_menu:show_latest_subs_reset()
    subs_menu:open()
end

function self.load_next_profile()
    cfg_mgr.next_profile()
    ensure_deck()
    h.notify("Loaded profile " .. cfg_mgr.profiles().active)
end

local function open_advanced_menu()
    hints_switch.set_index(1) -- switch current state to "shown"
    menu:open()
end

local function quick_menu_open()
    quick_menu:open()
end

local function quick_menu_card_open()
    quick_menu_card:open()
end

local function make_latest_subtitle_list()
    local primary_subs, secondary_subs = subs_observer.all_subs_until_now()
    local all_subs = h.join_two_sorted_lists(primary_subs, secondary_subs)
    local subs_selector = switch.new(all_subs)

    local dummy_now = Subtitle:new { ['text'] = "", ['start'] = mp.get_property_number("time-pos", 0), ['end'] = mp.get_property_number("time-pos", 0) }
    subs_selector.set_index(h.find_insertion_point(all_subs, dummy_now) - 1)
    return subs_selector
end

local function close_subtitle_selection_menu()
    local chosen_subs = {}
    for i, sub in ipairs(subs_menu.subs_selector.all_items()) do
        if subs_menu.chosen_subs[i] then
            table.insert(chosen_subs, sub)
        end
    end
    subs_observer.import_subs(chosen_subs)
    subs_menu.subs_selector = nil
    subs_menu.chosen_subs = {}
    subs_menu:close()
    menu:open()
end

-- menu

menu = MainMenu:new { subs2srs = self, menu_controller = menu_controller, name = "main menu" }

function menu:open_release_page()
    if release_checker.release_page_url() then
        return mp.commandv('run', platform.open_utility, release_checker.release_page_url())
    end
end

function menu:make_key_bindings()
    return h.join_lists(
            MainMenu.make_key_bindings(self),
            { key = 'o', fn = _run { menu.open_release_page, menu } }
    )
end

function menu:print_legend(osd)
    local state = hints_switch.get()
    if state == 'hidden' then
        -- Menu bindings are active but hidden
        osd:item('i'):newline()
    else
        self:print_header(osd)
        self:warn_formats(osd)
        self:warn_clipboard(osd)
        self:warn_updates(osd)
        osd:italics("Press "):item('i'):italics(" to show menu bindings."):newline()
    end
    self:print_selection(osd)
end

function menu:print_header(osd)
    osd:submenu('mpvacious options'):newline()
    osd:item('Timings: '):text(h.human_readable_time(subs_observer.get_timing('start')))
    osd:item(' to '):text(h.human_readable_time(subs_observer.get_timing('end'))):newline()
    osd:item('Autocopy: '):text(subs_observer.autocopy_is_enabled_str()):item(" ["):text(subs_observer.autocopy_current_method_str()):item("]"):newline()
    osd:item('Active profile: '):text(cfg_mgr.profiles().active):item(" ["):text(cfg_mgr.query("deck_name")):item("]"):newline()
    osd:item('# cards: '):text(quick_creation_opts:get_cards()):newline()
end

function menu:warn_formats(osd)
    local prog_name = (cfg_mgr.query("use_ffmpeg") and "ffmpeg" or "mpv")
    for type, codecs in pairs(codec_support[prog_name .. "_support"]) do
        -- type is one of snapshot, audio
        for codec, supported in pairs(codecs) do
            if not supported and cfg_mgr.query(type .. '_codec') == codec then
                osd:red('Warning: '):newline()
                osd:tab():text(string.format("your version of %s does not support %s.", prog_name, codec)):newline()
                osd:tab():text(string.format("mpvacious won't be able to create %s files.", type)):newline()
            end
        end
    end
end

function menu:warn_clipboard(osd)
    if subs_observer.autocopy_current_method() == "clipboard" and platform.healthy == false then
        osd:red('Warning: '):text(string.format("%s is not installed.", platform.clip_util)):newline()
    end
end

function menu:warn_updates(osd)
    if release_checker.has_update() then
        osd:red('Note: '):text("new version available: " .. release_checker.get_latest_version()):newline()
        osd:italics("Press "):item('o'):italics(" to open release page."):newline()
    end
end

function menu:print_selection(osd)
    if (subs_observer.is_appending() or subs_observer.has_recorded_dialogs()) and cfg_mgr.query("show_selected_text") then
        osd:start_line():pos(menu_consts.start_x_second_pane, menu_consts.start_y)
        osd:submenu("Primary text"):newline()
        for _, s in ipairs(subs_observer.recorded_subs()) do
            osd:text(escape_for_osd(s['text'])):newline()
        end
        if not h.is_empty(cfg_mgr.query("secondary_field")) then
            -- If the user wants to add secondary subs to Anki,
            -- it's okay to print them on the screen.
            osd:submenu("Secondary text"):newline()
            for _, s in ipairs(subs_observer.recorded_secondary_subs()) do
                osd:text(escape_for_osd(s['text'])):newline()
            end
        end
    end
end

-- Binds menu

local function bindings_has_text(item)
    return not h.is_empty(item.text)
end

binds_menu = BindsMenu:new { subs2srs = self, menu_controller = menu_controller, name = "menu binds menu" }
-- only bindings with text are shown to the user.
binds_menu.bindings_switch = switch.new(h.filter(binds_menu:make_key_bindings(), bindings_has_text))

function binds_menu:print_legend(osd)
    osd:submenu('Menu bindings ⇅'):newline()
    switch_to_osd(self.bindings_switch, osd)
    self:print_controls(osd)
    osd:italics("Press "):item('i'):italics(" to show global bindings."):newline()
end

-- Global bindings

global_binds_menu = BindsMenu:new { subs2srs = self, menu_controller = menu_controller, name = "global binds menu" }

-- global bindings work when the menu is closed.
global_binds_menu.bindings_switch = switch.new {
    { key = "a", name = "mpvacious-menu-open", fn = _run { open_advanced_menu }, text = "Open advanced menu", force = true },
    { key = "g", name = "mpvacious-quick-card-menu-open", fn = _run { quick_menu_open }, text = "Open quick menu" },
    { key = "ctrl+t", name = "mpvacious-autocopy-toggle", fn = subs_observer.toggle_autocopy, text = "Toggle autocopy" },
    { key = "Ctrl+n", name = "mpvacious-export-note", fn = menu:with_update { note_exporter.export_to_anki, false }, text = "Add a new note", force = true },

    -- Clipboard
    { key = "Ctrl+c", name = "mpvacious-copy-sub-to-clipboard", fn = subs_observer.copy_current_primary_to_clipboard, text = "Copy current subtitle to clipboard", force = true },
    { key = "Ctrl+C", name = "mpvacious-copy-secondary-sub-to-clipboard", fn = subs_observer.copy_current_secondary_to_clipboard, text = "Copy current secondary subtitle to clipboard" },

    -- Secondary subtitles
    { key = "Ctrl+j", name = "mpvacious-secondary-sid-next", fn = secondary_sid.select_next, text = "Selected next secondary sid" },
    { key = "Ctrl+k", name = "mpvacious-secondary-sid-prev", fn = secondary_sid.select_previous, text = "Selected previous secondary sid" },
    { key = "Ctrl+v", name = "mpvacious-secondary-sid-toggle", fn = secondary_sid.change_visibility, text = "Change secondary sid visibility" },

    { key = "Alt+g", name = "mpvacious-quick-card-sel-menu-open", fn = _run { quick_menu_card_open }, text = "Open quick card menu" },
    { key = "Ctrl+g", name = "mpvacious-animated-snapshot-toggle", fn = encoder.snapshot.toggle_animation, text = "Toggle animated snapshots" },

    -- Note updating
    { key = "Ctrl+b", name = "mpvacious-update-selected-note", fn = menu:with_update { note_exporter.update_selected_note, false }, text = "Update the selected note" },
    { key = "Ctrl+B", name = "mpvacious-overwrite-selected-note", fn = menu:with_update { note_exporter.update_selected_note, true }, text = "Overwrite the selected note" },
    { key = "Ctrl+m", name = "mpvacious-update-last-note", fn = menu:with_update { note_exporter.update_last_note, false }, text = "Update the last added note" },
    { key = "Ctrl+M", name = "mpvacious-overwrite-last-note", fn = menu:with_update { note_exporter.update_last_note, true }, text = "Overwrite the last added note" },

    -- Vim-like seeking between subtitle lines
    { key = "H", name = "mpvacious-sub-seek-back", fn = _run { play_control.sub_seek, 'backward' }, text = "Seek to the previous subtitle" },
    { key = "L", name = "mpvacious-sub-seek-forward", fn = _run { play_control.sub_seek, 'forward' }, text = "Seek to the next subtitle" },
    { key = "Ctrl+h", name = "mpvacious-sub-rewind", fn = _run { play_control.sub_rewind }, text = "Seek to the start of the line" },
    { key = "Ctrl+H", name = "mpvacious-sub-replay", fn = _run { play_control.play_till_sub_end }, text = "Replay current subtitle" },
    { key = "Alt+h", name = "mpvacious-sub-seek-back-pause", fn = _run { play_control.sub_seek, 'backward', true }, text = "Seek to the previous subtitle and pause" },
    { key = "Ctrl+L", name = "mpvacious-sub-play-up-to-next", fn = _run { play_control.play_till_next_sub_end }, text = "Play until the next subtitle's end" },
    { key = "Alt+l", name = "mpvacious-sub-seek-forward-pause", fn = _run { play_control.sub_seek, 'forward', true }, text = "Seek to the next subtitle and pause" },
}

function global_binds_menu:print_legend(osd)
    osd:submenu('Global bindings ⇅'):newline()
    switch_to_osd(self.bindings_switch, osd)
    self:print_controls(osd)
    osd:italics("Press "):item('i'):italics(" to hide mpvacious options."):newline()
end

function global_binds_menu:add_global_bindings()
    for _, val in pairs(self.bindings_switch.all_items()) do
        if val.force then
            mp.add_forced_key_binding(val.key, val.name, val.fn)
        else
            mp.add_key_binding(val.key, val.name, val.fn)
        end
    end
end

------------------------------------------------------------
-- select subs

subs_menu = Menu:new {
    cfg = menu_consts,
    subs_selector = nil,
    chosen_subs = {}, -- store indices
    menu_controller = menu_controller,
    name = "subs selector menu",
}

function subs_menu:select_current_sub()
    self.chosen_subs[self.subs_selector.get_index()] = not self.chosen_subs[self.subs_selector.get_index()]
end

function subs_menu:show_latest_subs_reset()
    mp.set_property("pause", "yes")
    subs_menu.subs_selector = make_latest_subtitle_list()
    subs_menu.chosen_subs = {}
end

function subs_menu:change_menu_item(step)
    return self.subs_selector.change_menu_item(step)
end

function subs_menu:make_key_bindings()
    return {
        { key = 'a', fn = self:with_update { h.noop } }, -- occupy 'a' to prevent surprises
        { key = 'g', fn = self:with_update { h.noop } },
        { key = 'v', fn = self:with_update { h.noop } },
        { key = 'r', fn = self:with_update { self.show_latest_subs_reset, self } },
        { key = 'ESC', fn = self:with_update { close_subtitle_selection_menu } },
        { key = 'q', fn = self:with_update { close_subtitle_selection_menu } },
        -- mark current sub for export
        { key = 'ENTER', fn = self:with_update { self.select_current_sub, self } },
        { key = 'SPACE', fn = self:with_update { self.select_current_sub, self } },
        -- vim keys
        { key = 'k', fn = self:with_update { self.change_menu_item, self, -1 } },
        { key = 'j', fn = self:with_update { self.change_menu_item, self, 1 } },
        { key = 'h', fn = self:with_update { close_subtitle_selection_menu } },
        { key = 'l', fn = self:with_update { self.select_current_sub, self } },
        -- arrows
        { key = 'up', fn = self:with_update { self.change_menu_item, self, -1 } },
        { key = 'down', fn = self:with_update { self.change_menu_item, self, 1 } },
        { key = 'left', fn = self:with_update { close_subtitle_selection_menu } },
        { key = 'right', fn = self:with_update { self.select_current_sub, self } },
        -- mouse
        { key = 'MBTN_LEFT', fn = self:with_update { self.select_current_sub, self } },
        { key = 'WHEEL_UP', fn = self:with_update { self.change_menu_item, self, -1 } },
        { key = 'WHEEL_DOWN', fn = self:with_update { self.change_menu_item, self, 1 } },
    }
end

function subs_menu:print_subs_selector(osd)
    osd:submenu('Select subtitles ⇅'):newline()
    for _, item in ipairs(subs_menu.subs_selector.adjacent_items(5, 5)) do
        local checkbox = subs_menu.chosen_subs[item.idx] and "[x]" or "[ ]"
        if item.idx == subs_menu.subs_selector.get_index() then
            osd:tab():blue(checkbox):text(' <'):blue(escape_for_osd(item.item.text)):text('>'):newline()
        else
            osd:tab():item(checkbox):text(' <'):text(escape_for_osd(item.item.text)):text('>'):newline()
        end
    end
    osd:submenu('Controls'):newline()
    osd:tab():item('j/↓/wheel: '):text('down'):newline()
    osd:tab():item('k/↑/wheel: '):text('up'):newline()
    osd:tab():item('l/ENTER/mouse left: '):text('toggle selection'):newline()
    osd:tab():item('r: '):text('reset selection'):newline()
    osd:tab():item('q/ESC: '):text('finish'):newline()
end

function subs_menu:make_osd()
    local osd = OSD:new()
    osd:new_layer()
       :border(self.cfg.border_size)
       :fsize(cfg_mgr.query("menu_font_size"))
       :font(cfg_mgr.query("menu_font_name"))
       :pos(self.cfg.start_x, self.cfg.start_y)
    self:print_subs_selector(osd)
    return osd
end

------------------------------------------------------------
-- quick_menu line selection

local choose_cards = function(i)
    quick_creation_opts:set_cards(i)
    quick_menu_card:close()
    quick_menu:open()
end
local choose_lines = function(i)
    quick_creation_opts:set_lines(i)
    note_exporter.update_last_note(true)
    quick_menu:close()
end

quick_menu = Menu:new { menu_controller = menu_controller, name = "quick menu" }
quick_menu.keybindings = {}
for i = 1, 9 do
    table.insert(quick_menu.keybindings, { key = tostring(i), fn = function()
        choose_lines(i)
    end })
end
table.insert(quick_menu.keybindings, { key = 'g', fn = function()
    choose_lines(1)
end })
table.insert(quick_menu.keybindings, { key = 'ESC', fn = function()
    quick_menu:close()
end })
table.insert(quick_menu.keybindings, { key = 'q', fn = function()
    quick_menu:close()
end })
function quick_menu:print_header(osd)
    osd:submenu('quick card creation: line selection'):newline()
    osd:item('# lines: '):text('Enter 1-9'):newline()
end
function quick_menu:print_legend(osd)
    osd:new_layer()
       :fsize(cfg_mgr.query("menu_font_size"))
       :font(cfg_mgr.query("menu_font_name"))
       :align(4)
    self:print_header(osd)
end
function quick_menu:make_osd()
    local osd = OSD:new()
    self:print_legend(osd)
    return osd
end

-- quick_menu card selection
quick_menu_card = Menu:new { menu_controller = menu_controller, name = "quick card menu" }
quick_menu_card.keybindings = {}
for i = 1, 9 do
    table.insert(quick_menu_card.keybindings, { key = tostring(i), fn = function()
        choose_cards(i)
    end })
end
table.insert(quick_menu_card.keybindings, { key = 'ESC', fn = _run { quick_menu_card.close, quick_menu_card } })
table.insert(quick_menu_card.keybindings, { key = 'q', fn = _run { quick_menu_card.close, quick_menu_card } })
function quick_menu_card:print_header(osd)
    osd:submenu('quick card creation: card selection'):newline()
    osd:item('# cards: '):text('Enter 1-9'):newline()
end
function quick_menu_card:print_legend(osd)
    osd:new_layer()
       :fsize(cfg_mgr.query("menu_font_size"))
       :font(cfg_mgr.query("menu_font_name"))
       :align(4)
    self:print_header(osd)
end
function quick_menu_card:make_osd()
    local osd = OSD:new()
    self:print_legend(osd)
    return osd
end

------------------------------------------------------------
-- tests

local function run_tests()
    h.run_tests()
    local new_note = {
        SentKanji = "それは…分からんよ",
        SentAudio = "[sound:s01e13_02m25s010ms_02m27s640ms.ogg]",
        SentEng = "Well...",
        Image = '<img alt="snapshot" src="s01e13_02m25s561ms.avif">'
    }
    local old_note = {
        SentAudio = "[sound:s01e13_02m21s340ms_02m24s140ms.ogg]",
        Image = '<img alt="snapshot" src="s01e13_02m22s225ms.avif">',
        VocabAudio = "",
        Notes = "",
        VocabDef = "",
        SentKanji = "勝ちって何に？",
        SentEng = "What would we win, exactly?",
    }
    local result = note_exporter.join_fields(new_note, old_note)
    local expected = {
        SentKanji = "勝ちって何に？<br>それは…分からんよ",
        SentAudio = "[sound:s01e13_02m21s340ms_02m24s140ms.ogg]<br>[sound:s01e13_02m25s010ms_02m27s640ms.ogg]",
        SentEng = "What would we win, exactly?<br>Well...",
        Image = '<img alt="snapshot" src="s01e13_02m22s225ms.avif"><br><img alt="snapshot" src="s01e13_02m25s561ms.avif">',
        Notes = "",
    }
    h.assert_equals(result, expected)
end

local function pcall_tests()
    if os.getenv("MPVACIOUS_TEST") == "TRUE" then
        -- at this point, other tests in submodules should have been finished.
        mp.msg.warn("RUNNING TESTS")
        local success, err = pcall(run_tests)
        if not success then
            mp.msg.error("TESTS FAILED")
            mp.msg.error(err)
        else
            mp.msg.warn("TESTS PASSED")
        end
        mp.commandv("quit")
    end
end

------------------------------------------------------------
-- main

local main = (function()
    local main_executed = false
    return function()
        if main_executed then
            subs_observer.clear_all_dialogs()
            return
        else
            main_executed = true
        end
        cfg_mgr.init()
        ankiconnect.init(cfg_mgr)
        forvo.init(cfg_mgr)
        encoder.init(cfg_mgr)
        secondary_sid.init(cfg_mgr)
        ensure_deck()
        subs_observer.init(menu, cfg_mgr)
        note_exporter.init(ankiconnect, quick_creation_opts, subs_observer, encoder, forvo, cfg_mgr)
        new_note_checker.init(ankiconnect, menu:with_update { note_exporter.update_notes }, cfg_mgr)
        pcall_tests()

        global_binds_menu:add_global_bindings()
        mp.msg.warn("Press 'a' to open the mpvacious menu.")
        release_checker.init(cfg_mgr)

        -- start timer
        new_note_checker.start_timer()
    end
end)()

mp.register_event("file-loaded", main)
