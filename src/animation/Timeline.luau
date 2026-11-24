local Tween = require("./Tween")
local C = require("../layout/Constraints")
local Timeline = {}
Timeline.__index = Timeline
function Timeline.new()
    return setmetatable({ steps = {}, cursor = 0, tweens = {}, status = "idle" }, Timeline)
end
function Timeline:to(element, properties, options, at)
    assert(self.status == "idle", "XTGUI timeline is already playing")
    options = table.clone(options or {})
    assert(options["repeat"] ~= -1, "XTGUI timeline cannot contain an infinite tween")
    at = at or self.cursor
    C.number(at, "timeline position", 0, 86400)
    local length = (options.duration or 0.3)
            * (options.reverse and 2 or 1)
            * ((options["repeat"] or 0) + 1)
        + (options.delay or 0)
    options.delay = (options.delay or 0) + at
    table.insert(self.steps, { element = element, properties = properties, options = options })
    self.cursor = math.max(self.cursor, at + length)
    return self
end
function Timeline:wait(seconds)
    C.number(seconds, "timeline wait", 0, 86400)
    self.cursor += seconds
    return self
end
function Timeline:parallel(steps)
    local at = self.cursor
    for _, step in ipairs(steps) do
        self:to(step.element, step.properties, step.options, at)
    end
    return self
end
function Timeline:play(options)
    assert(self.status == "idle", "XTGUI timeline can only play once")
    options = options or {}
    self.status = "running"
    local remaining = #self.steps
    if remaining == 0 then
        self.status = "completed"
        if options.onComplete then
            options.onComplete(self)
        end
        return self
    end
    local ok, reason = pcall(function()
        for _, step in ipairs(self.steps) do
            local opts = table.clone(step.options)
            local completed = opts.onComplete
            local cancelled = opts.onCancel
            opts.onComplete = function(tween)
                if completed then
                    completed(tween)
                end
                remaining -= 1
                if remaining == 0 and self.status == "running" then
                    self.status = "completed"
                    if options.onComplete then
                        options.onComplete(self)
                    end
                end
            end
            opts.onCancel = function(tween)
                if cancelled then
                    cancelled(tween)
                end
                if self.status == "running" then
                    self:cancel()
                end
            end
            table.insert(self.tweens, Tween.new(step.element, step.properties, opts))
        end
    end)
    if not ok then
        self:cancel()
        error(reason, 0)
    end
    return self
end
function Timeline:cancel()
    if self.status == "cancelled" or self.status == "completed" then
        return
    end
    self.status = "cancelled"
    for _, tween in ipairs(self.tweens) do
        tween:cancel()
    end
end
return Timeline
