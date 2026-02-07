--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Check for updates.
]]

local mp = require('mp')
local h = require('helpers')
local platform = require('platform.init')
local utils = require('mp.utils')

local function make_release_checker(o)
    o = o or {}
    o.repo = o.repo or "Ajatt-Tools/mpvacious"
    o.max_time_sec = o.max_time_sec or 20
    o.check_delay_sec = o.check_delay_sec or 5
    local api_check_url = "https://api.github.com/repos/" .. o.repo .. "/releases/latest"
    local curl_args = { "-sL", "--max-time", tostring(o.max_time_sec), api_check_url }
    local is_new_version_available = false
    local latest_version, installed_version
    local self = {}

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
        if h.is_empty(latest_version) or h.is_empty(installed_version) then
            -- Couldn't get both versions. Can't compare
            return
        end
        -- Use numeric version comparison instead of string comparison
        is_new_version_available = h.version_needs_update(latest_version, installed_version) == true
        if is_new_version_available then
            mp.msg.warning("New version is available: " .. latest_version)
        else
            mp.msg.info("Installed version is up to date: " .. installed_version)
        end
    end

    local function parse_json(stdout)
        local json = utils.parse_json(stdout)
        if h.is_empty(json) then
            mp.msg.error("Couldn't parse JSON from " .. api_check_url .. ".")
        else
            latest_version = json.tag_name
            installed_version = read_installed_version_file()
            compare_versions()
        end
    end

    local function on_curl_request_finish(success, result, error)
        if success ~= true or error ~= nil then
            mp.msg.error("Couldn't connect to " .. api_check_url .. ". Error: " .. error)
        elseif h.is_empty(result) or result.status ~= 0 or h.is_empty(result.stdout) then
            mp.msg.error("Empty result from " .. api_check_url .. ". Status: " .. result.status)
        else
            parse_json(result.stdout)
        end
    end

    local function check_new_version()
        platform.curl_request { args = curl_args, completion_fn = on_curl_request_finish }
    end

    function self.run()
        mp.add_timeout(o.check_delay_sec, check_new_version)
    end

    function self.has_update()
        return is_new_version_available
    end

    function self.release_page_url()
        return "https://github.com/" .. o.repo .. "/releases/tag/" .. latest_version
    end

    function self.get_latest_version()
        return latest_version
    end

    function self.get_installed_version()
        return installed_version
    end

    return self
end

return {
    new = make_release_checker
}
