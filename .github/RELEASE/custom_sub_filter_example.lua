--- See: https://github.com/Ajatt-Tools/mpvacious/pull/151

local M = {}

local isKana = function(char)
    local byte1, byte2, byte3 = string.byte(char, 1, 3)
    -- 平假名范围: ぁ (U+3041) 到 ゖ (U+3096)
    if byte1 == 227 and byte2 == 129 and (byte3 >= 128 and byte3 <= 191) then
        return true
    end
    -- 片假名范围: ァ (U+30A1) 到 ヶ (U+30F6)
    if byte1 == 227 and byte2 == 130 and (byte3 >= 128 and byte3 <= 191) then
        return true
    end
    -- 片假名扩展范围: ㇰ (U+31F0) 到 ㇿ (U+31FF)
    if byte1 == 227 and byte2 == 131 and (byte3 >= 128 and byte3 <= 191) then
        return true
    end
    return false
end

-- 检查字符串是否包含假名
local containsKana = function(str)
    for i = 1, #str do
        local char = str:sub(i, i + 2)
        if isKana(char) then
            return true
        end
    end
    return false
end

-- 判断字符串是否包含非简体的汉字（根据实际需要可调整范围）
local containsNonSimplifiedChinese = function(str)
    -- 简单判断是否包含日文汉字的范围，例如，常用日文汉字 (这个范围可能需要根据需求进一步细化)
    return str:match("[\228\184\128-\233\191\191]")
end

local contains_non_latin_letters = function(str)
    return str:match("[^%c%p%s%w—]")
end

local capitalize_first_letter = function(string)
    return string:gsub("^%l", string.upper)
end

local remove_leading_trailing_spaces = function(str)
    return str:gsub('^%s*(.-)%s*$', '%1')
end

local remove_leading_trailing_dashes = function(str)
    return str:gsub('^[%-_]*(.-)[%-_]*$', '%1')
end


local get_japanese = function(str1, str2)
    if containsKana(str1) then
        return str1
    elseif containsKana(str2) then
        return str2
    elseif containsNonSimplifiedChinese(str1) then
        return str1
    elseif containsNonSimplifiedChinese(str2) then
        return str2
    else
        return str1
    end
end

local get_last_two_parts = function(input)
    local lines = {}
    -- 使用 string.gmatch 分割字符串并存入表
    for line in string.gmatch(input, "[^\n]+") do
        table.insert(lines, line)
    end

    -- 获取最后两段，如果不足两段，则根据情况返回
    local count = #lines
    if count >= 2 then
        return lines[count - 1], lines[count]
    elseif count == 1 then
        return lines[1], ""  -- 如果只有一段，返回该段和空字符串
    else
        return "", ""  -- 如果没有段落，返回两个空字符串
    end
end

local get_japanese_from_subtext = function(text)
    if text == nil or text == "" then
        return ""
    end

    return get_japanese(get_last_two_parts(text))
end

M.preprocess = get_japanese_from_subtext

return M
