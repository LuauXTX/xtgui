local C = require("./Constraints")
local Flex = require("./Flex")
local Grid = require("./Grid")
local Style = require("../styling/Style")
local Theme = require("../styling/Theme")
local Text = require("../rendering/TextLayout")
local Backend = require("../rendering/Backend")
local Geometry = require("../rendering/Geometry")
local State = require("../core/State")
local Diagnostics = require("../core/Diagnostics")
local L = {}
local function sameBounds(a, b)
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
end
local function layoutCallback(node, previous)
    if sameBounds(node.box, previous) then
        return
    end
    local bounds = table.clone(node.box)
    table.insert(node.app._afterLayout, function()
        if node.alive and node.props.onLayout then
            Diagnostics.call("onLayout " .. Diagnostics.node(node), function()
                node.props.onLayout(bounds, node, previous)
            end)
        end
    end)
end
local function equal(a, b, depth)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" or (depth or 0) > 8 then
        return false
    end
    for k, v in pairs(a) do
        if not equal(v, b[k], (depth or 0) + 1) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end
L.equal = equal
local delegate = {
    "width",
    "height",
    "minWidth",
    "maxWidth",
    "minHeight",
    "maxHeight",
    "margin",
    "flexGrow",
    "flexShrink",
    "flexBasis",
    "alignSelf",
    "position",
    "left",
    "right",
    "top",
    "bottom",
    "x",
    "y",
    "display",
}
function L.styles(node, parentStyle, theme, disabled)
    local ownTheme = type(node.kind) == "string" and node.props.theme
    node.theme = ownTheme and Theme.resolve(ownTheme, theme) or theme
    node.disabled = disabled or State.read(node.props.disabled) == true
    if type(node.kind) == "string" and node.app._transition then
        node.app:_transition(
            node,
            node.style,
            Style.resolve(node, parentStyle, node.theme, true),
            equal
        )
    end
    local style = Style.resolve(node, parentStyle, node.theme)
    local previous = node.style
    node.style = style
    for _, child in ipairs(node.children) do
        L.styles(child, style, node.theme, node.disabled)
        if child.layoutDirty then
            node.layoutDirty = true
            node.measureCache = nil
        end
    end
    if type(node.kind) == "table" and node.children[1] then
        for _, key in ipairs(delegate) do
            style[key] = node.children[1].style[key]
        end
    end
    if not equal(previous, style) then
        node.paintDirty = true
        node.layoutDirty = true
        node.measureCache = nil
    end
end
local function flow(node)
    local result = {}
    for _, child in ipairs(node.children) do
        if
            child.style.display ~= "none"
            and child.style.position ~= "absolute"
            and not child.props.portal
        then
            table.insert(result, child)
        end
    end
    return result
end
local function edges(style)
    local p = style.padding
    return p.left + p.right, p.top + p.bottom
end
local function axisMargins(style, row)
    local m = style.margin
    return row and m.left or m.top, row and m.right or m.bottom
end
local function gridInfo(node, width, height)
    local columns = Grid.count(node.props.columns)
    local children = flow(node)
    local cells, rows = Grid.cells(children, columns)
    local columnGap = node.style.columnGap or node.style.gap
    local rowGap = node.style.rowGap or node.style.gap
    local natural = {}
    if type(node.props.columns) == "table" then
        for _, cell in ipairs(cells) do
            local needsAuto = false
            for i = cell.column, cell.column + cell.columnSpan - 1 do
                if node.props.columns[i] == "auto" then
                    needsAuto = true
                end
            end
            if needsAuto then
                local measured = L.measure(cell.node, width, height)
                local m = cell.node.style.margin
                local each = math.max(
                    0,
                    (measured + m.left + m.right - columnGap * (cell.columnSpan - 1))
                        / cell.columnSpan
                )
                for i = cell.column, cell.column + cell.columnSpan - 1 do
                    natural[i] = math.max(natural[i] or 0, each)
                end
            end
        end
    end
    local tracks = Grid.tracks(node.props.columns, columns, width, columnGap, natural)
    return cells, rows, tracks, columnGap, rowGap
