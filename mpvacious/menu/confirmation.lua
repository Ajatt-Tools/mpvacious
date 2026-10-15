--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Present reusable Yes/No confirmations through mpv's console input.
]]

local mp = require("mp")
local input = require("mp.input")
local msg = require("mp.msg")

local CONFIRMATION_TIMEOUT_SECONDS = 20
local DEFAULT_MP_API = { input = input, msg = msg, mp = mp }

--- Return a stateful Yes/No confirmation controller with optional mp-compatible APIs.
--- Requests resolve once. Replacements open only after the previous input handler closes.
local function make_confirmation(mp_api)
    mp_api = mp_api or DEFAULT_MP_API
    local private = {
        -- The registered request remains active until its closed callback runs.
        active = nil,
        -- The latest replacement waiting for the old input handler to unregister.
        pending = nil,
    }
    local public = {}

    --- Resolve a request once and stop its timeout timer before invoking callbacks.
    local function resolve(request, was_accepted)
        if request.resolved then
            return
        end
        request.resolved = true
        if request.timer then
            request.timer:kill()
        end
        if was_accepted then
            request.on_accept()
        else
            request.on_cancel()
        end
    end

    --- Close the active request after its callback has resolved.
    local function close_request(request)
        if private.active ~= request or request.closed then
            return
        end
        request.closed = true
        mp_api.input.terminate()
    end

    --- Resolve and close a request, leaving any replacement queued.
    local function finish_request(request, was_accepted)
        if private.active ~= request then
            return
        end
        resolve(request, was_accepted)
        close_request(request)
    end

    --- Resolve and close the currently active request.
    local function finish_active(was_accepted)
        if private.active then
            finish_request(private.active, was_accepted)
        end
    end

    --- Return input callbacks tied to a request rather than mutable controller state.
    local function input_options(request)
        return {
            prompt = request.prompt,
            items = { "Yes", "No" },
            default_item = 2,
            submit = function(index) finish_request(request, index == 1) end,
            closed = function()
                resolve(request, false)
                if private.active ~= request then
                    return
                end
                private.active = nil
                mp_api.mp.add_timeout(0, function() private.open_pending() end)
            end,
        }
    end

    --- Open a request after mpv has unregistered its previous input handler.
    local function open_request(request)
        private.active = request
        request.timer = mp_api.mp.add_timeout(
            CONFIRMATION_TIMEOUT_SECONDS,
            function()
                finish_request(request, false)
            end
        )
        mp_api.input.select(input_options(request))
        mp_api.msg.warn(request.prompt)
    end

    --- Open the pending request only when no older input handler remains active.
    function private.open_pending()
        if private.active or not private.pending then
            return
        end
        local request = private.pending
        private.pending = nil
        open_request(request)
    end

    --- Cancel requests present at entry, preserving any newly queued reentrant request.
    local function cancel_confirmation()
        local pending = private.pending
        local active = private.active
        private.pending = nil
        if pending then
            resolve(pending, false)
        end
        if active and private.active == active then
            finish_request(active, false)
        end
        private.open_pending()
    end

    --- Queue a prompt, allowing cancellation callbacks to supersede it with a newer one.
    local function queue_confirmation(options)
        local previous = private.pending
        local incoming = {
            prompt = options.prompt,
            on_accept = options.on_accept,
            on_cancel = options.on_cancel,
            resolved = false,
            closed = false,
        }
        private.pending = incoming
        if previous then
            resolve(previous, false)
        end
        if private.pending ~= incoming then
            -- A cancellation callback queued a newer request. Latest wins.
            return
        end
        if private.active then
            finish_active(false)
        else
            private.open_pending()
        end
    end

    ------------------------------------------------------------
    --- Public

    function public.get_confirmation_timeout()
        return CONFIRMATION_TIMEOUT_SECONDS
    end

    --- Cancel active and queued confirmations, if any.
    function public.cancel()
        cancel_confirmation()
    end

    --- Present a Yes/No prompt and resolve it exactly once.
    function public.confirm(options)
        queue_confirmation(options)
    end

    return public
end

return { new = make_confirmation }
