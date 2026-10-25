-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

local h = require("helpers")
local make_filename_factory = require("utils.filename_factory")
local fixtures = require("tests.fixtures")

-- This is the compatibility ceiling enforced by the filename limiter, including its suffix.
local ANKI_FILENAME_BYTE_LIMIT = 119
local DEFAULT_SUFFIX = "_99h99m99s999ms-99h99m99s999ms.webp"

--- Keep the full suffix and fill only complete characters into its remaining byte budget.
local function assert_filename_byte_budget_test_case(character, suffix)
    local api = fixtures.make_filename_factory_test_api()
    local filename_factory = make_filename_factory.new(api)
    local reserved_suffix = DEFAULT_SUFFIX
    if suffix then
        reserved_suffix = suffix
    end
    local budget = ANKI_FILENAME_BYTE_LIMIT - #reserved_suffix
    local text = character:rep(150)
    local result = filename_factory.anki_compatible_length(text, suffix)
    h.assert_equals(result, character:rep(math.floor(budget / #character)))
    h.assert_equals(#(result .. reserved_suffix) <= ANKI_FILENAME_BYTE_LIMIT, true)
    h.assert_equals(select("#", filename_factory.anki_compatible_length(text, suffix)), 1)
end

--- Use byte lengths, not script heuristics, for static, range, and fallback suffixes.
local function test_filename_byte_budgets()
    for _, character in ipairs { "a", "é", "日", "😊" } do
        for _, case in ipairs {
            {},
            { suffix = false },
            { suffix = "" },
            { suffix = "_00h00m00s000ms.webp" },
            { suffix = "_00h00m00s000ms_01h02m03s004ms.opus" },
            { suffix = "_100h00m00s000ms_101h02m03s004ms.avif" },
            { suffix = string.rep("s", ANKI_FILENAME_BYTE_LIMIT) },
        } do
            assert_filename_byte_budget_test_case(character, case.suffix)
        end
    end
end

--- Leave short names intact and truncate only when the complete filename would exceed the limit.
local function test_filename_exact_limit()
    local api = fixtures.make_filename_factory_test_api()
    local filename_factory = make_filename_factory.new(api)
    local suffix = "_00h00m00s000ms.jpg"
    local budget = ANKI_FILENAME_BYTE_LIMIT - #suffix
    for _, size in ipairs { 0, 1, budget - 1, budget, budget + 1 } do
        local text = string.rep("a", size)
        local result = filename_factory.anki_compatible_length(text, suffix)
        h.assert_equals(result, string.rep("a", math.min(size, budget)))
    end
end

--- Retain the longest mixed-width prefix rather than budgeting every character as CJK.
local function test_filename_mixed_width_prefix()
    local api = fixtures.make_filename_factory_test_api()
    local filename_factory = make_filename_factory.new(api)
    local suffix = string.rep("_", ANKI_FILENAME_BYTE_LIMIT - 8 - #".webp") .. ".webp"
    local result = filename_factory.anki_compatible_length("Aé車😊", suffix)
    h.assert_equals(result, "Aé車")
    h.assert_equals(#(result .. suffix), ANKI_FILENAME_BYTE_LIMIT - 2)
end

--- Read filenames on file load, applying cleanup and retaining the timestamp format.
local function test_filename_generation()
    for _, case in ipairs {
        { source = "Show [Group] (Extra).mkv", basename = "show" },
        { source = "(Title).mkv", basename = "title" },
        { source = "[Title].mkv", basename = "title" },
        { source = "---.mkv", basename = "---" },
    } do
        local api, state = fixtures.make_filename_factory_test_api(case.source)
        local factory = make_filename_factory.new(api)
        h.assert_equals(state.reads, 0)
        h.assert_equals(#state.events, 1)
        h.assert_equals(state.events[1].name, "file-loaded")
        state.events[1].callback()
        h.assert_equals(factory.make_filename(65, ".WEBP"), case.basename .. "_01m05s000ms.webp")
        h.assert_equals(factory.make_filename(65, 3661, ".opus"), case.basename .. "_01m05s000ms_1h01m01s000ms.opus")
    end
end

--- Keep independently cached names and update only the factory receiving a file-load callback.
local function test_filename_factory_instance_isolation()
    local first_api, first_state = fixtures.make_filename_factory_test_api("First.mkv")
    local second_api, second_state = fixtures.make_filename_factory_test_api("Second.mkv")
    local first, second = make_filename_factory.new(first_api), make_filename_factory.new(second_api)
    first_state.events[1].callback()
    second_state.events[1].callback()
    first_state.filename = "Next.mkv"
    h.assert_equals(first.make_filename(0, ".jpg"), "first_00m00s000ms.jpg")
    first_state.events[1].callback()
    h.assert_equals(first.make_filename(0, ".jpg"), "next_00m00s000ms.jpg")
    h.assert_equals(second.make_filename(0, ".jpg"), "second_00m00s000ms.jpg")
    h.assert_equals({ #first_state.events, #second_state.events }, { 1, 1 })
end

--- Generate real filenames without cutting a multibyte character or losing either suffix.
local function test_generated_filename_byte_limits()
    for _, character in ipairs { "a", "é", "日", "😊" } do
        local api, state = fixtures.make_filename_factory_test_api(character:rep(150) .. ".mkv")
        local factory = make_filename_factory.new(api)
        state.events[1].callback()
        for _, case in ipairs {
            { args = { 0, ".webp" }, suffix = "_00m00s000ms.webp" },
            { args = { 0, 1, ".opus" }, suffix = "_00m00s000ms_00m01s000ms.opus" },
        } do
            local expected = character:rep(math.floor((ANKI_FILENAME_BYTE_LIMIT - #case.suffix) / #character))
            local result = factory.make_filename(h.unpack(case.args))
            h.assert_equals(result, expected .. case.suffix)
            h.assert_equals(#result <= ANKI_FILENAME_BYTE_LIMIT, true)
        end
    end
end

--- Validate required basename and optional suffix types even when the basename needs no truncation.
local function test_filename_limiter_argument_types()
    local api, state = fixtures.make_filename_factory_test_api()
    local factory = make_filename_factory.new(api)
    for _, case in ipairs {
        { suffix = "" },
        { text = false, suffix = "" },
        { text = 0, suffix = "" },
        { text = {}, suffix = "" },
        { text = "name", suffix = 0 },
        { text = "name", suffix = true },
        { text = "name", suffix = {} },
    } do
        local success, message = pcall(factory.anki_compatible_length, case.text, case.suffix)
        h.assert_equals(success, false)
        h.assert_equals(h.is_substr(message, "Expected type string, got "), true)
    end
    h.assert_equals(state.reads, 0)
    h.assert_equals(factory.anki_compatible_length("name", ""), "name")
end

--- Oversized suffixes cannot be made safe by discarding the basename, including an empty basename.
local function test_filename_rejects_oversized_suffixes()
    local api = fixtures.make_filename_factory_test_api()
    local factory = make_filename_factory.new(api)
    for _, text in ipairs { "", "name", "日本" } do
        for _, size in ipairs { ANKI_FILENAME_BYTE_LIMIT + 1, ANKI_FILENAME_BYTE_LIMIT * 2 } do
            local success, message = pcall(factory.anki_compatible_length, text, string.rep("s", size))
            h.assert_equals(success, false)
            h.assert_equals(h.is_substr(message, "filename suffix exceeds Anki's 119-byte limit"), true)
        end
    end
    h.assert_equals(factory.anki_compatible_length("name", string.rep("s", ANKI_FILENAME_BYTE_LIMIT)), "")
end

--- Reject oversized real static/range suffixes without corrupting the factory's cached basename.
local function test_generated_filename_rejects_oversized_extensions()
    local api, state = fixtures.make_filename_factory_test_api("Episode.mkv")
    local factory = make_filename_factory.new(api)
    state.events[1].callback()
    local extension = "." .. string.rep("x", ANKI_FILENAME_BYTE_LIMIT)
    for _, args in ipairs { { 0, extension }, { 0, 1, extension } } do
        local success, message = pcall(factory.make_filename, h.unpack(args))
        h.assert_equals(success, false)
        h.assert_equals(h.is_substr(message, "filename suffix exceeds Anki's 119-byte limit"), true)
    end
    h.assert_equals(factory.make_filename(0, ".jpg"), "episode_00m00s000ms.jpg")
    h.assert_equals(state.reads, 1)
end

--- Run factory instance, event, generation, and byte-budget regressions on isolated mpv APIs.
local function run_tests()
    test_filename_byte_budgets()
    test_filename_exact_limit()
    test_filename_mixed_width_prefix()
    test_filename_generation()
    test_filename_factory_instance_isolation()
    test_generated_filename_byte_limits()
    test_filename_limiter_argument_types()
    test_filename_rejects_oversized_suffixes()
    test_generated_filename_rejects_oversized_extensions()
end

return { run_tests = run_tests }
