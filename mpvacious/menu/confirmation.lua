--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Present reusable Yes/No confirmations through mpv's console input.
]]

local mp = require("mp")
local input = require("mp.input")
local msg = require("mp.msg")
local h = require("helpers")

local CONFIRMATION_TIMEOUT_SECONDS = 20
local DEFAULT_MP_API = { input = input, msg = msg, mp = mp }

--- Return a stateful Yes/No confirmation controller with optional mp-compatible APIs.
--- Ignore new prompts until the active input handler has closed.
local function make_confirmation(mp_api)
    mp_api = mp_api or DEFAULT_MP_API
    local self = {
        -- The registered request remains active until its closed callback runs.
        active = nil,
        notify = mp_api.notify or h.notify,
    }
    local public = {}

    --- Resolve once, stop the timer, and close the active prompt.
    --- Return whether this call initiated prompt closure.
    local function resolve_and_close_request(request)
        if request.resolved then
            return false
        end
        request.resolved = true
        if request.timer then
            request.timer:kill()
        end
        if self.active ~= request or request.closed then
            return false
        end
        request.closed = true
        mp_api.input.terminate()
        return true
    end

    --- Accept once after resolving and requesting prompt closure.
    local function accept_request(request)
        if resolve_and_close_request(request) then
            request.on_accept()
        end
    end

    --- Cancel once, close any active prompt, and report an optional reason.
    local function cancel_request(request, reason)
        if resolve_and_close_request(request) then
            self.notify(reason, "info", 4)
        end
    end

    --- Return input callbacks tied to a request rather than mutable controller state.
    local function input_options(request)
        return {
            prompt = request.prompt,
            items = { "Yes", "No" },
            default_item = 2,
            submit = function(index)
                if self.active ~= request then
                    return
                end
                if index == 1 then
                    accept_request(request)
                else
                    cancel_request(request, "Cancelled by the user.")
                end
            end,
            closed = function()
                request.closed = true
                cancel_request(request)
                if self.active ~= request then
                    return
                end
                self.active = nil
            end,
        }
    end

    ------------------------------------------------------------
    --- Public

    --- Return the configured prompt timeout in seconds.
    function public.get_confirmation_timeout()
        return CONFIRMATION_TIMEOUT_SECONDS
    end

    --- Cancel the active request with an optional reason.
    function public.cancel(reason)
        if self.active then
            cancel_request(self.active, reason)
        end
    end

    --- Present a Yes/No prompt unless another handler is active or still closing.
    function public.confirm(options)
        if self.active then
            return
        end
        local request = {
            prompt = options.prompt,
            on_accept = options.on_accept,
            resolved = false,
            closed = false,
        }
        self.active = request
        request.timer = mp_api.mp.add_timeout(CONFIRMATION_TIMEOUT_SECONDS, function()
            if self.active == request then
                cancel_request(request)
            end
        end)
        mp_api.input.select(input_options(request))
        mp_api.msg.warn(request.prompt)
    end

    return public
end

return { new = make_confirmation }
