--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Config utils tests.
]]

local h = require('helpers')
local defaults = require('config.defaults')
local cfg_utils = require('config.utils')

--- Run config default and validation tests.
local function run_tests()
    h.assert_equals(defaults.get_default().menu_max_shown_lines, 1)
    local formatted = cfg_utils.format_default_config('subs2srs', 'option=value\n')
    h.assert_equals(formatted:match('^# Written by subs2srs on .-%.\n(.*)$'), 'option=value\n')

    --- Return the validated number of visible menu lines.
    local function validate_menu_max_shown_lines(value)
        local config = defaults.get_default()
        config.menu_max_shown_lines = value
        cfg_utils.validate_config(config)
        return config.menu_max_shown_lines
    end

    local cases = {
        { -10, defaults.min_menu_max_shown_lines },
        { defaults.min_menu_max_shown_lines, defaults.min_menu_max_shown_lines },
        { defaults.default_menu_max_shown_lines, defaults.default_menu_max_shown_lines },
        { defaults.max_menu_max_shown_lines, defaults.max_menu_max_shown_lines },
        { 9999, defaults.max_menu_max_shown_lines },
    }

    for _, case in ipairs(cases) do
        local value, expected = h.unpack(case)
        h.assert_equals(validate_menu_max_shown_lines(value), expected)
    end
end

return {
    run_tests = run_tests,
}