end
function L.measure(node, availableW, availableH)
    local s = node.style
    if s.display == "none" then
        return 0, 0
    end
    local cached = node.measureCache
    if not node.layoutDirty and cached and cached.aw == availableW and cached.ah == availableH then
        return cached.w, cached.h
    end
    local explicitW = C.dimension(s.width, availableW)
    local explicitH = C.dimension(s.height, availableH)
    local padW, padH = edges(s)
    local innerW = math.max(0, (explicitW or availableW) - padW)
    local innerH = math.max(0, (explicitH or availableH) - padH)
    local w, h = 0, 0
    local kind = node.kind
    if type(kind) == "table" then
        if node.children[1] then
            w, h = L.measure(node.children[1], availableW, availableH)
        end
        padW = 0
        padH = 0
    elseif kind == "Text" or kind == "Button" or kind == "IconButton" then
        local layout = Text.layout(
            node.app,
            node.props.text or node.props.icon or "",
            s,
            innerW,
            node.props.wrap ~= false and kind == "Text"
        )
        w = layout.width
        h = layout.height
    elseif kind == "TextInput" or kind == "TextArea" then
        w = 180
        h = kind == "TextArea" and 120 or s.fontSize * 1.3
    elseif kind == "Checkbox" or kind == "RadioButton" or kind == "Switch" then
        local text = Text.layout(node.app, node.props.text or "", s, innerW, false)
        w = (kind == "Switch" and 46 or 24) + (text.width > 0 and 8 + text.width or 0)
        h = math.max(26, text.height)
    elseif kind == "Slider" then
        w = 160
        h = 28
    elseif kind == "ProgressBar" then
        w = 160
        h = 10
    elseif kind == "Image" then
        w, h = Backend.image(node.props.source):getSize()
    elseif kind == "Separator" then
        w = 1
        h = 1
    elseif kind == "Canvas" then
        w = 240
        h = 160
    elseif kind == "Grid" then
        local cells, rows, tracks, cg, rg = gridInfo(node, innerW, innerH)
        local heights = {}
        for _, cell in ipairs(cells) do
            local cw = cg * (cell.columnSpan - 1)
            for i = cell.column, cell.column + cell.columnSpan - 1 do
                cw += tracks[i]
            end
            local _, ch = L.measure(cell.node, cw, innerH)
            local m = cell.node.style.margin
            local each = (ch + m.top + m.bottom - rg * (cell.rowSpan - 1)) / cell.rowSpan
            for i = cell.row, cell.row + cell.rowSpan - 1 do
                heights[i] = math.max(heights[i] or 0, each)
            end
        end
        for _, v in ipairs(tracks) do
            w += v
        end
        w += cg * math.max(0, #tracks - 1)
        for i = 1, rows do
            h += heights[i] or 0
        end
        h += rg * math.max(0, rows - 1)
        node.gridNatural = heights
    else
        local row = kind == "Row"
        local stack = kind == "Stack"
        local children = flow(node)
        local gap = row and (s.columnGap or s.gap) or (s.rowGap or s.gap)
        for _, child in ipairs(children) do
            local cw, ch = L.measure(child, innerW, innerH)
            local m = child.style.margin
            cw += m.left + m.right
            ch += m.top + m.bottom
            if stack then
                w = math.max(w, cw)
                h = math.max(h, ch)
            elseif row then
                w += cw
                h = math.max(h, ch)
            else
                w = math.max(w, cw)
                h += ch
            end
        end
        if not stack then
            if row then
                w += gap * math.max(0, #children - 1)
            else
                h += gap * math.max(0, #children - 1)
            end
        end
        if kind == "ScrollView" then
            w = math.min(w, 240)
            h = math.min(h, 240)
        end
    end
    local minW, minH, maxW, maxH = C.sides(s, availableW, availableH)
    w = C.clamp(explicitW or w + padW, minW, maxW)
    h = C.clamp(explicitH or h + padH, minH, maxH)
    node.measureCache = { aw = availableW, ah = availableH, w = w, h = h }
    return w, h
end
local function size(child, w, h)
    local minW, minH, maxW, maxH = C.sides(child.style, w, h)
    return C.clamp(w, minW, maxW), C.clamp(h, minH, maxH)
end
function L.arrange(node, x, y, width, height)
    local s = node.style
    if s.display == "none" then
        width = 0
        height = 0
    end
    width = math.max(0, width)
    height = math.max(0, height)
    local b = node.box
    local changed = b.x ~= x or b.y ~= y or b.width ~= width or b.height ~= height
    if not changed and not node.layoutDirty then
        return
    end
    local previous = table.clone(b)
    node.box = { x = x, y = y, width = math.max(0, width), height = math.max(0, height) }
    node.paintDirty = true
    if changed and node.app._markDirty then
        node.app:_markDirty(previous)
        node.app:_markDirty(node.box)
    end
    if
        changed
        and type(node.kind) == "string"
        and node.props.onLayout
        and not node.app.preflight
    then
        local changes = node.app._layoutChanges
        if changes then
            if not changes.before[node] then
                changes.before[node] = previous
                table.insert(changes.order, node)
            end
        else
            layoutCallback(node, previous)
        end
    end
    if type(node.kind) == "table" then
        if node.children[1] then
            local child = node.children[1]
            local cs = child.style
            local cw = width
            local ch = height
            if not node.parent then
                cw = C.dimension(cs.width, width) or width
                ch = C.dimension(cs.height, height) or height
            end
            cw, ch = size(child, cw, ch)
            L.arrange(
                child,
                x + (not node.parent and (cs.x or 0) or 0),
                y + (not node.parent and (cs.y or 0) or 0),
                cw,
                ch
            )
        end
        node.layoutDirty = false
        return
    end
    local p = s.padding
    local ix = x + p.left
    local iy = y + p.top
    local iw = math.max(0, width - p.left - p.right)
    local ih = math.max(0, height - p.top - p.bottom)
    local children = flow(node)
    local kind = node.kind
    if kind == "Grid" then
        local cells, rows, tracks, cg, rg = gridInfo(node, iw, ih)
        local rowDef = node.props.rows or table.create(rows, "auto")
        local natural = {}
        for _, cell in ipairs(cells) do
            local cw = cg * (cell.columnSpan - 1)
            for i = cell.column, cell.column + cell.columnSpan - 1 do
                cw += tracks[i]
            end
            local _, ch = L.measure(cell.node, cw, ih)
            local m = cell.node.style.margin
            local each =
                math.max(0, (ch + m.top + m.bottom - rg * (cell.rowSpan - 1)) / cell.rowSpan)
            for i = cell.row, cell.row + cell.rowSpan - 1 do
                natural[i] = math.max(natural[i] or 0, each)
            end
        end
        local rowTracks = Grid.tracks(rowDef, rows, ih, rg, natural)
        for _, cell in ipairs(cells) do
            local cx = ix
            local cy = iy
            local cw = cg * (cell.columnSpan - 1)
            local ch = rg * (cell.rowSpan - 1)
            for i = 1, cell.column - 1 do
                cx += tracks[i] + cg
            end
            for i = 1, cell.row - 1 do
                cy += rowTracks[i] + rg
            end
            for i = cell.column, cell.column + cell.columnSpan - 1 do
                cw += tracks[i]
            end
            for i = cell.row, cell.row + cell.rowSpan - 1 do
                ch += rowTracks[i]
            end
            local m = cell.node.style.margin
            L.arrange(
                cell.node,
                cx + m.left,
                cy + m.top,
                math.max(0, cw - m.left - m.right),
                math.max(0, ch - m.top - m.bottom)
            )
        end
    elseif kind == "Stack" then
        for _, child in ipairs(children) do
            local cw, ch = L.measure(child, iw, ih)
            local m = child.style.margin
            if child.style.width == nil then
                cw = iw - m.left - m.right
            end
            if child.style.height == nil then
                ch = ih - m.top - m.bottom
            end
            cw, ch = size(child, cw, ch)
            L.arrange(child, ix + m.left, iy + m.top, cw, ch)
        end
    else
        local row = kind == "Row"
        local scrolling = kind == "ScrollView"
        local items = {}
        local main = row and iw or ih
        local cross = row and ih or iw
        for _, child in ipairs(children) do
            local cw, ch = L.measure(child, iw, ih)
            local cs = child.style
            local before, after = axisMargins(cs, row)
            local minW, minH, maxW, maxH = C.sides(cs, iw, ih)
            table.insert(items, {
                node = child,
                basis = C.dimension(cs.flexBasis, main) or (row and cw or ch),
                min = row and minW or minH,
                max = row and maxW or maxH,
                grow = scrolling and 0 or cs.flexGrow,
                shrink = scrolling and 0 or cs.flexShrink,
                before = before,
                after = after,
                cross = row and ch or cw,
            })
        end
        local mainGap = row and (s.columnGap or s.gap) or (s.rowGap or s.gap)
        local remaining = Flex.distribute(items, main, mainGap)
        local contentMain = main - remaining
        local contentCross = cross
        for _, item in ipairs(items) do
            contentCross = math.max(contentCross, item.cross)
        end
        if scrolling then
            node.contentWidth = row and contentMain or contentCross
            node.contentHeight = row and contentCross or contentMain
            node.data.scrollX =
                math.clamp(node.data.scrollX or 0, 0, math.max(0, node.contentWidth - iw))
            node.data.scrollY =
                math.clamp(node.data.scrollY or 0, 0, math.max(0, node.contentHeight - ih))
            ix -= node.data.scrollX
            iy -= node.data.scrollY
        end
        local offset, gap = Flex.spacing(s.justifyContent, remaining, #items, mainGap)
        for _, item in ipairs(items) do
            local child = item.node
            local cs = child.style
            local m = cs.margin
            local crossBefore = row and m.top or m.left
            local crossAfter = row and m.bottom or m.right
            local align = cs.alignSelf or s.alignItems
            local csize = item.cross
            if align == "stretch" and (row and cs.height or cs.width) == nil then
                csize = cross - crossBefore - crossAfter
            end
            local cw = row and item.size or csize
            local ch = row and csize or item.size
            if row and cs.height == nil and align ~= "stretch" then
                local _, mh = L.measure(child, cw, ih)
                ch = mh
                csize = ch
            end
            cw, ch = size(child, cw, ch)
            local extra = math.max(0, cross - csize - crossBefore - crossAfter)
            local co = crossBefore
                + (align == "center" and extra / 2 or align == "end" and extra or 0)
            offset += item.before
            local cx = ix + (row and offset or co)
            local cy = iy + (row and co or offset)
            L.arrange(child, cx + (cs.x or 0), cy + (cs.y or 0), cw, ch)
            offset += item.size + item.after + gap
        end
    end
    for _, child in ipairs(node.children) do
        local cs = child.style
        if cs.position == "absolute" or child.props.portal then
            local cw, ch = L.measure(child, iw, ih)
            local left = C.dimension(cs.left, iw)
            local right = C.dimension(cs.right, iw)
            local top = C.dimension(cs.top, ih)
            local bottom = C.dimension(cs.bottom, ih)
            if left and right and cs.width == nil then
                cw = math.max(0, iw - left - right)
            end
            if top and bottom and cs.height == nil then
                ch = math.max(0, ih - top - bottom)
            end
            cw, ch = size(child, cw, ch)
            local cx = left or (right and iw - right - cw) or cs.x or 0
            local cy = top or (bottom and ih - bottom - ch) or cs.y or 0
            if child.props.portal then
                local anchor = child.props.anchor
                anchor = type(anchor) == "table" and anchor.current or anchor
                if anchor and anchor.box then
                    cx = anchor.box.x
                    cy = anchor.box.y + anchor.box.height + (child.props.offset or 4)
                end
                cx = math.clamp(cx, 0, math.max(0, node.app.width - cw))
                cy = math.clamp(cy, 0, math.max(0, node.app.height - ch))
                L.arrange(child, cx, cy, cw, ch)
            else
                L.arrange(child, ix + cx, iy + cy, cw, ch)
            end
        elseif cs.display == "none" then
            L.arrange(child, ix, iy, 0, 0)
        end
    end
    node.layoutDirty = false
end
local function runLayout(app)
    if not app.root then
        return
    end
    local started = os.clock()
    L.styles(app.root, nil, app.theme, false)
    L.measure(app.root, app.width, app.height)
    L.arrange(app.root, 0, 0, app.width, app.height)
    local function world(node)
        local path = {}
        local current = node
        while current do
            table.insert(path, current)
            if current.props.portal then
                break
            end
            current = current.parent
        end
        local matrix = Geometry.identity
        for i = #path, 1, -1 do
            matrix =
                Geometry.multiply(matrix, Geometry.transform(path[i].box, path[i].style.transform))
        end
        return matrix
    end
    local function anchors(node)
        local anchor = node.props.anchor
        anchor = type(anchor) == "table" and anchor.current or anchor
        if node.props.portal and anchor and anchor.box then
            local bounds = Geometry.aabb(anchor.box, world(anchor))
            L.arrange(
                node,
                math.clamp(bounds.x, 0, math.max(0, app.width - node.box.width)),
                math.clamp(
                    bounds.y + bounds.height + (node.props.offset or 4),
                    0,
                    math.max(0, app.height - node.box.height)
                ),
                node.box.width,
                node.box.height
            )
        end
        for _, child in ipairs(node.children) do
            anchors(child)
        end
    end
    anchors(app.root)
    app.diagnostics.layoutTime = os.clock() - started
    app.diagnostics.layouts += 1
end
function L.run(app)
    if not app.root then
        return
    end
    local previous = app._layoutChanges
    local changes = { before = {}, order = {} }
    app._layoutChanges = changes
    local ok, err = pcall(runLayout, app)
    app._layoutChanges = previous
    if not ok then
        error(err, 0)
    end
    -- Portal anchoring can arrange a node more than once. Only the final bounds
    -- relative to the start of this layout are observable by application code.
    for _, node in ipairs(changes.order) do
        layoutCallback(node, changes.before[node])
    end
end
return L
