--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Config management, validation, loading.
]]

local mpopt = require('mp.options')
local msg = require('mp.msg')
local h = require('helpers')
local defaults = require('config.defaults')
local cfg_utils = require('config.utils')

local default_profile_filename = 'subs2srs'
local profiles_filename = 'subs2srs_profiles'

local function make_config_mgr()
    local self = {
        config = nil,
        profiles = nil,
        initial_config = {},
        init_done = false,
    }

    local function remember_initial_config()
        if h.is_empty(self.initial_config) then
            self.initial_config = h.shallow_copy(self.config, self.initial_config)
        else
            msg.fatal("Ignoring. Initial config has been read already.")
        end
    end

    local function restore_initial_config()
        self.config = h.shallow_copy(self.initial_config, self.config)
    end

    local function read_profile_list()
        mpopt.read_options(self.profiles, profiles_filename)
        msg.info("Read profile list. Defined profiles: " .. self.profiles.profiles)
    end

    local function read_profile(profile_name)
        mpopt.read_options(self.config, profile_name)
        msg.info("Read config file: " .. profile_name)
    end

    local function read_default_config()
        read_profile(default_profile_filename)
    end

    local function reload_from_disk()
        --- Loads default config file (subs2srs.conf), then overwrites it with current profile.
        if not h.is_empty(self.config) and not h.is_empty(self.profiles) then
            restore_initial_config()
            read_default_config()
            if self.profiles.active ~= default_profile_filename then
                read_profile(self.profiles.active)
            end
            cfg_utils.validate_config(self.config)
        else
            msg.fatal("Attempt to load config when init hasn't been done.")
        end
    end

    local function next_profile()
        local first, next, new
        for profile in string.gmatch(self.profiles.profiles, '[^,]+') do
            if not first then
                first = profile
            end
            if profile == self.profiles.active then
                next = true
            elseif next then
                next = false
                new = profile
            end
        end
        if next == true or not new then
            new = first
        end
        self.profiles.active = new
        reload_from_disk()
    end

    local function init()
        cfg_utils.create_config_file(default_profile_filename)
        self.config = h.shallow_copy(defaults.defaults)
        self.profiles = h.shallow_copy(defaults.profiles)

        -- 'subs2srs' is the main profile, it is always loaded. 'active profile' overrides it afterwards.
        -- initial state is saved to another table to maintain consistency when cycling through incomplete profiles.
        read_profile_list()
        read_default_config()
        remember_initial_config()
        if self.profiles.active ~= default_profile_filename then
            read_profile(self.profiles.active)
        end
        cfg_utils.validate_config(self.config)
        self.init_done = true
    end

    local function is_init_done()
        return self.init_done
    end

    local function fail_if_not_ready()
        if not self.init_done then
            error("config not loaded")
        end
    end

    local function get_profiles()
        fail_if_not_ready()
        return self.profiles
    end

    local function get_config()
        fail_if_not_ready()
        return self.config
    end

    return {
        init = init,
        reload_from_disk = reload_from_disk,
        next_profile = next_profile,
        init_done = is_init_done,
        config = get_config,
        profiles = get_profiles,
        fail_if_not_ready = fail_if_not_ready,
    }
end

return {
    new = make_config_mgr
}
