local Element = {}
local State = require("./State")
Element.__index = Element
local serial = 0
function Element.new(kind, app)
    serial += 1
    return setmetatable({
        id = serial,
        kind = kind,
        name = type(kind) == "table" and kind.name or tostring(kind),
        app = app,
        children = {},
        props = {},
        rawProps = {},
        data = {},
        hooks = {},
        pendingEffects = {},
        dirty = true,
        paintDirty = true,
        layoutDirty = true,
        active = true,
        alive = true,
        interaction = {},
        box = { x = 0, y = 0, width = 0, height = 0 },
        dependencies = {},
        renderCount = 0,
    }, Element)
end
function Element:invalidate()
    if self.alive then
        self.dirty = true
        local parent = self.parent
        while parent do
            parent.subtreeDirty = true
            parent = parent.parent
        end
        self.app:_queue(self)
    end
end
function Element:setProps(properties)
    assert(self.alive, "XTGUI element was destroyed: " .. self.name)
    assert(not State.rendering, "XTGUI setProps cannot run during component rendering")
    assert(type(properties) == "table", "XTGUI setProps expects a table")
    assert(
        properties.key == nil or properties.key == self.key,
        "XTGUI setProps cannot change an element's key"
    )
    local props = table.clone(self._nextDescriptor and self._nextDescriptor.props or self.rawProps)
    self._clearAnimated = self._clearAnimated or {}
    for key, value in pairs(properties) do
        props[key] = value
        self._clearAnimated[key] = true
    end
    self._nextDescriptor = { type = self.kind, props = props, key = self.key }
    self:invalidate()
    return self
end
function Element:destroy()
    assert(not State.rendering, "XTGUI destroy cannot run during component rendering")
    self.app:_remove(self)
end
function Element:focus()
    assert(not State.rendering, "XTGUI focus belongs in an event or effect")
    return self.app.focus:set(self)
end
function Element:scrollTo(x, y)
    return self.app:_scroll(self, x, y)
end
function Element:capturePointer()
    return self.app.input:capture(self)
end
function Element:releasePointer()
    return self.app.input:release(self)
end
function Element:getBounds()
    return table.clone(self.box)
end
function Element:getChildren()
    return table.clone(self.children)
end
function Element:find(key)
    if type(self.kind) == "string" and self.props.id == key then
        return self
    end
    for _, child in ipairs(self.children) do
        local found = child:find(key)
        if found then
            return found
        end
    end
end
function Element:findKey(key)
    if self.key == key then
        return self
    end
    for _, child in ipairs(self.children) do
        local found = child:findKey(key)
        if found then
            return found
        end
    end
end
function Element:contains(other)
    while other do
        if other == self then
            return true
        end
        other = other.parent
    end
    return false
end
return Element
