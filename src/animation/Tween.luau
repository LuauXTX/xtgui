local Easing = require("./Easing")
local Style = require("../styling/Style")
local C = require("../layout/Constraints")
local Tween = {}
Tween.__index = Tween
local serial = 0
local allowed = {
    opacity = true,
    x = true,
    y = true,
    width = true,
    height = true,
    radius = true,
    borderWidth = true,
    background = true,
    color = true,
    borderColor = true,
    transform = true,
}
local colors = { background = true, color = true, borderColor = true }
local function copy(value)
    if type(value) == "table" then
        return table.clone(value)
    end
    return value
end
local function interpolate(a, b, t)
    if type(b) == "number" then
        return a + (b - a) * t
    end
    local result = {}
    for k, v in pairs(b) do
        result[k] = interpolate(a[k], v, t)
    end
    return result
end
local function shape(a, b, key)
    if type(b) == "number" then
        C.number(b, key)
        assert(type(a) == "number", "XTGUI tween requires numeric starting value for " .. key)
    else
        assert(type(a) == "table" and type(b) == "table", "XTGUI tween cannot interpolate " .. key)
        for k, v in pairs(b) do
            shape(a[k], v, key .. "." .. tostring(k))
        end
    end
end
function Tween.new(element, properties, options)
    assert(element and element.alive, "XTGUI tween needs a live element")
    assert(type(properties) == "table", "XTGUI tween properties must be a table")
    Style.validate(properties, "tween")
    options = options or {}
    serial += 1
    local easing = type(options.easing) == "function" and options.easing
        or Easing[options.easing or "easeOutCubic"]
    assert(easing, "XTGUI unknown easing: " .. tostring(options.easing))
    local duration = options.duration or 0.3
    local delay = options.delay or 0
    local repeats = options["repeat"] or 0
    C.number(duration, "tween duration", 0.000001, 86400)
    C.number(delay, "tween delay", 0, 86400)
    C.number(repeats, "tween repeat", -1, 100000)
    assert(repeats % 1 == 0, "XTGUI tween repeat must be an integer")
    local target = {}
    for key, value in pairs(properties) do
        assert(allowed[key], "XTGUI property cannot be tweened: " .. tostring(key))
        target[key] = colors[key] and Style.color(value) or copy(value)
    end
    assert(next(target), "XTGUI tween needs properties")
    local self = setmetatable({
        element = element,
        app = element.app,
        target = target,
        options = options,
        easing = easing,
        duration = duration,
        delay = delay,
        repeats = repeats,
        reverse = options.reverse == true,
        start = os.clock(),
        id = serial,
        status = "running",
    }, Tween)
    if self.app._animationWake then
        self.app._animationWake()
        self.app._animationWake = nil
    end
    self.app._tweens[self] = true
    self.app:_redraw()
    return self
end
function Tween:cancel()
    if self.status ~= "running" then
        return
    end
    self.status = "cancelled"
    self.app._tweens[self] = nil
    if not next(self.app._tweens) and self.app._animationWake then
        self.app._animationWake()
        self.app._animationWake = nil
    end
    if self.options.onCancel then
        self.options.onCancel(self)
    end
end
function Tween:_step(now)
    if self.status ~= "running" then
        return
    end
    local element = self.element
    if not element.alive then
        self:cancel()
        return
    end
    local elapsed = now - self.start - self.delay
    if elapsed < 0 then
        return
    end
    if not self.from then
        for other in pairs(self.app._tweens) do
            if other ~= self and other.from and other.element == element then
                for key in pairs(self.target) do
                    if other.target[key] ~= nil then
                        other:cancel()
                        break
                    end
                end
            end
        end
        self.from = {}
        element.data.animated = element.data.animated or {}
        for key, value in pairs(self.target) do
            local source = element.data.animated[key]
            if source == nil then
                source = element.style[key]
            end
            if source == nil and (key == "x" or key == "y") then
                source = 0
            end
            if source == nil and key == "width" then
                source = element.box.width
            elseif source == nil and key == "height" then
                source = element.box.height
            end
            if colors[key] then
                source = Style.color(source or "#00000000")
            end
            if key == "transform" then
                source = source or {}
                local defaults = { x = 0, y = 0, rotation = 0, scaleX = 1, scaleY = 1 }
                source = table.clone(source)
                for k in pairs(value) do
                    if source[k] == nil then
                        source[k] = defaults[k]
                    end
                end
            end
            shape(source, value, key)
            self.from[key] = copy(source)
        end
    end
    local cycle = self.duration * (self.reverse and 2 or 1)
    local complete = self.repeats >= 0 and elapsed >= cycle * (self.repeats + 1)
    local position = complete and (self.reverse and 0 or 1) or (elapsed % cycle) / self.duration
    if position > 1 then
        position = 2 - position
    end
    local amount = self.easing(math.clamp(position, 0, 1))
    C.number(amount, "easing result", -100, 100)
    for key, value in pairs(self.target) do
        element.data.animated[key] = interpolate(self.from[key], value, amount)
    end
    element.paintDirty = true
    self.app:_styles()
    if self.options.onUpdate then
        self.options.onUpdate(amount, self)
    end
    if complete then
        self.status = "completed"
        self.app._tweens[self] = nil
        if self.options.onComplete then
            self.options.onComplete(self)
        end
    end
end
function Tween.attach(Application)
    function Application:_tickAnimations(now)
        local tweens = {}
        for tween in pairs(self._tweens) do
            table.insert(tweens, tween)
        end
        table.sort(tweens, function(a, b)
            return a.id < b.id
        end)
        for _, tween in ipairs(tweens) do
            tween:_step(now)
        end
        if next(self._tweens) and not self._animationWake then
            local wait = math.huge
            for tween in pairs(self._tweens) do
                local remaining = tween.start + tween.delay - now
                wait = math.min(wait, remaining > 0 and remaining or 1 / 60)
            end
            self._animationWake = self:after(wait, function()
                self._animationWake = nil
                self:_redraw()
            end)
        end
    end
    function Application:_transition(node, before, target, equal)
        local config = node.props.transition
        if not config then
            return
        end
        if not before then
            node.data.transitionTarget = table.clone(target)
            return
        end
        assert(type(config) == "table", "XTGUI transition must be a table")
        local properties = config.properties or { "background", "color", "borderColor", "opacity" }
        local changed = {}
        local previous = node.data.transitionTarget
        for _, key in ipairs(properties) do
            assert(allowed[key], "XTGUI invalid transition property: " .. tostring(key))
            if
                target[key] ~= nil
                and before[key] ~= nil
                and previous
                and not equal(previous[key], target[key])
            then
                changed[key] = target[key]
            end
        end
        node.data.transitionTarget = table.clone(target)
        if next(changed) then
            node.data.animated = node.data.animated or {}
            for key in pairs(changed) do
                node.data.animated[key] = before[key]
            end
            local options = table.clone(config)
            local completed = options.onComplete
            options.onComplete = function(tween)
                for key in pairs(changed) do
                    node.data.animated[key] = nil
                end
                if completed then
                    completed(tween)
                end
            end
            Tween.new(node, changed, options)
        end
    end
end
return Tween
