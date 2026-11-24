local G = require("../rendering/Geometry")
local W = require("../components/Widgets")
local roles = {
    Text = "text",
    Button = "button",
    IconButton = "button",
    TextInput = "textbox",
    TextArea = "textbox",
    Checkbox = "checkbox",
    RadioButton = "radio",
    Switch = "switch",
    Slider = "slider",
    ProgressBar = "progressbar",
    Image = "image",
    Separator = "separator",
}
local Semantics = {}
function Semantics.snapshot(app)
    local function visit(node)
        if
            node.style.display == "none" or (type(node.kind) == "string" and node.props.ariaHidden)
        then
            return {}
        end
        local children = {}
        for _, child in ipairs(node.children) do
            for _, value in ipairs(visit(child)) do
                table.insert(children, value)
            end
        end
        local role = type(node.kind) == "string" and (node.props.role or roles[node.kind]) or nil
        if not role then
            return children
        end
        local p = node.props
        local entry = {
            id = p.id or tostring(node.id),
            role = role,
            label = p.ariaLabel or p.text or p.alt,
            disabled = node.disabled == true,
            focused = app.focus.current == node,
            focusable = app.focus:eligible(node),
            bounds = G.aabb(node.box, node.world or G.identity),
            children = children,
            selected = p.selected,
            expanded = p.expanded,
            level = p.level,
            itemCount = p.itemCount,
            activeDescendant = p.activeDescendant,
        }
        if node.kind == "TextInput" or node.kind == "TextArea" then
            if not p.password then
                entry.value = W.editor(node).text
            end
            entry.multiline = node.kind == "TextArea"
            entry.readOnly = p.readOnly
        elseif node.kind == "Checkbox" or node.kind == "RadioButton" or node.kind == "Switch" then
            entry.checked = W.value(node, "checked", false)
        elseif node.kind == "Slider" or node.kind == "ProgressBar" then
            entry.value = W.value(node, "value", 0)
            entry.min = p.min or 0
            entry.max = p.max or (node.kind == "ProgressBar" and 1 or 100)
        end
        return { entry }
    end
    app:flush()
    return {
        role = "application",
        label = app.options.title or "XTGUI",
        children = app.root and visit(app.root) or {},
    }
end
return Semantics
