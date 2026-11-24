local Focus = {}
local Widgets = require("../components/Widgets")
Focus.__index = Focus
local defaults = {
    Button = true,
    IconButton = true,
    TextInput = true,
    TextArea = true,
    Checkbox = true,
    RadioButton = true,
    Switch = true,
    Slider = true,
}
function Focus.new(app)
    return setmetatable({ app = app, visible = false }, Focus)
end
function Focus:eligible(node)
    if
        not node
        or not node.alive
        or node.disabled
        or not node.style
        or type(node.kind) ~= "string"
    then
        return false
    end
    local ancestor = node
    while ancestor do
        if ancestor.style.display == "none" then
            return false
        end
        ancestor = ancestor.parent
    end
    if node.props.focusable == false then
        return false
    end
    return node.props.focusable == true or defaults[node.kind] == true or node.props.tabIndex ~= nil
end
function Focus:trap()
    local trap
    for _, node in ipairs(self.app._visual) do
        if node.props.focusTrap and node.alive then
            trap = node
        end
    end
    return trap
end
function Focus:set(node, visible)
    if node and (not self:eligible(node) or (self:trap() and not self:trap():contains(node))) then
        return false
    end
    self.visible = visible == nil and self.visible or visible
    if self.current == node then
        self.app:_redraw()
        return true
    end
    local previous = self.current
    self.current = node
    if previous then
        if previous.data.editor then
            previous.data.editor.composition = ""
        end
        previous.interaction.focused = false
        self.app.input:emit("blur", previous, { relatedTarget = node })
        previous.paintDirty = true
    end
    if node then
        node.interaction.focused = true
        node.paintDirty = true
        self.app.input:emit("focus", node, { relatedTarget = previous })
    end
    self.app:_styles()
    self.app:_ime()
    self.app:_caretTimer()
    return true
end
function Focus:tab(reverse)
    local nodes = {}
    local trap = self:trap()
    local groups = {}
    for _, node in ipairs(self.app._visual) do
        if
            node.kind == "RadioButton"
            and node.props.group
            and self:eligible(node)
            and (not trap or trap:contains(node))
        then
            if not groups[node.props.group] or Widgets.value(node, "checked", false) then
                groups[node.props.group] = node
            end
        end
    end
    for _, node in ipairs(self.app._visual) do
        if
            self:eligible(node)
            and (node.props.tabIndex or 0) >= 0
            and (not trap or trap:contains(node))
        then
            if
                node.kind ~= "RadioButton"
                or node.props.group == nil
                or groups[node.props.group] == node
            then
                table.insert(nodes, node)
            end
        end
    end
    table.sort(nodes, function(a, b)
        local ai = a.props.tabIndex or 0
        local bi = b.props.tabIndex or 0
        if ai ~= bi then
            if ai == 0 then
                return false
            elseif bi == 0 then
                return true
            else
                return ai < bi
            end
        end
        return a.paintOrder < b.paintOrder
    end)
    local index = reverse and 1 or 0
    for i, node in ipairs(nodes) do
        if node == self.current then
            index = i
            break
        end
    end
    if #nodes > 0 then
        self:set(nodes[(index + (reverse and -1 or 1) - 1) % #nodes + 1], true)
        self:reveal()
    end
end
function Focus:reveal()
    local node = self.current
    if not node then
        return
    end
    local b = node.box
    local parent = node.parent
    while parent do
        if parent.kind == "ScrollView" then
            local p = parent.style.padding
            local viewport = {
                x = parent.box.x + p.left,
                y = parent.box.y + p.top,
                width = parent.box.width - p.left - p.right,
                height = parent.box.height - p.top - p.bottom,
            }
            local dx = b.x < viewport.x and b.x - viewport.x
                or math.max(0, b.x + b.width - viewport.x - viewport.width)
            local dy = b.y < viewport.y and b.y - viewport.y
                or math.max(0, b.y + b.height - viewport.y - viewport.height)
            self.app:_scroll(
                parent,
                (parent.data.scrollX or 0) + dx,
                (parent.data.scrollY or 0) + dy
            )
        end
        parent = parent.parent
    end
end
return Focus
