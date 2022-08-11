--[[
Copyright: Ren Tatsumoto and contributors
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Platform-specific functions.
]]

local h = require('helpers')

if h.is_win() then
    return require('platform.win')
else
    return require('platform.nix')
end
