local Backend = require("../rendering/Backend")
local Renderer = require("../rendering/Renderer")
local Text = require("../rendering/TextLayout")
local G = require("../rendering/Geometry")
local Theme = require("../styling/Theme")
local Style = require("../styling/Style")
local C = require("../layout/Constraints")
local Layout = require("../layout/LayoutEngine")
local Visual = require("../input/VisualTree")
local Focus = require("../input/FocusManager")
local Input = require("../input/EventDispatcher")
local W = require("../components/Widgets")
local Component = require("./Component")
local R = require("./Reconciler")
local Scheduler = require("./Scheduler")
local State = require("./State")
local Validation = require("./Validation")
local Diagnostics = require("./Diagnostics")
local Application = {}
Application.__index = Application
function Application.new(options, api)
    assert(not State.rendering, "XTGUI createApp must be called outside component rendering")
    options = options or {}
    C.number(options.width or 800, "window width", 1, 16384)
    C.number(options.height or 600, "window height", 1, 16384)
    if options.clipboard then
        assert(
            type(options.clipboard.get) == "function" and type(options.clipboard.set) == "function",
            "XTGUI clipboard requires get and set functions"
        )
    end
    local self = setmetatable({
        options = options,
        api = api,
        width = options.width or 800,
        height = options.height or 600,
        theme = Theme.resolve(options.theme),
        _pending = {},
        _effects = {},
        _afterCommit = {},
        _afterLayout = {},
        _visual = {},
        _portals = {},
        _timers = {},
        _tweens = {},
        _needsLayout = true,
        _needsStyles = true,
        diagnostics = { frames = 0, layouts = 0, updates = 0, dirtyRegions = {} },
        _caretVisible = true,
    }, Application)
    self.focus = Focus.new(self)
    self.input = Input.new(self)
    self._viewport = State.new({ width = self.width, height = self.height })
    self._rootComponent = Component.new(function()
        return self._render(api)
    end, "Application")
    Backend.acquire()
    return self
end
function Application:_live()
    assert(not self.destroyed, "XTGUI application was destroyed")
end
function Application:_markDirty(box)
    if not box or box.width <= 0 or box.height <= 0 then
        return
    end
    local regions = self.diagnostics.dirtyRegions
    table.insert(regions, table.clone(box))
    if #regions > 32 then
        self.diagnostics.dirtyRegions =
            { { x = 0, y = 0, width = self.width, height = self.height } }
    end
end
function Application:_redraw(node)
    self._dirty = true
    if node then
        self:_markDirty(node.box)
    elseif #self.diagnostics.dirtyRegions == 0 then
        self:_markDirty({ x = 0, y = 0, width = self.width, height = self.height })
    end
    if self.window and self._ready and not self.closed and self.window:isOpen() then
        self.window:requestRedraw()
    end
end
function Application:_queue(node)
    Diagnostics.record(self, "component invalidated", node)
    self._pending[node] = true
    self:_redraw(node)
end
function Application:_queueEffect(effect)
    if self.destroyed or not effect.active then
        return
    end
    Diagnostics.record(self, "effect invalidated", effect)
    self._effects[effect] = true
    self:_redraw()
end
function Application:_styles()
    Diagnostics.record(self, "styles invalidated")
    self._needsStyles = true
    self:_redraw()
end
function Application:_layout(node)
    Diagnostics.record(self, "layout invalidated", node)
    while node do
        node.layoutDirty = true
        node.measureCache = nil
        node = node.parent
    end
    self._needsLayout = true
    self:_redraw()
end
function Application:_preflight(plan)
    Validation.run(self, plan)
end
function Application:render(callback)
    assert(not State.rendering, "XTGUI render cannot be called from a component render")
    self:_live()
    assert(
        type(callback) == "function" or type(callback) == "table",
        "XTGUI render expects a function or descriptor"
    )
    local old = self._render
    self._render = type(callback) == "function" and callback
        or function()
            return callback
        end
    local ok, err = pcall(function()
        if self.root then
            self.root.dirty = true
            self:_queue(self.root)
        else
            local plan = R.prepare(self, nil, self._rootComponent({}))
            self.root = R.commit(self, plan)
            self:_layout(self.root)
            self._needsStyles = true
        end
        self:flush()
    end)
    if not ok then
        self._render = old
        error(err, 0)
    end
    return self
