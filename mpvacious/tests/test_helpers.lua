--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Test helpers.
]]

local h = require("helpers")
local utils = require("mp.utils")
local fixtures = require("tests.fixtures")

--- Preserve dense, sparse, and string keys while mapping values into a separate table.
local function test_map_preserves_keys_and_input()
    for _, case in ipairs {
        { input = {}, expected = {} },
        { input = { 1, 2, 3 }, expected = { 2, 4, 6 } },
        { input = { [2] = 3, [5] = 7 }, expected = { [2] = 6, [5] = 14 } },
        { input = { first = 2, second = 5 }, expected = { first = 4, second = 10 } },
    } do
        local original = h.deep_copy(case.input)
        local mapped = h.map(case.input, function(value) return value * 2 end)
        h.assert_equals(mapped, case.expected)
        h.assert_equals(rawequal(mapped, case.input), false)
        mapped.extra = true
        h.assert_equals(case.input, original)
    end
end

--- Retain false mapped values rather than treating them as absent entries.
local function test_map_preserves_false_values()
    local input = { first = true, second = false }
    h.assert_equals(h.map(input, function(value) return not value end), { first = false, second = true })
    h.assert_equals(input, { first = true, second = false })
end

--- Leave original indices intact when a mapping callback returns nil for an entry.
local function test_map_omits_nil_results()
    local input = { 1, 2, 3 }
    local mapped = h.map(input, function(value)
        if value ~= 2 then return value end
    end)
    h.assert_equals(mapped, { [1] = 1, [3] = 3 })
    h.assert_equals(input, { 1, 2, 3 })
end

--- Reduce numeric arrays with default-zero and explicitly supplied accumulators.
local function test_reduce_numeric_accumulators()
    for _, case in ipairs {
        { input = {}, expected = 0 },
        { input = { 1, 2, 3 }, expected = 6 },
        { input = { 1, 2, 3 }, initial = 10, expected = 16 },
        { input = { 1, 2, 3 }, initial = 0, expected = 6 },
    } do
        local original = h.deep_copy(case.input)
        local result = h.reduce(case.input, function(total, value) return total + value end, case.initial)
        h.assert_equals(result, case.expected)
        h.assert_equals(case.input, original)
    end
end

--- Visit array entries in index order and follow ipairs behavior at missing indices.
local function test_reduce_array_iteration()
    for _, case in ipairs {
        { input = { "third", "first", "second" }, expected = "third|first|second|" },
        { input = { [1] = "first", [3] = "third" }, expected = "first|" },
        { input = { named = "ignored" }, expected = "" },
    } do
        local result = h.reduce(case.input, function(text, value) return text .. value .. "|" end, "")
        h.assert_equals(result, case.expected)
    end
end

--- Preserve false accumulators and false array entries rather than applying a truthy default.
local function test_reduce_false_accumulator()
    local result = h.reduce({ false }, function(accumulator, value)
        h.assert_equals(accumulator, false)
        h.assert_equals(value, false)
        return true
    end, false)
    h.assert_equals(result, true)
end

--- Return empty-array accumulators unchanged without invoking the reducer.
local function test_reduce_empty_array()
    local reject_call = h.as_callback(error, "an empty array must not invoke its reducer")
    local initial = { retained = true }
    h.assert_equals(h.reduce({}, reject_call), 0)
    h.assert_equals(h.reduce({}, reject_call, nil), 0)
    h.assert_equals(h.reduce({}, reject_call, false), false)
    h.assert_equals(rawequal(h.reduce({}, reject_call, initial), initial), true)
end

