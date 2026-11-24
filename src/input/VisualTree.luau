local G = require("../rendering/Geometry")
local V = {}
function V.sorted(children)
    local result = {}
    for i, node in ipairs(children) do
        table.insert(result, { node = node, index = i })
    end
    table.sort(result, function(a, b)
        local az = a.node.style.zIndex or 0
        local bz = b.node.style.zIndex or 0
        return az < bz or (az == bz and a.index < b.index)
    end)
    local nodes = {}
    for _, item in ipairs(result) do
        table.insert(nodes, item.node)
    end
    return nodes
end
function V.update(app)
    local portals = {}
    local layers = {}
    local function collect(node, base, pointerDisabled)
        if node.style.display == "none" then
            return
        end
        local disabled = pointerDisabled or node.props.pointerEvents == "none"
        if node.props.portal then
            base += (node.style.zIndex or 0)
            table.insert(
                layers,
                { node = node, z = base, order = #layers + 1, pointerDisabled = pointerDisabled }
            )
        end
        for _, child in ipairs(V.sorted(node.children)) do
            collect(child, base, disabled)
        end
    end
    if app.root then
        collect(app.root, 0, false)
    end
    table.sort(layers, function(a, b)
        return a.z < b.z or (a.z == b.z and a.order < b.order)
    end)
    local entries = {}
    local order = 0
    local function visit(node, parentWorld, clips, portal, pointerDisabled)
        if node.style.display == "none" then
            return
        end
        if node.props.portal and not portal then
            return
        end
        local localMatrix = G.transform(node.box, node.style.transform)
        node.world = G.multiply(parentWorld, localMatrix)
        node.inverse = G.inverse(node.world)
        node.clips = clips
        node.pointerDisabled = pointerDisabled or node.props.pointerEvents == "none"
        if node.box.width > 0 and node.box.height > 0 then
            order += 1
            node.paintOrder = order
            table.insert(entries, node)
        end
        local childClips = clips
        if
            node.style.overflow == "hidden"
            or node.kind == "ScrollView"
            or node.kind == "TextInput"
            or node.kind == "TextArea"
        then
            childClips = table.clone(clips)
            table.insert(childClips, G.polygon(node.box, node.world))
        end
        for _, child in ipairs(V.sorted(node.children)) do
            visit(child, node.world, childClips, false, node.pointerDisabled)
        end
    end
    if app.root then
        visit(app.root, G.identity, {}, false)
    end
    for _, layer in ipairs(layers) do
        table.insert(portals, layer.node)
        visit(layer.node, G.identity, {}, true, layer.pointerDisabled)
    end
    app._visual = entries
    app._portals = portals
end
function V.hit(app, x, y)
    for i = #app._visual, 1, -1 do
        local node = app._visual[i]
        if not node.pointerDisabled and node.inverse then
            local lx, ly = G.point(node.inverse, x, y)
            local b = node.box
            local inside = lx >= b.x and ly >= b.y and lx < b.x + b.width and ly < b.y + b.height
            if inside then
                for _, clip in ipairs(node.clips) do
                    if not G.contains(clip, x, y) then
                        inside = false
                        break
                    end
                end
            end
            if inside and type(node.kind) == "string" then
                return node, lx, ly
            end
        end
    end
end
return V