end
function Application:flush()
    self:_live()
    if self._flushing then
        return
    end
    self._flushing = true
    local trace = Diagnostics.begin(self)
    local ok, err = pcall(function()
        for pass = 1, 100 do
            trace.pass = pass
            trace.phase = "scheduler"
            Scheduler.flush()
            local pending = self._pending
            self._pending = {}
            for node in pairs(pending) do
                local ancestor = node.parent
                local covered = false
                while ancestor do
                    if pending[ancestor] then
                        covered = true
                        break
                    end
                    ancestor = ancestor.parent
                end
                if node.alive and not covered then
                    trace.phase = "reconcile " .. Diagnostics.node(node)
                    node.dirty = true
                    local prepared, plan =
                        pcall(R.prepare, self, node, node._nextDescriptor or node.descriptor)
                    if not prepared then
                        node._nextDescriptor = nil
                        node._clearAnimated = nil
                        node.dirty = false
                        error(plan, 0)
                    end
                    R.commit(self, plan, node.parent)
                    self:_layout(node)
                    self._needsStyles = true
                    self.diagnostics.updates += 1
                end
            end
            local callbacks = self._afterCommit
            trace.phase = "commit callbacks"
            self._afterCommit = {}
            for _, callback in ipairs(callbacks) do
                callback()
            end
            Scheduler.flush()
            if self._needsLayout or self._needsStyles then
                trace.phase = "layout"
                -- Consume this pass's work even for an empty application. New
                -- invalidations during layout/callbacks belong to the next pass.
                self._needsLayout = false
                self._needsStyles = false
                Layout.run(self)
                Visual.update(self)
                local after = self._afterLayout
                self._afterLayout = {}
                for _, callback in ipairs(after) do
                    callback()
                end
                Scheduler.flush()
                if self.focus.current and not self.focus:eligible(self.focus.current) then
                    self.focus:set(nil)
                end
                self.focus:syncTraps()
            end
            -- Component effects see committed layout, and a dependency change
            -- plus a props change schedules only one run in this pass.
            trace.phase = "effects"
            local effects = self._effects
            self._effects = {}
            for effect in pairs(effects) do
                Scheduler.enqueue(effect, function()
                    effect:run()
                end)
            end
            Scheduler.flush()
            if
                not next(self._pending)
                and not next(self._effects)
                and #self._afterCommit == 0
                and #self._afterLayout == 0
                and not self._needsLayout
                and not self._needsStyles
            then
                break
            end
            if pass == 100 then
                error(Diagnostics.report(self), 0)
            end
        end
    end)
    self._flushing = false
    self.diagnostics.flushPasses = trace.pass
    self.diagnostics.invalidationCount = trace.total
    self._flushTrace = nil
    if not ok then
        error(err, 0)
    end
end
function Application:_unmounted(node)
    if self._validationCache then
        self._validationCache[node] = nil
    end
    self._pending[node] = nil
    if self.focus.current == node then
        self.focus.current = nil
        self:_caretTimer()
    end
    if self.input.captured == node or self.input.pressed == node then
        self.input:cancel()
    end
    if self.input.hovered == node then
        self.input.hovered = nil
    end
    for tween in pairs(self._tweens) do
        if tween.element == node then
            tween:cancel()
        end
    end
end
function Application:_remove(node)
    self:_live()
    assert(node.app == self, "XTGUI element belongs to another application")
    local parent = node.parent
    if parent then
        local index = table.find(parent.children, node)
        if index then
            table.remove(parent.children, index)
        end
    else
        self.root = nil
    end
    R.destroy(node)
    self:_layout(parent)
    self:_redraw()
end
function Application:find(key)
    self:_live()
    return self.root and self.root:find(key)
end
function Application:loadFont(path, size)
    self:_live()
    return Backend.font(self, { fontPath = path, fontSize = size or 16 })
end
function Application:loadImage(path)
    self:_live()
    return Backend.image(path)
end
function Application:invalidate(element)
    self:_live()
    if element then
        assert(element.alive and element.app == self, "XTGUI invalid element")
        element.paintDirty = true
    end
    self:_redraw(element)