--- Build slice scenarios covering bounds, negative indices, and fractional indices.
local function make_islice_cases()
    return {
        { input = { 1, 2, 3 }, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 2, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 2, end_pos = 2, expected = { 2 } },
        { input = { 1, 2, 3 }, start_pos = 2, end_pos = 99, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 99, expected = {} },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = 0, expected = {} },
        { input = { 1, 2, 3 }, start_pos = -2, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = -1, expected = { 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = -2, expected = { 1, 2 } },
        { input = { 1, 2, 3 }, start_pos = -3, end_pos = -1, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = -99, expected = { 1, 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = -99, expected = {} },
        { input = { 1, 2, 3 }, start_pos = 1.5, expected = { 2, 3 } },
        { input = { 1, 2, 3 }, start_pos = 1, end_pos = 2.5, expected = { 1, 2 } },
        { input = { 1, 2, 3 }, start_pos = 1.5, end_pos = 2.5, expected = { 2 } },
    }
end

--- Verify table slices against the boundary scenarios.
local function test_islice()
    for _, case in ipairs(make_islice_cases()) do
        h.assert_equals(h.itable_slice(case.input, case.start_pos, case.end_pos), case.expected)
    end
end

--- Build ordered-list equality scenarios.
local function make_list_equal_cases()
    return {
        { { 1, 2, 3 }, { 1, 2, 3 }, true }, -- identical lists
        { { 1, 2 }, { 1, 2, 3 }, false }, -- different lengths
        { { 1, 2, 3 }, { 1, 2 }, false }, -- different lengths, other direction
        { { 1, 2, 3 }, { 1, 9, 3 }, false }, -- same length, different element
        { {}, {}, true }, -- both empty
        { { "a", "b" }, { "a", "b" }, true }, -- string elements
        { { "a" }, { "A" }, false }, -- exact (case-sensitive) match
        { { 1, 2 }, { 2, 1 }, false }, -- order matters
    }
end

--- Verify list equality respects length, values, and order.
local function test_list_equal()
    for _, case in ipairs(make_list_equal_cases()) do
        local first, second, expected = h.unpack(case)
        h.assert_equals(h.list_equal(first, second), expected)
    end
end

--- Build structural equality scenarios with reordered and shared tables.
local function make_equal_table_values_cases(reordered, note_info)
    local shared = { value = "same" }
    return {
        { first = note_info, last = reordered, expected = true },
        { first = reordered, last = note_info, expected = true },
        { first = note_info, last = { noteId = 2, fields = { Sentence = { value = "changed" } } }, expected = false },
        { first = note_info, last = { noteId = 2, fields = note_info.fields, extra = true }, expected = false },
        { first = { 1, 2 }, last = { 2, 1 }, expected = false },
        { first = { false }, last = { {} }, expected = false },
        {
            first = { a = shared, b = shared },
            last = { a = { value = "same" }, b = { value = "same" } },
            expected = true,
        },
        { first = false, last = nil, expected = false },
        { first = nil, last = nil, expected = true },
    }
end

--- Verify table equality ignores object-key order but respects values and array order.
local function test_equal_table_values()
    local note_info = { noteId = 2, fields = { Sentence = { value = "second" }, Audio = { value = "" } } }
    local reordered = { fields = { Audio = { value = "" }, Sentence = { value = "second" } }, noteId = 2 }
    h.assert_equals(reordered, note_info)
    for _, case in ipairs(make_equal_table_values_cases(reordered, note_info)) do
        h.assert_equals(h.equal(case.first, case.last), case.expected)
    end
end

--- Build nonempty-string boundary scenarios including other Lua value types.
local function make_is_non_empty_str_cases()
    return {
        { value = "/anki/media", expected = true },
        { value = " ", expected = true },
        { value = "", expected = false },
        { value = nil, expected = false },
        { value = 42, expected = false },
        { value = false, expected = false },
        { value = {}, expected = false },
    }
end

--- Verify only nonempty strings satisfy the media-path boundary check.
local function test_is_non_empty_str()
    for _, case in ipairs(make_is_non_empty_str_cases()) do
        h.assert_equals(h.is_non_empty_str(case.value), case.expected)
    end
end

--- Build mixed newline normalization scenarios.
local function make_normalize_newlines_cases()
    return {
        { "a\r\nb", "a\nb" },
        { "a\rb", "a\nb" },
        { "a\r\nb\rc", "a\nb\nc" },
        { "a\nb", "a\nb" },
    }
end

--- Verify carriage returns normalize to line feeds.
local function test_normalize_newlines()
    for _, case in ipairs(make_normalize_newlines_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.normalize_newlines(text), expected)
    end
end

--- Build line-splitting scenarios preserving empty lines.
local function make_split_line_cases()
    return {
        { "a\nb", { "a", "b" } },
        { "a\n", { "a", "" } },
        { "", { "" } },
        { "\n", { "", "" } },
    }
end

--- Verify splitting preserves leading and trailing empty lines.
local function test_split_lines()
    for _, case in ipairs(make_split_line_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.split_lines(text), expected)
    end
end

--- Build line-limit scenarios with truncation and empty input.
local function make_limit_lines_cases()
    return {
        -- {lines, max_lines, expected}
        { { "a", "b" }, 3, { "a", "b" } }, -- under the limit: unchanged
        { { "a", "b" }, 2, { "a", "b" } }, -- exactly at the limit: unchanged
        { { "a", "b", "c" }, 2, { "a", "b…" } }, -- over the limit: capped, ellipsis on the last kept line
        { { "a", "b", "c" }, 1, { "a…" } }, -- limit of one line
        { {}, 2, {} }, -- empty input
    }
end

--- Verify capped lines receive an ellipsis only when truncated.
local function test_limit_lines()
    for _, case in ipairs(make_limit_lines_cases()) do
        local lines, max_lines, expected = h.unpack(case)
        h.assert_equals(h.limit_lines(lines, max_lines), expected)
    end
end

--- Build wrapping scenarios for whitespace, Unicode, and custom separators.
local function make_str_wrap_cases()
    return {
        { text = "short", n_chars = 25, separator = [[\N]], expected = "short" },
        { text = "abcdef", n_chars = 3, separator = [[\N]], expected = [[abc\Ndef]] },
        { text = "one two three", n_chars = 6, separator = [[\N]], expected = [[one\Ntwo\Nthree]] },
        { text = "like them.", n_chars = 9, separator = [[\N]], expected = [[like\Nthem.]] },
        { text = " abc def", n_chars = 4, separator = [[\N]], expected = [[abc\Ndef]] },
        { text = "ab cdefgh", n_chars = 3, separator = [[\N]], expected = [[ab\Ncde\Nfgh]] },
        { text = "一二三四五六", n_chars = 6, separator = [[\N]], expected = [[一二三\N四五六]] },
        { text = "ab一二cd", n_chars = 6, separator = [[\N]], expected = [[ab一二\Ncd]] },
        { text = "一二\n三四", n_chars = 6, separator = [[\N]], expected = [[一二\N三四]] },
        { text = "Привет", n_chars = 3, separator = [[\N]], expected = [[При\Nвет]] },
        { text = "", n_chars = 6, separator = [[\N]], expected = "" },
        { text = "一", n_chars = 1, separator = [[\N]], expected = "一" },
        { text = "a\n\nb", n_chars = 6, separator = [[\N]], expected = [[a\N\Nb]] },
        { text = "a\n", n_chars = 6, separator = [[\N]], expected = [[a\N]] },
        { text = "\na", n_chars = 6, separator = [[\N]], expected = [[\Na]] },
        { text = "abcdef", n_chars = 3, expected = "abc\ndef" },
    }
end

--- Verify wrapping preserves text boundaries and requested separators.
local function test_str_wrap()
    for _, case in ipairs(make_str_wrap_cases()) do
        h.assert_equals(h.str_wrap(case.text, case.n_chars, case.separator), case.expected)
    end
end

--- Build subtitle trimming scenarios with annotations and whitespace.
local function make_trim_cases()
    return {
        { "  hello  ", "hello" },
        { "　hello　", "hello" },
        { " (note) hello ", "hello" },
        { "a \n b", "a b" },
        { "a  b", "a b" },
    }
end

--- Verify subtitle trimming removes annotations and normalizes spacing.
local function test_trim()
    for _, case in ipairs(make_trim_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.trim(text), expected)
    end
end

--- Build normalization scenarios for markup, Unicode spaces, and quotation marks.
local function make_normalized_subtitle_text_cases()
    return {
        { "<b>現実味</b>", "現実味" },
        { "a　b", "a b" },
        { "a\194\160b", "a b" },
        { "a\226\128\175b", "a b" },
        { "a\226\128\139b", "ab" },
        { "\239\187\191ab", "ab" },
        { "『お』", '"お"' },
        { "「お」", '"お"' },
        { "“お”", '"お"' },
        { "〝お〟", '"お"' },
        { "＂お＂", '"お"' },
        { "  a\t\nb  ", "a b" },
        {
            "女の子の <b>女性</b>の　『お』から始まる…",
            '女の子の 女性の "お"から始まる…',
        },
    }
end

--- Verify subtitle normalization produces consistent plain text.
local function test_normalize_subtitle_text()
    for _, case in ipairs(make_normalized_subtitle_text_cases()) do
        local text, expected = h.unpack(case)
        h.assert_equals(h.normalize_subtitle_text(text), expected)
    end
end

--- Verify substring searches treat Lua pattern characters literally.
local function test_is_substr()
    -- Test is_substr
    h.assert_equals(h.is_substr("abcd", "bc"), true)
    h.assert_equals(h.is_substr("abcd", "xyz"), false)
    h.assert_equals(h.is_substr("abcd", "^.*d.*$"), false)
end

--- Verify pattern-based searches evaluate Lua patterns.
local function test_str_contains()
    -- Test str_contains
    h.assert_equals(h.str_contains("abcd", "^.*d.*$"), true)
    h.assert_equals(h.str_contains("abcd", "^.*z.*$"), false)
end

--- Verify consecutive whitespace collapses to a single space.
local function test_collapse_whitespace()
    -- Test collapse_whitespace
    h.assert_equals(h.collapse_whitespace("a  b"), "a b")
    h.assert_equals(h.collapse_whitespace("a\tb"), "a b")
    h.assert_equals(h.collapse_whitespace("a\nb"), "a b")
    h.assert_equals(h.collapse_whitespace("a\r\nb"), "a b")
    h.assert_equals(h.collapse_whitespace("a \t \n b"), "a b")
end

--- Lowercase HTML and normalize spacing and entities without erasing escaped literal tags.
local function test_normalize_html_text()
    for _, case in ipairs {
        { expected = "" },
        { input = "", expected = "" },
        { input = "<b>Hello</b><BR/>World&nbsp;!", expected = "hello world !" },
        { input = " one<br>two<br />three\n four ", expected = "one two three four" },
        { input = "<b>&lt;Hello&gt;</b>", expected = "<hello>" },
        { input = "&amp;lt;Hello&amp;gt;", expected = "&lt;hello&gt;" },
        { input = "<i></i><br>&nbsp;", expected = "" },
    } do
        h.assert_equals(h.normalize_html_text(case.input), case.expected)
        h.assert_equals(select("#", h.normalize_html_text(case.input)), 1)
    end
end

--- Verify HTML entities decode once while unknown entities remain unchanged.
local function test_unescape_special_characters()
    for _, case in ipairs {
        { input = "that&apos;s", expected = "that's" },
        { input = "that&#39;s &amp; &quot;ok&quot;", expected = 'that\'s & "ok"' },
        { input = "&lt;tag&gt;", expected = "<tag>" },
        { input = "&amp;lt;tag&amp;gt;", expected = "&lt;tag&gt;" },
        { input = "&amp;amp;", expected = "&amp;" },
        { input = "&unknown; &#123; &nbsp;", expected = "&unknown; &#123; &nbsp;" },
        { input = "plain text", expected = "plain text" },
        { input = "", expected = "" },
    } do
        h.assert_equals(h.unescape_special_characters(case.input), case.expected)
    end
end

--- Keep gsub replacement counts out of both helpers' public return values.
local function test_entity_helpers_return_only_strings()
    for _, helper in ipairs { h.escape_special_characters, h.unescape_special_characters } do
        for _, text in ipairs { "", "plain text", "<tag> &amp; &quot;" } do
            h.assert_equals(select("#", helper(text)), 1)
            h.assert_equals(type(helper(text)), "string")
        end
    end
end

--- Verify HTML escaping is idempotent and reversible for plain text.
local function test_escape_special_characters()
    -- Test escape_special_characters
    h.assert_equals(h.escape_special_characters("that's"), "that&apos;s")
    h.assert_equals(h.escape_special_characters('that\'s & "ok"'), "that&apos;s &amp; &quot;ok&quot;")
    h.assert_equals(h.escape_special_characters("<tag>"), "&lt;tag&gt;")
    h.assert_equals(h.escape_special_characters("&\"'<>"), "&amp;&quot;&apos;&lt;&gt;")
    h.assert_equals(h.escape_special_characters("a<b&c"), "a&lt;b&amp;c")
    h.assert_equals(h.escape_special_characters("&amp;"), "&amp;")
    h.assert_equals(h.escape_special_characters("hello world"), "hello world")
    h.assert_equals(h.escape_special_characters(""), "")
    -- Round-trip: unescape(escape(text)) should return the original text.
    h.assert_equals(h.unescape_special_characters(h.escape_special_characters('that\'s & "ok"')), 'that\'s & "ok"')
    -- Idempotency: escaping an already-escaped string should be a no-op.
    h.assert_equals(
        h.escape_special_characters(h.escape_special_characters('that\'s & "ok"')),
        "that&apos;s &amp; &quot;ok&quot;"
    )
end

--- Build episode-number scenarios including movies without episode numbers.
local function make_ep_num_cases()
    return {
        { filename = "A Whisker Away.mkv", expected = nil },
        { filename = "[Placeholder] Gekijouban SHIROBAKO [Ma10p_1080p][x265_flac]", expected = nil },
        { filename = "[Placeholder] Sono Bisque Doll wa Koi wo Suru - 06 [54E495D0]", expected = "06" },
        {
            filename = "(Hi10)_Kobayashi-san_Chi_no_Maid_Dragon_-_02_(BD_1080p)_(Placeholder)_(12C5D2B4)",
            expected = "02",
        },
        { filename = "[Placeholder] Koi to Yobu ni wa Kimochi Warui - 01 (1080p) [D517C9F0]", expected = "01" },
        { filename = "[Placeholder] Tsukimonogatari 01 [BD 1080p x264 10-bit FLAC] [5CD88145]", expected = "01" },
        { filename = "[Placeholder] 86 - Eighty Six - 01 (1080p) [1B13598F]", expected = "01" },
        {
            filename = "[Placeholder] Fate Stay Night - Unlimited Blade Works - 00 (BD 1080p Hi10 FLAC) [95590B7F]",
            expected = "00",
        },
        { filename = "House, M.D. S01E01 Pilot - Everybody Lies (1080p x265 Placeholder)", expected = "01" },
        { filename = "A Generic Episode-165", expected = "165" },
    }
end

--- Verify episode extraction across filename conventions.
local function test_get_episode_number()
    -- Test get_episode_number
    -- Use records instead of a filename → expected map because Lua table entries
    -- with nil values do not exist. Keeping `expected = nil` inside a record lets
    -- us test filenames where no episode number should be found.
    for _, case in ipairs(make_ep_num_cases()) do
        local _, _, episode_num = h.get_episode_number(case.filename)
        h.assert_equals(episode_num, case.expected)
    end
end

--- Verify shallow copying replaces destination values.
local function test_shallow_copy()
    local t1 = { 1, 2, 3 }
    local t2 = { 3, 4, 5 }
    h.shallow_copy(t1, t2)
    h.assert_equals(t2, t1)
end

--- Provide a linear reference implementation for insertion-point tests.
local function find_insertion_point_linear(list, new)
    for idx, value in ipairs(list) do
        if new < value then
            return idx
        end
    end
    return #list + 1
end

--- Build sorted insertion scenarios including duplicates and empty lists.
local function make_insertion_cases()
    return {
        { { 1, 2, 4, 5 }, 3, 3 },
        { { 1, 2, 4, 5 }, 99, 5 },
        { { 1, 2, 4, 5 }, 0, 1 },
        { { 1, 2, 4, 5 }, 2, 3 },
        { { 1, 2, 4, 5 }, 5, 5 },
        { {}, 5, 1 },
        { { 2, 2, 2, 2, 2, 2 }, 5, 7 },
    }
end

--- Compare insertion points with expected indices and the linear reference.
local function test_find_insertion_point()
    for _, case in ipairs(make_insertion_cases()) do
        local list, new_value, expected = h.unpack(case)
        local r1 = find_insertion_point_linear(list, new_value)
        local r2 = h.find_insertion_point(list, new_value)
        h.assert_equals(r1, r2)
        h.assert_equals(r2, expected)
    end
end

--- Verify adjacent-item windows remain within list boundaries.
local function test_adjacent_items()
    --- Extract item values from adjacent-item test results.
    local function _items(items)
        local ret = {}
        for _, val in ipairs(items) do
            table.insert(ret, val.item)
        end
        return ret
    end
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3 }, 2, 1, 1)), { 1, 2, 3 })
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3 }, 2, 10, 10)), { 1, 2, 3 })
    h.assert_equals(
        _items(h.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 10, 4, 4)),
        { 2, 3, 4, 5, 6, 7, 8, 9, 10 }
    )
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 9, 3, 3)), { 4, 5, 6, 7, 8, 9, 10 })
    h.assert_equals(_items(h.adjacent_items({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, 1, 3, 3)), { 1, 2, 3, 4, 5, 6, 7 })
end

--- Verify GNU configuration and script directory conventions.
local function test_dirs()
    -- GNU only:
    if h.is_gnu() then
        h.assert_equals(h.find_mpv_scripts_dir(), utils.join_path(os.getenv("HOME") or "~", ".config/mpv/scripts"))
        h.assert_equals(h.find_mpv_config_directory(), utils.join_path(os.getenv("HOME") or "~", ".config/mpv"))
    end
end

--- Verify character-count limits preserve Unicode and mark truncation.
local function test_str_limit()
    -- Test str limit
    h.assert_equals(h.str_limit("abc", 3), "abc")
    h.assert_equals(h.str_limit("abcd", 3), "abc…")
    h.assert_equals(h.str_limit("報連相", 3), "報連相")
    h.assert_equals(h.str_limit("報連相", 2), "報連…")
    h.assert_equals(h.str_limit("報連相", 1), "報…")
    h.assert_equals(h.str_limit("報連相", 33), "報連相")
    h.assert_equals(h.str_limit("報連a", 2), "報連…") -- one narrow char remains after the cut
end

--- Verify display-width limits account for wide characters.
local function test_str_limit_width()
    -- Test str_limit_width: CJK counts double, narrower chars count once.
    h.assert_equals(h.str_limit_width("abc", 3), "abc")
    h.assert_equals(h.str_limit_width("abcd", 3), "abc…")
    h.assert_equals(h.str_limit_width("報連相", 3), "報…") -- 2 widths each, exceeds 3
    h.assert_equals(h.str_limit_width("報連", 4), "報連")
    h.assert_equals(h.str_limit_width("ab報", 4), "ab報")
    h.assert_equals(h.str_limit_width("ab報c", 4), "ab報…")
    h.assert_equals(h.str_limit_width("", 3), "")
    h.assert_equals(h.str_limit_width("報連相", 6, 3), "報連…") -- wide_char_width=3: two fit, third exceeds
    h.assert_equals(h.str_limit_width("ЯЯЯЯ", 3), "ЯЯЯ…") -- 2-byte chars count as narrow
end

--- Verify values clamp to inclusive lower and upper bounds.
local function test_clamp()
    -- Test clamp
    h.assert_equals(h.clamp(5, 1, 10), 5)
    h.assert_equals(h.clamp(0, 1, 10), 1)
    h.assert_equals(h.clamp(-100, 1, 10), 1)
    h.assert_equals(h.clamp(11, 1, 10), 10)
    h.assert_equals(h.clamp(1, 1, 10), 1)
    h.assert_equals(h.clamp(10, 1, 10), 10)
end

--- Verify version comparisons distinguish older, newer, and equal releases.
local function test_version_needs_update()
    -- Test version comparison
    h.assert_equals(h.version_needs_update("v1.0.0", "v1.0.0"), nil)
    h.assert_equals(h.version_needs_update("v1.0.0", "v1.0.1"), false)
    h.assert_equals(h.version_needs_update("v1.0.1", "v1.0.0"), true)
    h.assert_equals(h.version_needs_update("v1.10.0", "v1.9.0"), true)
    h.assert_equals(h.version_needs_update("v2.0.0", "v1.99.99"), true)
    h.assert_equals(h.version_needs_update("v1.0", "v1.0.0"), nil)
    h.assert_equals(h.version_needs_update("v1", "v1.0.0"), nil)
    h.assert_equals(h.version_needs_update("v26.1.30.0", "v26.1.30.1"), false)
end

--- Verify merging preserves sorted order and duplicate values.
local function test_join_two_sorted_lists()
    -- Test join_two_sorted_lists
    h.assert_equals(h.join_two_sorted_lists({ 1, 3, 5 }, { 2, 4, 6 }), { 1, 2, 3, 4, 5, 6 })
    h.assert_equals(h.join_two_sorted_lists({ 1, 2, 3 }, { 4, 5, 6 }), { 1, 2, 3, 4, 5, 6 })
    h.assert_equals(h.join_two_sorted_lists({ 4, 5, 6 }, { 1, 2, 3 }), { 1, 2, 3, 4, 5, 6 })
    h.assert_equals(h.join_two_sorted_lists({ 1, 3, 5 }, {}), { 1, 3, 5 })
    h.assert_equals(h.join_two_sorted_lists({}, { 2, 4, 6 }), { 2, 4, 6 })
    h.assert_equals(h.join_two_sorted_lists({}, {}), {})
    h.assert_equals(h.join_two_sorted_lists({ 1 }, { 2 }), { 1, 2 })
    h.assert_equals(h.join_two_sorted_lists({ 1, 1, 2 }, { 1, 3, 3 }), { 1, 1, 1, 2, 3, 3 })
end

--- Verify HTML tag removal preserves enclosed text.
local function test_remove_html_tags()
    -- Test h.remove_html_tags(str)
    h.assert_equals(h.remove_html_tags("ヤツらの声に<b>現実味</b>が…"), "ヤツらの声に現実味が…")
    h.assert_equals(
        h.remove_html_tags("ヤツらの声に<span>現実味</span>が…"),
        "ヤツらの声に現実味が…"
    )
    h.assert_equals(h.remove_html_tags("<b><b><b><b>"), "")
    h.assert_equals(h.remove_html_tags('<a href="test">test</a>'), "test")
end

--- Verify literal replacement handles patterns, Unicode, and occurrence limits.
local function test_str_replace()
    -- Test str_replace
    h.assert_equals(h.str_replace("a.b.a", ".", "-"), "a-b-a")
    h.assert_equals(h.str_replace("ababab", "ab", "x", 2), "xxab")
    h.assert_equals(h.str_replace("%w%w%w", "%w", "_"), "___")
    h.assert_equals(h.str_replace("abcdef", "%w", "_"), "abcdef")
    h.assert_equals(h.str_replace("メイド喫茶", "メイド", "冥土"), "冥土喫茶")
end

--- Ignore missing, empty, and non-string notifications before logging or displaying them.
local function test_notify_ignores_empty_messages()
    h.assert_equals(h.notify(nil), nil)
    for _, message in ipairs { "", false, 123, {} } do
        h.assert_equals(h.notify(message), nil)
    end
end

--- Verify canonical log dispatch and OSD rendering through the standalone recording mocks.
local function assert_notification_test_dispatch(calls, case)
    local before_log, before_osd = #calls.logs, #calls.osd
    h.notify("Notification regression", case.level, case.duration)
    h.assert_equals(#calls.logs, before_log + 1)
    h.assert_equals(#calls.osd, before_osd + 1)
    h.assert_equals(calls.logs[#calls.logs], { case.expected_level or case.level, "Notification regression" })
    h.assert_equals(calls.osd[#calls.osd], { "Notification regression", case.expected_duration or case.duration })
end

--- Exercise every canonical level, including v, without adding production-only injection arguments.
local function test_notify_canonical_log_dispatch()
    -- Real-mpv runs use actual APIs rather than the standalone setup's recording mocks.
    local setup = package.loaded["tests.setup"]
    if type(setup) ~= "table" then return end
    for _, level in ipairs { "fatal", "error", "warn", "info", "v", "debug", "trace" } do
        assert_notification_test_dispatch(setup.notification_calls, { level = level, duration = 2.5 })
    end
    for _, case in ipairs {
        { expected_level = "info", expected_duration = 1 },
        { level = "v", duration = 0 },
        { duration = 2.5, expected_level = "info" },
        { level = "info", expected_duration = 1 },
    } do
        assert_notification_test_dispatch(setup.notification_calls, case)
    end
end

--- Read isolated track metadata without modifying the supplied records.
local function assert_active_track_test_case(case, track_type)
    local original = h.deep_copy(case.tracks)
    local mp_api = fixtures.make_mp_property_reader { ["track-list"] = case.tracks }
    h.assert_equals(rawequal(h.get_active_track(track_type, mp_api), case.expected), true)
    h.assert_equals(case.tracks, original)
end

--- Handle unavailable metadata and select only matching, explicitly selected tracks.
local function test_get_active_track()
    for _, track_type in ipairs { "audio", "sub", "video" } do
        local selected = { type = track_type, selected = true, id = 7, albumart = track_type == "video" }
        local unselected = { type = track_type, selected = false, id = 8 }
        local wrong_type = { type = "other", selected = true, id = 9 }
        for _, case in ipairs {
            {},
            { tracks = {} },
            { tracks = { unselected } },
            { tracks = { wrong_type } },
            { tracks = { { type = track_type, id = 10 } } },
            { tracks = { unselected, wrong_type, selected }, expected = selected },
        } do
            assert_active_track_test_case(case, track_type)
        end
    end
end

--- Membership assertions accept listed values without modifying the allowed table.
local function test_assert_in_accepts_members()
    for _, case in ipairs {
        { value = "start", allowed = { "start", "end" } },
        { value = "end", allowed = { "start", "end" } },
        { value = false, allowed = { false, true } },
        { value = 0, allowed = { 0, 1 } },
        { value = "end", allowed = { [3] = "end" } },
        { value = "start", allowed = { boundary = "start" } },
    } do
        local original = h.shallow_copy(case.allowed)
        h.assert_equals(h.assert_in(case.value, case.allowed), nil)
        h.assert_equals(case.allowed, original)
    end
end

--- Rejected membership reports the caller and both values, including nil and empty allowed sets.
local function test_assert_in_rejects_nonmembers()
    for _, case in ipairs {
        { value = "middle", allowed = { "start", "end" } },
        { value = "", allowed = { "start", "end" } },
        { allowed = { "start", "end" } },
        { value = false, allowed = { "start", "end" } },
        { value = "start", allowed = {} },
        { allowed = {} },
    } do
        local original = h.shallow_copy(case.allowed)
        local success, message = pcall(function() h.assert_in(case.value, case.allowed) end)
        h.assert_equals(success, false)
        local expected = string.format("Expected one of %s, got %s", h.repr(case.allowed), h.repr(case.value))
        h.assert_equals(h.is_substr(message, expected), true)
        h.assert_equals(message:match("test_helpers%.lua:%d+: Expected one of ") ~= nil, true)
        h.assert_equals(case.allowed, original)
    end
end

--- Accept exact Lua type names without treating tables as metatable-based classes.
local function test_assert_type_accepts_builtin_types()
    for _, case in ipairs {
        { expected = "nil" },
        { value = false, expected = "boolean" },
        { value = 0, expected = "number" },
        { value = -1.5, expected = "number" },
        { value = "", expected = "string" },
        { value = {}, expected = "table" },
        { value = h.noop, expected = "function" },
        { value = coroutine.create(h.noop), expected = "thread" },
        { value = io.stdout, expected = "userdata" },
    } do
        h.assert_equals(h.assert_type(case.value, case.expected), nil)
    end
end

--- Report expected and actual types at the caller for mismatched values.
local function test_assert_type_rejects_wrong_types()
    for _, case in ipairs {
        { expected = "number", actual = "nil" },
        { value = false, expected = "number", actual = "boolean" },
        { value = "10", expected = "number", actual = "string" },
        { value = {}, expected = "number", actual = "table" },
        { value = 0, expected = "boolean", actual = "number" },
    } do
        local success, message = pcall(function() h.assert_type(case.value, case.expected) end)
        h.assert_equals(success, false)
        h.assert_equals(
            h.is_substr(message, string.format("Expected type %s, got %s", case.expected, case.actual)),
            true
        )
        h.assert_equals(message:match("test_helpers%.lua:%d+: Expected type ") ~= nil, true)
    end
end

--- Run the shared helper regression suite.
local function run_tests()
    test_map_preserves_keys_and_input()
    test_map_preserves_false_values()
    test_map_omits_nil_results()
    test_reduce_numeric_accumulators()
    test_reduce_array_iteration()
    test_reduce_false_accumulator()
    test_reduce_empty_array()
    test_is_substr()
    test_str_contains()
    test_collapse_whitespace()
    test_trim()
    test_normalize_subtitle_text()
    test_unescape_special_characters()
    test_normalize_html_text()
    test_entity_helpers_return_only_strings()
    test_escape_special_characters()
    test_get_episode_number()
    h.assert_equals(h.join_lists({ 1, 2 }, { 3 }, {}, { 4, 5 }), { 1, 2, 3, 4, 5 })
    test_list_equal()
    test_equal_table_values()
    test_is_non_empty_str()
    test_shallow_copy()
    test_find_insertion_point()
    test_adjacent_items()
    test_islice()
    test_dirs()
    test_str_limit()
    test_str_limit_width()
    test_normalize_newlines()
    test_split_lines()
    test_limit_lines()
    test_str_wrap()
    test_clamp()
    test_version_needs_update()
    test_join_two_sorted_lists()
    test_remove_html_tags()
    test_str_replace()
    test_notify_ignores_empty_messages()
    test_notify_canonical_log_dispatch()
    test_get_active_track()
    test_assert_in_accepts_members()
    test_assert_in_rejects_nonmembers()
    test_assert_type_accepts_builtin_types()
    test_assert_type_rejects_wrong_types()
end

return {
    run_tests = run_tests,
}
