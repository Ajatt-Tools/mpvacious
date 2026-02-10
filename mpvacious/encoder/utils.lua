--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Encoder utilities.
]]

local utils = require('mp.utils')
local msg = require('mp.msg')

local this = {}

local function fit_quality_percentage_to_range(quality, worst_val, best_val)
    local scaled = worst_val + (best_val - worst_val) * quality / 100
    -- Round to the nearest integer that's better in quality.
    if worst_val > best_val then
        return math.floor(scaled)
    end
    return math.ceil(scaled)
end

function this.quality_to_crf_avif(quality_value)
    -- Quality is from 0 to 100. For avif images CRF is from 0 to 63 and reversed.
    local worst_avif_crf = 63
    local best_avif_crf = 0
    return fit_quality_percentage_to_range(quality_value, worst_avif_crf, best_avif_crf)
end

function this.quality_to_jpeg_qscale(quality_value)
    local worst_jpeg_quality = 31
    local best_jpeg_quality = 2
    return fit_quality_percentage_to_range(quality_value, worst_jpeg_quality, best_jpeg_quality)
end

function this.toms(timestamp)
    --- Trim timestamp down to milliseconds.
    return string.format("%.3f", timestamp)
end

local function make_scale_filter(algorithm, width, height)
    -- algorithm is either "sinc" or "lanczos"
    -- Static image scaling uses "sinc", which is the best downscaling algorithm: https://stackoverflow.com/a/6171860
    -- Animated images use Lanczos, which is faster.
    return string.format(
            "scale='min(%d,iw)':'min(%d,ih)':flags=%s+accurate_rnd",
            width, height, algorithm
    )
end

function this.static_scale_filter(config)
    return make_scale_filter('sinc', config.snapshot_width, config.snapshot_height)
end

function this.animated_scale_filter(config)
    return make_scale_filter(
            'lanczos',
            config.animated_snapshot_width,
            config.animated_snapshot_height
    )
end

function this.make_loudnorm_targets(config)
    return string.format(
            'loudnorm=I=%s:LRA=%s:TP=%s:dual_mono=true',
            config.loudnorm_target,
            config.loudnorm_range,
            config.loudnorm_peak
    )
end

function this.parse_loudnorm(loudnorm_targets, json_extractor, loudnorm_consumer)
    local function warn()
        msg.warn('Failed to measure loudnorm stats, falling back on dynamic loudnorm.')
    end

    return function(success, result)
        local json
        if success and result.status == 0 then
            json = json_extractor(result.stdout, result.stderr)
        end

        if json == nil then
            warn()
            loudnorm_consumer(loudnorm_targets)
            return
        end

        local loudnorm_args = { loudnorm_targets }
        local function add_arg(name, val)
            -- loudnorm sometimes fails to gather stats for extremely short inputs.
            -- Simply omit the stat to fall back on dynamic loudnorm.
            if val ~= '-inf' and val ~= 'inf' then
                table.insert(loudnorm_args, string.format('%s=%s', name, val))
            else
                warn()
            end
        end

        local stats = utils.parse_json(json)
        add_arg('measured_I', stats.input_i)
        add_arg('measured_LRA', stats.input_lra)
        add_arg('measured_TP', stats.input_tp)
        add_arg('measured_thresh', stats.input_thresh)
        add_arg('offset', stats.target_offset)

        loudnorm_consumer(table.concat(loudnorm_args, ':'))
    end
end


return this
