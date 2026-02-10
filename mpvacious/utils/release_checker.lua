--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Check for updates.
]]

local mp = require('mp')
local h = require('helpers')
local platform = require('platform.init')
local utils = require('mp.utils')

local function make_release_checker()
    local private = {}
    local public = {}

    private.repo="Ajatt-Tools/mpvacious"
    private.max_time_sec=20
    private.check_delay_sec=5
    private.api_check_url = "https://api.github.com/repos/" .. private.repo .. "/releases/latest"
    private.curl_args = { "-sL", "--max-time", tostring(private.max_time_sec), private.api_check_url }
    private.is_new_version_available = false
    private.latest_version = nil
    private.installed_version = nil

    local function read_installed_version_file()
        local version_file_path = utils.join_path(mp.get_script_directory(), "version.json")
        local version_text, error = h.read_text(version_file_path)
        if error then
            mp.msg.error(error)
            return nil
        end
        local json = utils.parse_json(version_text)
        if h.is_empty(json) then
            mp.msg.error("Couldn't parse JSON from " .. version_file_path)
            return nil
        end
        return json.version
    end

    local function compare_versions()
        if h.is_empty(private.latest_version) or h.is_empty(private.installed_version) then
            -- Couldn't get both versions. Can't compare
            return
        end
        -- Use numeric version comparison instead of string comparison
        private.is_new_version_available = h.version_needs_update(private.latest_version, private.installed_version) == true
        if private.is_new_version_available then
            mp.msg.warn("New version is available: " .. private.latest_version)
        else
            mp.msg.info("Installed version is up to date: " .. private.installed_version)
        end
    end

    local function parse_json(stdout)
        local json = utils.parse_json(stdout)
        if h.is_empty(json) then
            mp.msg.error("Couldn't parse JSON from " .. private.api_check_url .. ".")
        else
            private.latest_version = json.tag_name
            private.installed_version = read_installed_version_file()
            compare_versions()
        end
    end

    local function on_curl_request_finish(success, result, error)
        if success ~= true or error ~= nil then
            mp.msg.error("Couldn't connect to " .. private.api_check_url .. ". Error: " .. error)
        elseif h.is_empty(result) or result.status ~= 0 or h.is_empty(result.stdout) then
            mp.msg.error("Empty result from " .. private.api_check_url .. ". Status: " .. result.status)
        else
            parse_json(result.stdout)
        end
    end

    local function check_new_version()
        platform.curl_request { args = private.curl_args, completion_fn = on_curl_request_finish }
    end

    function public.init(cfg_mgr)
        -- Check if update checking is enabled in the config
        if not cfg_mgr.query("check_for_updates") then
            mp.msg.warn("Update checking is disabled in the configuration.")
            return
        end
        mp.add_timeout(private.check_delay_sec, check_new_version)
    end

    function public.has_update()
        return private.is_new_version_available
    end

    function public.release_page_url()
        if h.is_empty(private.latest_version) then
            return nil
        end
        return "https://github.com/" .. private.repo .. "/releases/tag/" .. private.latest_version
    end

    function public.get_latest_version()
        return private.latest_version
    end

    function public.get_installed_version()
        return private.installed_version
    end

    return public
end

return {
    new = make_release_checker
}
