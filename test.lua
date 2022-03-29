require('helpers')

local lu = require('luaunit')

function test_get_episode_number()
    local test_cases = {
      { nil, "A Whisker Away.mkv" },
      { nil, "[*******] Gekijouban SHIROBAKO [Ma10p_1080p][x265_flac]" },
      { "06", "[**********] Sono Bisque Doll wa Koi wo Suru - 06 [54E495D0]" },
      { "02", "(Hi10)_Kobayashi-san_Chi_no_Maid_Dragon_-_02_(BD_1080p)_(*******)_(12C5D2B4)" },
      { "01", "[*******] Koi to Yobu ni wa Kimochi Warui - 01 (1080p) [D517C9F0]" },
      { "01", "[*******] Tsukimonogatari 01 [BD 1080p x264 10-bit FLAC] [5CD88145]" },
      { "01", "[*******] 86 - Eighty Six - 01 (1080p) [1B13598F]" },
      { "00", "[*******] Fate Stay Night - Unlimited Blade Works - 00 (BD 1080p Hi10 FLAC) [95590B7F]" },
      { "01", "House, M.D. S01E01 Pilot - Everybody Lies (1080p x265 *******)" },
    }

    for _, case in pairs(test_cases) do
      local _, _, episode_num = Helpers:get_episode_number(case[2])
      lu.assertEquals(episode_num, case[1])
    end
end

os.exit(lu.LuaUnit.run())