end
function Application:_scroll(node, x, y)
    if not node.alive or node.kind ~= "ScrollView" then
        return false
    end
    C.number(x, "scroll x")
    C.number(y, "scroll y")
    local b = node.box
    local p = node.style.padding
    local w = b.width - p.left - p.right
    local h = b.height - p.top - p.bottom
    x = math.clamp(x, 0, math.max(0, (node.contentWidth or w) - w))
    y = math.clamp(y, 0, math.max(0, (node.contentHeight or h) - h))
    if x == (node.data.scrollX or 0) and y == (node.data.scrollY or 0) then
        return false
    end
    node.data.scrollX = x
    node.data.scrollY = y
    self:_layout(node)
    if node.props.onScroll then
        node.props.onScroll({ x = x, y = y, viewportWidth = w, viewportHeight = h }, node)
    end
    return true
end
function Application:dispatch(event)
    self:_live()
    self:flush()
    event = table.clone(event)
    event.synthetic = true
    self.input:dispatch(event)
    self:flush()
    return self
end
function Application:shortcut(chord, callback)
    self:_live()
    return self.input:shortcut(chord, callback)
end
function Application:setTheme(theme)
    self:_live()
    self.theme = Theme.resolve(theme)
    self:_styles()
    return self
end
function Application:resize(width, height)
    self:_live()
    C.number(width, "width", 1, 16384)
    C.number(height, "height", 1, 16384)
    if self.width == width and self.height == height then
        return self
    end
    self.width = width
    self.height = height
    if self.root then
        self:_layout(self.root)
    end
    local viewport = self._viewport:get()
    if viewport.width ~= width or viewport.height ~= height then
        self._viewport:set({ width = width, height = height })
    end
    if self.window then
        self.window:setSize(width, height)
    end
    return self
end
function Application:after(seconds, callback)
    self:_live()
    C.number(seconds, "timer delay", 0, 86400)
    assert(type(callback) == "function", "XTGUI after expects a callback")
    local timer = { active = true, deadline = os.clock() + seconds }
    self._timers[timer] = true
    local function cancel()
        timer.active = false
        self._timers[timer] = nil
    end
    local task = require("@luauxtx/async/task")
    local function tick()
        if not timer.active or self.destroyed or self.closed then
            cancel()
            return
        end
        local remaining = timer.deadline - os.clock()
        if remaining > 0 then
            task.delay(math.min(0.05, remaining), tick)
        else
            cancel()
            self:_guard(function()
                callback(self)
            end)
        end
    end
    task.delay(math.min(0.05, seconds), tick)
    return cancel
end
function Application:_caretTimer()
    if self._cancelCaret then
        self._cancelCaret()
        self._cancelCaret = nil
    end
    self._caretVisible = true
    local node = self.focus.current
    if
        self._ready
        and not self.closed
        and self.focus.windowFocused ~= false
        and node
        and (node.kind == "TextInput" or node.kind == "TextArea")
    then
        local function blink()
            if not node.alive or self.focus.current ~= node then
                return
            end
            self._caretVisible = not self._caretVisible
            node.paintDirty = true
            self:_redraw()
            self._cancelCaret = self:after(0.5, blink)
        end
        node.paintDirty = true
        self._cancelCaret = self:after(0.5, blink)
    end
end
function Application:_ime()
    if not self.window or not self._ready or self.closed then
        return
    end
    local node = self.focus.current
    local editable = node
        and (node.kind == "TextInput" or node.kind == "TextArea")
        and not node.props.readOnly
    self.window:setImeEnabled(editable == true)
    if editable then
        local editor, layout = self.input:editorLayout(node)
        local _, caret = editor:display(node.props.password)
        local x, y = Text.caret(layout, caret)
        local pad = node.style.padding
        x, y = G.point(
            node.world,
            node.box.x + pad.left + x - editor.scrollX,
            node.box.y + pad.top + y - editor.scrollY
        )
        self.window:setImePosition(x, y, 1, layout.lineHeight)
    end
