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

--- Create an unopened prompt owning its state, timer, and input-handler lifecycle.
local function make_request(options, mp_api, on_closed)
    local self = {
        prompt = options.prompt,
        on_accept = options.on_accept,
        resolved = false,
        closed = false,
        notify = mp_api.notify or h.notify,
    }
    local public = {}

    --- Resolve once, stop the timer, and close this prompt.
    --- Return whether this call initiated prompt closure.
    local function resolve_and_close_request()
        if self.resolved then
            return false
        end
        self.resolved = true
        if self.timer then
            self.timer:kill()
        end
        if self.closed then
            return false
        end
        mp_api.input.terminate()
        return true
    end

    --- Accept once after resolving and requesting prompt closure.
    local function accept_request()
        if resolve_and_close_request() then
            self.on_accept()
        end
    end

    --- Return input callbacks closing over only this request's private lifecycle state.
    local function input_options()
        return {
            prompt = self.prompt,
            items = { "Yes", "No" },
            default_item = 2,
            submit = function(index)
                if index == 1 then
                    accept_request()
                else
                    public.cancel("Cancelled by the user.")
                end
            end,
            closed = function()
                if self.closed then
                    return
                end
                self.closed = true
                public.cancel()
                on_closed(public)
            end,
        }
    end

    ------------------------------------------------------------
    --- Public

    --- Cancel once, close any active prompt, and report an optional reason.
    function public.cancel(reason)
        if resolve_and_close_request() then
            self.notify(reason, "info", 4)
        end
    end

    --- Start the timer and input only after the controller has retained this request.
    function public.open()
        self.timer = mp_api.mp.add_timeout(CONFIRMATION_TIMEOUT_SECONDS, public.cancel)
        mp_api.input.select(input_options())
        mp_api.msg.warn(self.prompt)
    end

    return public
end

--- Return a controller that ignores new prompts until its active input handler closes.
local function make_confirmation(mp_api)
    mp_api = mp_api or DEFAULT_MP_API
    local self = { active_request = nil }
    local public = {}

    --- Release only the request whose input handler has closed.
    local function release_request(request)
        if self.active_request == request then
            self.active_request = nil
        end
    end

    ------------------------------------------------------------
    --- Public

    --- Return the configured prompt timeout in seconds.
    function public.get_confirmation_timeout()
        return CONFIRMATION_TIMEOUT_SECONDS
    end

    --- Cancel the active request with an optional reason.
    function public.cancel(reason)
        if self.active_request then
            self.active_request.cancel(reason)
        end
    end

    --- Present a Yes/No prompt unless another handler is active or still closing.
    function public.confirm(options)
        if not self.active_request then
            self.active_request = make_request(options, mp_api, release_request)
            self.active_request.open()
        end
    end

    return public
end

return { new = make_confirmation }
