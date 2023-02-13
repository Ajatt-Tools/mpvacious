--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

This module automatically finds and sets secondary sid if it's not already set.
Secondary sid will be shown when mouse is moved to the top part of the mpv window.
]]

local mp = require('mp')
local h = require('helpers')

local self = {
    visibility = 'auto',
    visibility_states = { auto = true, never = true, always = true, },
}

local function is_accepted_language(sub_lang)
    for _, accepted_lang in pairs(self.accepted_languages) do
        if accepted_lang == sub_lang then
            return true
        end
    end
    return false
end

local function is_selected_language(track, active_track)
    return track.id == mp.get_property_native('sid') or (active_track and active_track.lang == track.lang)
end

local function is_full(track)
    return h.str_contains(track.title, 'full')
end

local function is_garbage(track)
    for _, keyword in pairs({ 'song', 'sign', 'caption', 'commentary' }) do
        if h.str_contains(track.title, keyword) then
            return true
        end
    end
    return false
end

local function prioritize_full_subs(tracks_list)
    return table.sort(tracks_list, function(first, second)
        return (is_full(first) and not is_full(second)) or (is_garbage(second) and not is_garbage(first))
    end)
end

local function find_best_secondary_sid()
    local active_track = h.get_active_track('sub')
    local sub_tracks = h.get_loaded_tracks('sub')
    prioritize_full_subs(sub_tracks)
    for _, track in ipairs(sub_tracks) do
        if is_accepted_language(track.lang) and not is_selected_language(track, active_track) then
            return track.id
        end
    end
    return nil
end

local function window_height()
    return mp.get_property_native('osd-dimensions/h')
end

local function get_accepted_sub_langs()
    local languages = {}
    for lang in self.config.secondary_sub_lang:gmatch('[a-z-]+') do
        table.insert(languages, lang)
    end
    return languages
end

local function on_mouse_move(_, state)
    -- state = {x=int,y=int, hover=true|false, }
    if self.visibility == 'auto' and state ~= nil then
        mp.set_property_bool(
                'secondary-sub-visibility',
                state.hover and (state.y / window_height()) < self.config.secondary_sub_area
        )
    end
end

local function on_file_loaded()
    -- If secondary sid is not already set, try to find and set it.
    local secondary_sid = mp.get_property_native('secondary-sid')
    if secondary_sid == false then
        secondary_sid = find_best_secondary_sid()
        if secondary_sid ~= nil then
            mp.set_property_native('secondary-sid', secondary_sid)
        end
    end
end

local function update_visibility()
    mp.set_property_bool('secondary-sub-visibility', self.visibility == 'always')
end

local function init(config)
    self.config = config
    self.visibility = config.secondary_sub_visibility
    self.accepted_languages = get_accepted_sub_langs()
    mp.register_event('file-loaded', on_file_loaded)
    if config.secondary_sub_area > 0 then
        mp.observe_property('mouse-pos', 'native', on_mouse_move)
    end
    update_visibility()
end

local function change_visibility()
    while true do
        self.visibility = next(self.visibility_states, self.visibility)
        if self.visibility ~= nil then
            break
        end
    end
    update_visibility()
    h.notify("Secondary sid visibility: " .. self.visibility)
end

local function switch_secondary_sid(direction)
    local primary_sid = mp.get_property_native('sid')
    local secondary_sid = mp.get_property_native('secondary-sid')

    local subtitle_tracks = h.filter(h.get_loaded_tracks('sub'), function(track)
        return track.id ~= secondary_sid and track.id ~= primary_sid
    end)
    table.sort(subtitle_tracks, function(track1, track2) return track1.id < track2.id end)

    local new_secondary_sub = { id = false, title = "removed" }

    if direction == 'prev' then
        local previous_tracks = h.filter(subtitle_tracks, function(track)
            return secondary_sid == false or track.id < secondary_sid
        end)
        if #previous_tracks > 0 then
            new_secondary_sub = previous_tracks[#previous_tracks]
        end
    elseif direction == 'next' then
        local next_tracks = h.filter(subtitle_tracks, function(track)
            return secondary_sid == false or track.id > secondary_sid
        end)
        if #next_tracks > 0 then
            new_secondary_sub = next_tracks[1]
        end
    end

    mp.set_property_native('secondary-sid', new_secondary_sub.id)
    if new_secondary_sub.id == false then
        h.notify("Removed secondary sid.")
    else
        h.notify(string.format(
                "Secondary #%d: %s (%s)",
                new_secondary_sub.id,
                new_secondary_sub.title or "No title",
                new_secondary_sub.lang or "Unknown"
        ))
    end
end

return {
    init = init,
    change_visibility = change_visibility,
    select_previous = function() switch_secondary_sid('prev') end,
    select_next = function() switch_secondary_sid('next') end,
}
