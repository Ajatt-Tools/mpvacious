-- Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
-- License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

local h = require("helpers")
local filename_factory = require("utils.filename_factory")

-- This is the compatibility ceiling enforced by the filename limiter, including its suffix.
local ANKI_FILENAME_BYTE_LIMIT = 119
local DEFAULT_SUFFIX = "_99h99m99s999ms-99h99m99s999ms.webp"

--- Keep the full suffix and fill only complete characters into its remaining byte budget.
local function assert_filename_byte_budget_test_case(character, suffix)
    local reserved_suffix = DEFAULT_SUFFIX
    if suffix ~= nil then
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
    local suffix = string.rep("_", ANKI_FILENAME_BYTE_LIMIT - 8 - #".webp") .. ".webp"
    local result = filename_factory.anki_compatible_length("Aé車😊", suffix)
    h.assert_equals(result, "Aé車")
    h.assert_equals(#(result .. suffix), ANKI_FILENAME_BYTE_LIMIT - 2)
end

--- Run basename byte-budget regressions without changing shared mpv APIs or filename state.
local function run_tests()
    test_filename_byte_budgets()
    test_filename_exact_limit()
    test_filename_mixed_width_prefix()
end

return { run_tests = run_tests }
