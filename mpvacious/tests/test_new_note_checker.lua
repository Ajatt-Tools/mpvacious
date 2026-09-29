--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

New-note checker tests.
]]

local fixtures = require('test_fixtures')
local make_new_note_checker = require('anki.new_note_checker')
local h = require('helpers')

--- Drive the checker through initialization and three ticks using its public API.
local function run_checker_test_scenario(state, case)
    local checker = make_new_note_checker.new({
        mp = fixtures.make_new_note_checker_mp(state),
        logger = fixtures.make_new_note_checker_logger(state),
    })
    checker.init(
            fixtures.make_new_note_checker_ankiconnect(state, case),
            function(ids, overwrite)
                h.assert_equals(ids, { state.note_id })
                h.assert_equals(overwrite, false)
                state.updates = state.updates + 1
            end, fixtures.make_config_manager {
                model_name = 'Test', deck_name = 'Test', sentence_field = 'Sentence',
                audio_field = 'Audio', image_field = 'Image', enable_new_note_timer = true,
                new_note_timer_interval_seconds = 2,
            }
    )
    checker.start_timer()
    for _ = 1, 3 do
        state.tick()
    end
    checker.stop_timer()
end

--- Assert one checker scenario without mutating shared mpv APIs.
local function assert_checker_test_case(case)
    local state = { searches = 0, fetches = 0, updates = 0, errors = {}, timer_kills = 0,
                    note_id = h.minutes_ago(case.age_minutes or 0) }
    run_checker_test_scenario(state, case)
    h.assert_equals(state.fetches, case.fetches)
    h.assert_equals(state.updates, case.updates)
    h.assert_equals(state.timer_kills, 1)
    local expected_errors = {}
    if case.error then
        expected_errors = { string.format('failed to retrieve note %s: %s', tostring(state.note_id), case.error) }
    end
    h.assert_equals(state.errors, expected_errors)
end

--- Verify one-time inspection for server errors, deleted notes, and each eligibility condition.
local function run_tests()
    local cases = {
        { error = "Ankiconnect isn't running", fetches = 1, updates = 0 },
        { error = 'AnkiConnect returned no fields for the deleted note', fetches = 1, updates = 0 },
        { fields = nil, fetches = 1, updates = 0 }, -- preserve the predicate's guard independently of fetch errors
        { fields = {}, fetches = 1, updates = 0 },
        { fields = { Sentence = 'text' }, fetches = 1, updates = 1 },
        { fields = { Sentence = '' }, fetches = 1, updates = 1 },
        { fields = { Other = 'text' }, fetches = 1, updates = 0 },
        { fields = { Sentence = 'text', Audio = '[sound:existing.ogg]' }, fetches = 1, updates = 0 },
        { fields = { Sentence = 'text', Image = '<img src="existing.png">' }, fetches = 1, updates = 0 },
        { fields = { Sentence = 'text' }, age_minutes = 3, fetches = 1, updates = 0 },
    }
    for _, case in ipairs(cases) do
        assert_checker_test_case(case)
    end
end

return {
    run_tests = run_tests,
}
