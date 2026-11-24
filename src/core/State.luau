local Scheduler = require("./Scheduler")
local State = { owner = nil, tracking = nil, rendering = false }
local Value = {}; Value.__index = Value
local Computed = {}; Computed.__index = Computed
local function live(self) assert(not self.disposed, "XTGUI state/computed value has been disposed") end
local function track(self)
    if State.tracking then State.tracking[self] = self.version or 0 end
end
local function notify(self)
    local listeners = {}
    for listener in pairs(self.listeners) do table.insert(listeners, listener) end
    for _, listener in ipairs(listeners) do if listener.active ~= false then listener:invalidate() end end
end
function State.capture(callback)
    local previous = State.tracking
    local dependencies = {}
    State.tracking = dependencies
    local result = table.pack(pcall(callback))
    State.tracking = previous
    if not result[1] then error(result[2], 0) end
    return dependencies, table.unpack(result, 2, result.n)
end
function State.commitDependencies(observer, dependencies)
    for value in pairs(observer.dependencies or {}) do value.listeners[observer] = nil end
    observer.dependencies = dependencies
    for value in pairs(dependencies) do value.listeners[observer] = true end
end
function State.collect(observer, callback)
    local dependencies, result = State.capture(callback)
    State.commitDependencies(observer, dependencies)
    return result
end
function State.detach(observer)
    observer.active = false
    for value in pairs(observer.dependencies or {}) do value.listeners[observer] = nil end
    observer.dependencies = {}
end
function State.hook(kind, factory)
    local owner = State.owner
    if not owner then return factory() end
    owner.hookIndex += 1
    local index = owner.hookIndex
    local hook = owner.hooks[index]
    if hook then assert(hook.kind == kind, "XTGUI hook order changed in " .. owner.name); return hook.value end
    assert(not owner.hookCount, "XTGUI hook count changed in " .. owner.name)
    local value = factory(); owner.hooks[index] = { kind = kind, value = value }; return value
end
function State.new(initial)
    return State.hook("state", function() return setmetatable({ _xtguiState = true, value = initial, listeners = {} }, Value) end)
end
function Value:get() live(self); track(self); return self.value end
function Value:set(value)
    live(self); assert(not State.rendering, "XTGUI: state cannot be changed during component rendering")
    if self.value == value then return false end
    self.value = value; self.version = (self.version or 0) + 1
    Scheduler.batch(function() notify(self) end)
    return true
end
function Value:update(callback) return self:set(callback(self:get())) end
function Value:dispose()
    if self.disposed then return end
    self.disposed = true
    notify(self)
    self.listeners = {}
end
function State.is(value) return type(value) == "table" and value._xtguiState == true end
function State.read(value) if State.is(value) then return value:get() end; return value end
function State.computed(callback)
    return State.hook("computed", function()
        local self = setmetatable({ _xtguiState = true, callback = callback, listeners = {}, dirty = true, active = true }, Computed)
        return self
    end)
end
function Computed:invalidate()
    if self.disposed or self.dirty then return end
    self.dirty = true; self.version = (self.version or 0) + 1; notify(self)
end
function Computed:get()
    live(self); track(self)
    if self.dirty then
        assert(not self.evaluating, "XTGUI computed dependency cycle")
        self.evaluating = true
        local ok, result = pcall(function() return State.collect(self, self.callback) end)
        self.evaluating = false
        if not ok then error(result, 0) end
        self.value = result; self.dirty = false
    end
    return self.value
end
function Computed:dispose() if not self.disposed then State.detach(self); self.listeners = {}; self.disposed = true end end
local function subscribe(self, callback)
    live(self)
    local observer = { active = true }
    function observer:invalidate()
        Scheduler.enqueue(self, function() if self.active then callback(State.read(self.source)) end end)
    end
    observer.source = self
    self.listeners[observer] = true
    return function() observer.active = false; self.listeners[observer] = nil end
end
Value.subscribe = subscribe; Computed.subscribe = subscribe
function State.effect(callback)
    local effect = State.hook("effect", function()
        local self = { active = true, callback = callback }
        function self:run()
            if not self.active then return end
            if self.cleanup then local cleanup = self.cleanup; self.cleanup = nil; cleanup() end
            local cleanup = State.collect(self, self.callback)
            assert(cleanup == nil or type(cleanup) == "function", "XTGUI effect must return a cleanup function or nil")
            self.cleanup = cleanup
        end
        function self:invalidate() Scheduler.enqueue(self, function() self:run() end) end
        function self:dispose()
            if not self.active then return end
            State.detach(self)
            if self.cleanup then local cleanup = self.cleanup; self.cleanup = nil; cleanup() end
        end
        return self
    end)
    if State.owner then
        table.insert(State.owner.pendingEffects, { effect = effect, callback = callback })
    else effect:run() end
    return function() effect:dispose() end
end
function State.ref(initial) return State.hook("ref", function() return { current = initial } end) end
function State.cleanup(callback)
    assert(State.owner, "XTGUI onCleanup must be called inside a component")
    State.hook("cleanup", function() return { dispose = callback } end)
end
State.batch = Scheduler.batch
return State
