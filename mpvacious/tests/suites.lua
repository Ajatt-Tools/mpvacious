--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Test suites
]]

local modules = {
    "tests.test_helpers",
    "tests.test_observer",
    "tests.test_encoder_utils",
    "tests.test_new_note_checker",
    "tests.test_ankiconnect",
    "tests.test_note_exporter",
    "tests.test_sub_list",
    "tests.test_collector",
    "tests.test_config_utils",
    "tests.test_snapshot",
    "tests.test_encoder",
    "tests.test_subtitle",
    "tests.test_note_update_context",
    "tests.test_forvo",
    "tests.test_note_update_guard",
    "tests.test_note_update_workflow",
    "tests.test_confirmation",
}

--- Load each registered suite for the standalone and mpv-backed runners.
local function load_test_suites()
    local suites = {}
    for _, module_name in ipairs(modules) do
        local module = require(module_name)
        suites[module_name] = { run_tests = module.run_tests }
    end
    return suites
end

--- Create a runner using the shared ordered suite registry.
local function make_test_suite_runner()
    local suites = load_test_suites()
    local self = {}

    --- Return the loaded suites keyed by module name.
    function self.suites()
        return suites
    end

    --- Run every registered suite in its declared order.
    function self.run_tests()
        for _, module_name in ipairs(modules) do
            print(string.format("Running %s tests...", module_name))
            suites[module_name].run_tests()
            print(string.format("%s tests passed.", module_name))
        end
    end

    return self
end

return {
    new = make_test_suite_runner,
}
