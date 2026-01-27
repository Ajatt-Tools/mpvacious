--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle list remembers selected subtitle lines.
]]

local h = require('helpers')

local new_sub_list = function()
    local subs_list = {}

    local get_time = function(position)
        local i = position == 'start' and 1 or #subs_list
        return subs_list[i][position]
    end
    local get_text = function()
        local speech = {}
        for _, sub in ipairs(subs_list) do
            table.insert(speech, sub['text'])
        end
        return table.concat(speech, ' ')
    end
    local get_n_text = function(sub, n_lines)
        local speech = {}
        local end_sub = sub
        for _, v in ipairs(subs_list) do
            if v['start'] - end_sub['end'] >= 20 then
                break
            end
            if v >= sub and #speech < n_lines then
                table.insert(speech, v['text'])
                end_sub = v
            end
        end
        return table.concat(speech, ' '), end_sub
    end
    local insert = function(sub)
        if sub == nil then
            return false
        end
        local lookup_window_size = 25
        local n_latest_subs = {h.unpack(subs_list, math.max(#subs_list - lookup_window_size, 1), #subs_list)}
        if h.contains(n_latest_subs, sub) then
            return false
        end
        table.insert(subs_list, h.find_insertion_point(n_latest_subs, sub), sub)
        return true
    end
    local get_subs_list = function()
        local copy = {}
        for key, value in pairs(subs_list) do
            copy[key] = value
        end
        return copy
    end
    return {
        get_subs_list = get_subs_list,
        get_time = get_time,
        get_text = get_text,
        get_n_text = get_n_text,
        insert = insert,
        is_empty = function()
            return h.is_empty(subs_list)
        end,
    }
end

return {
    new = new_sub_list,
}
