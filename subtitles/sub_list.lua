--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Subtitle list remembers selected subtitle lines.
]]

local h = require('helpers')

local new_sub_list = function()
    local subs_list = {}

    local find_i = function(sub)
        for i, v in ipairs(subs_list) do
            if sub < v then
                return i
            end
        end
        return #subs_list + 1
    end
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
        if sub ~= nil and not h.contains(subs_list, sub) then
            table.insert(subs_list, find_i(sub), sub)
            return true
        end
        return false
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
