--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Detached configuration provider for one transaction.
]]

local h = require("helpers")

--- Capture a ready manager's settings and profile metadata once.
--- Implement only what is required for transactions that use them.
local function make_snapshot(cfg_mgr)
    cfg_mgr.fail_if_not_ready()
    local captured = h.deep_copy(cfg_mgr.config())
    local profiles = h.deep_copy(cfg_mgr.profiles())
    local public = {}

    --- Return mutable settings owned by this transaction, separate from the live profile.
    function public.config()
        return captured
    end

    --- Return profile metadata owned by this transaction.
    function public.profiles()
        return profiles
    end

    --- Confirm this provider was constructed from a ready manager.
    function public.fail_if_not_ready()
        return true
    end

    return public
end

return {
    new = make_snapshot,
}