end
function Application:_guard(callback)
    local ok, err = pcall(callback)
    if not ok then
        self.lastError = tostring(err)
        if self.options.onError then
            local handled, reason = pcall(self.options.onError, self.lastError, self)
            if not handled then
                self.lastError ..= "\nonError: " .. tostring(reason)
                self:close()
            end
        else
            self:close()
        end
        if self._inFrame then
            self:close()
        end
    end
    return ok
end
function Application:_start()
    self:_live()
    assert(not self.window, "XTGUI application has already run")
    self.closed = false
    local o = self.options
    self.window = Backend.native().createWindow({
        title = o.title or "XTGUI",
        width = self.width,
        height = self.height,
        resizable = o.resizable ~= false,
        visible = o.visible ~= false,
        vsync = o.vsync ~= false,
        continuous = false,
        closeOnRequest = false,
    })
    self.window:onEvent(function()
        self:_guard(function()
            self._ready = true
            for _, event in ipairs(self.window:pollEvents()) do
                if event.type == "resize" or event.type == "scale" then
                    self.width = event.width
                    self.height = event.height
                    if self.root then
                        self:_layout(self.root)
                    end
                    local viewport = self._viewport:get()
                    if viewport.width ~= self.width or viewport.height ~= self.height then
                        self._viewport:set({ width = self.width, height = self.height })
                    end
                    if o.onResize then
                        o.onResize(event, self)
                    end
                elseif event.type == "close" then
                    if not o.onClose or o.onClose(self) ~= false then
                        self:close()
                    end
                else
                    self:flush()
                    self.input:dispatch(event)
                end
                if self.closed then
                    break
                end
            end
        end)
    end)
    self.window:onFrame(function(dt)
        self:_guard(function()
            self._ready = true
            self.window:pollEvents()
            if not self._started then
                self._started = true
                if o.onReady then
                    o.onReady(self)
                end
            end
            if self.closed then
                return
            end
            if self._tickAnimations then
                self:_tickAnimations(os.clock())
            end
            self:flush()
            self:_ime()
            if not self._autoFocused then
                self._autoFocused = true
                for _, node in ipairs(self._visual) do
                    if node.props.autoFocus then
                        self.focus:set(node, true)
                        break
                    end
                end
            end
            self._inFrame = true
            self.diagnostics.lastDirtyRegions = self.diagnostics.dirtyRegions
            self.diagnostics.dirtyRegions = {}
            local frame = self.window:beginFrame()
            Renderer.draw(self, frame)
            self.window:endFrame()
            self._inFrame = false
            self._dirty = false
            if o.onFrame then
                o.onFrame(dt, self)
            end
        end)
    end)
end
function Application:close()
    if self.closed then
        return
    end
    self.closed = true
    for timer in pairs(self._timers) do
        timer.active = false
    end
    self._timers = {}
    self.input:release()
    if self.window then
        self.window:close()
    end
end
function Application:destroy()
    if self.destroyed then
        return
    end
    self:close()
    self._destroying = true
    if self.root then
        R.destroy(self.root)
        self.root = nil
    end
    self.destroyed = true
    self._validationCache = {}
    self.focus.trapRestore = {}
    self._viewport:dispose()
    self._visual = {}
    self._pending = {}
    self._effects = {}
    self._afterCommit = {}
    self._afterLayout = {}
    Backend.release()
    Text.clear()
    if self._cleanupErrors and #self._cleanupErrors > 0 then
        error("XTGUI cleanup failures:\n" .. table.concat(self._cleanupErrors, "\n"), 0)
    end
end
function Application.runAll(apps)
    assert(type(apps) == "table" and #apps > 0, "XTGUI run requires applications")
    local ok, err = pcall(function()
        Backend.native().run(function()
            for _, app in ipairs(apps) do
                app:_start()
            end
        end)
    end)
    local failure
    for _, app in ipairs(apps) do
        failure = failure or (not app.options.onError and app.lastError)
        local cleaned, reason = pcall(function()
            app:destroy()
        end)
        if not cleaned then
            failure = failure or tostring(reason)
        end
    end
    if not ok then
        error("XTGUI native graphics: " .. tostring(err), 0)
    end
    if failure then
        error(failure, 0)
    end
end
function Application:run()
    Application.runAll({ self })
    return self
end
return Application
