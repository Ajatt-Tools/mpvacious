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
    -- for missing keys compares nil to true
    return self.accepted_languages[sub_lang] == true
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
    for lang in self.config.secondary_sub_lang:gmatch('[a-zA-Z-]+') do
        languages[lang] = true
    end
    return languages
end

local function on_mouse_move(_, state)
    -- state = {x=int,y=int, hover=true|false, }
    if mp.get_property_native('secondary-sid') and self.visibility == 'auto' and state ~= nil then
        mp.set_property_bool(
                'secondary-sub-visibility',
                state.hover and (state.y / window_height()) < self.config.secondary_sub_area
        )
    end
end

local function on_file_loaded()
    -- If secondary sid is not already set, try to find and set it.
    local secondary_sid = mp.get_property_native('secondary-sid')
    if secondary_sid == false and self.config.secondary_sub_auto_load == true then
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

local function compare_by_preference_then_id(track1, track2)
    if is_accepted_language(track1.lang) and not is_accepted_language(track2.lang) then
        return true
    elseif not is_accepted_language(track1.lang) and is_accepted_language(track2.lang) then
        return false
    else
        return (track1.id < track2.id)
    end
end

local function split_before_after(previous_tracks, next_tracks, all_tracks, current_track_id)
    -- works like take_while() and drop_while() combined
    local prev = true
    for _, track in ipairs(all_tracks) do
        if prev == true and track.id == current_track_id then
            prev = false
        end
        if track.id ~= current_track_id then
            if prev then
                table.insert(previous_tracks, track)
            else
                table.insert(next_tracks, track)
            end
        end
    end
end

local function not_primary_sid(track)
    return mp.get_property_native('sid') ~= track.id
end

local function find_new_secondary_sub(direction)
    local subtitle_tracks = h.filter(h.get_loaded_tracks('sub'), not_primary_sid)
    table.sort(subtitle_tracks, compare_by_preference_then_id)

    local secondary_sid = mp.get_property_native('secondary-sid')
    local new_secondary_sub = { id = false, title = "removed" }

    if #subtitle_tracks > 0 then
        if not secondary_sid then
            new_secondary_sub = (direction == 'prev') and subtitle_tracks[#subtitle_tracks] or subtitle_tracks[1]
        else
            local previous_tracks = {}
            local next_tracks = {}
            split_before_after(previous_tracks, next_tracks, subtitle_tracks, secondary_sid)
            if direction == 'prev' and #previous_tracks > 0 then
                new_secondary_sub = previous_tracks[#previous_tracks]
            elseif direction == 'next' and #next_tracks > 0 then
                new_secondary_sub = next_tracks[1]
            end
        end
    end
    return new_secondary_sub
end

local function switch_secondary_sid(direction)
    local new_secondary_sub = find_new_secondary_sub(direction)

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
    select_previous = function()
        switch_secondary_sid('prev')
    end,
    select_next = function()
        switch_secondary_sid('next')
    end,
}
