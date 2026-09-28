--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Test suites
]]

local modules = {
    'helpers',
    'encoder.encoder',
    'encoder.utils',
    'config.utils',
    'anki.ankiconnect',
    'anki.new_note_checker',
    'anki.note_exporter',
    'anki.note_update_context',
    'subtitles.subtitle',
    'subtitles.collector',
    'subtitles.sub_list',
    'subtitles.observer',
}

local function load_test_suites()
    local suites = {}
    for _, module_name in ipairs(modules) do
        local module = require(module_name)
        suites[module_name] = { run_tests = module.run_tests }
    end
    return suites
end

local function make_test_suite_runner()
    local suites = load_test_suites()
    local self = {}

    function self.suites()
        return suites
    end

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
