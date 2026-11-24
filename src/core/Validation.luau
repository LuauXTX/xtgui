local Layout = require("../layout/LayoutEngine")
local Backend = require("../rendering/Backend")
local Validation = {}

-- A reusable, non-interactive layout mirror validates the candidate BEFORE unmounts.
-- It shares immutable props/measurement results, never hooks, refs or mutable boxes.
function Validation.run(app, plan)
    if not plan then
        return
    end
    local started = os.clock()
    local count = 0
    app._validationCache = app._validationCache or {}
    local candidate = {
        options = app.options,
        width = app.width,
        height = app.height,
        theme = app.theme,
        _afterLayout = {},
        preflight = true,
        diagnostics = { layouts = 0 },
    }
    local clone
    clone = function(node, item, parent)
        if not item and node == plan.node then
            item = plan
        end
        local changed = item and not item.reuse
        local shadow = app._validationCache[node] or { children = {}, data = {}, box = {} }
        if node.descriptor then
            app._validationCache[node] = shadow
        end
        count += 1
        shadow.id = node.id
        shadow.kind = node.kind
        shadow.app = candidate
        shadow.parent = parent
        shadow.props = changed and item.props or node.props
        shadow.interaction = node.interaction
        shadow.style = node.style
        shadow.layoutDirty = changed or node.layoutDirty
        shadow.measureCache = not changed and node.measureCache or nil
        for k, v in pairs(node.box) do
            shadow.box[k] = v
        end
        shadow.data.animated = node.data.animated
        if changed and shadow.data.animated and node._clearAnimated then
            shadow.data.animated = table.clone(shadow.data.animated)
            for key in pairs(node._clearAnimated) do
                shadow.data.animated[key] = nil
            end
        end
        shadow.data.scrollX = node.data.scrollX
        shadow.data.scrollY = node.data.scrollY
        table.clear(shadow.children)
        if changed then
            for _, childPlan in ipairs(item.children) do
                table.insert(shadow.children, clone(childPlan.node, childPlan, shadow))
            end
        else
            for _, child in ipairs(node.children) do
                table.insert(shadow.children, clone(child, nil, shadow))
            end
        end
        return shadow
    end
    local rootPlan
    if not app.root then
        rootPlan = plan
    end
    candidate.root = clone(app.root or plan.node, rootPlan, nil)
    Layout.run(candidate)
    local function resources(node)
        if node.kind == "TextInput" or node.kind == "TextArea" then
            Backend.font(app, node.style)
        end
        for _, child in ipairs(node.children) do
            resources(child)
        end
    end
    resources(candidate.root)
    app.diagnostics.preflightTime = os.clock() - started
    app.diagnostics.preflightNodes = count
end
return Validation
