local Paint = require("./Paint")
local Style = require("../styling/Style")
local G = require("./Geometry")
local Visual = require("../input/VisualTree")
local Renderer = {}
local function canvas(frame, node)
    local clips, transforms = 0, 0
    local proxy = { deltaTime = frame.deltaTime }
    for _, op in ipairs({ "rect", "line", "image", "text" }) do
        proxy[op] = function(_, props)
            return frame[op](frame, props)
        end
    end
    function proxy:pushClip(p)
        frame:pushClip(p)
        clips += 1
    end
    function proxy:popClip()
        assert(clips > 0, "XTGUI Canvas clip underflow")
        frame:popClip()
        clips -= 1
    end
    function proxy:pushTransform(p)
        frame:pushTransform(p)
        transforms += 1
    end
    function proxy:popTransform()
        assert(transforms > 0, "XTGUI Canvas transform underflow")
        frame:popTransform()
        transforms -= 1
    end
    local ok, err = pcall(node.props.onPaint, proxy, node:getBounds(), node)
    while clips > 0 do
        frame:popClip()
        clips -= 1
    end
    while transforms > 0 do
        frame:popTransform()
        transforms -= 1
    end
    if not ok then
        error("XTGUI Canvas " .. tostring(node.props.id or node.id) .. ": " .. tostring(err), 0)
    end
end
function Renderer.draw(app, frame)
    local color = Style.color(app.theme.colors.background)
    frame:clear(table.unpack(color))
    local stats = { nodes = 0, commands = 0, cached = 0 }
    local viewport = { x = 0, y = 0, width = app.width, height = app.height }
    local visit
    visit = function(node, alpha, portal)
        if
            node.style.display == "none"
            or node.box.width <= 0
            or node.box.height <= 0
            or (node.props.portal and not portal)
        then
            return
        end
        alpha *= node.style.opacity
        node._paintAlpha = alpha
        local transform = node.style.transform
        local transformed = transform ~= nil
        if transformed then
            frame:pushTransform({
                x = node.box.x + (transform.x or 0),
                y = node.box.y + (transform.y or 0),
                rotation = transform.rotation or 0,
                scaleX = transform.scaleX or 1,
                scaleY = transform.scaleY or 1,
            })
            frame:pushTransform({ x = -node.box.x, y = -node.box.y })
        end
        if alpha > 0 and G.overlaps(G.aabb(node.box, node.world), viewport) then
            stats.nodes += 1
            if not node.paintDirty then
                stats.cached += 1
            end
            for _, command in ipairs(Paint.commands(node)) do
                if command.props then
                    local props = command.props
                    if props.color and alpha ~= 1 then
                        props = table.clone(props)
                        props.color = Style.color(props.color, alpha)
                    end
                    frame[command.op](frame, props)
                else
                    frame[command.op](frame)
                end
                stats.commands += 1
            end
            if node.kind == "Canvas" then
                frame:pushClip(node.box)
                canvas(frame, node)
                frame:popClip()
            end
        end
        local clip = node.style.overflow == "hidden" or node.kind == "ScrollView"
        if clip then
            frame:pushClip(node.box)
        end
        for _, child in ipairs(Visual.sorted(node.children)) do
            visit(child, alpha, false)
        end
        if clip then
            frame:popClip()
        end
        if transformed then
            frame:popTransform()
            frame:popTransform()
        end
    end
    if app.root then
        visit(app.root, 1, false)
    end
    for _, node in ipairs(app._portals) do
        local alpha = 1
        local parent = node.parent
        while parent do
            alpha *= parent.style.opacity
            parent = parent.parent
        end
        visit(node, alpha, true)
    end
    app.diagnostics.paint = stats
    app.diagnostics.frames += 1
end
return Renderer
