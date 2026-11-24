local Style = require("../styling/Style")
local Text = require("./TextLayout")
local Backend = require("./Backend")
local W = require("../components/Widgets")
local Paint = {}
function Paint.commands(node)
    if not node.paintDirty and node.commands then
        return node.commands
    end
    local commands = {}
    local b = node.box
    local s = node.style
    local p = node.props
    local colors = node.theme.colors
    local function add(op, props)
        table.insert(commands, { op = op, props = props })
    end
    local function rect(x, y, w, h, color, radius, outline, lineWidth)
        if w > 0 and h > 0 and color then
            add("rect", {
                x = x,
                y = y,
                width = w,
                height = h,
                color = Style.color(color),
                radius = radius or 0,
                outline = outline,
                lineWidth = lineWidth or 1,
            })
        end
    end
    local function line(x1, y1, x2, y2, color, width)
        add(
            "line",
            { x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = Style.color(color), width = width or 1 }
        )
    end
    local function text(layout, x, y, color, align, width)
        for _, run in ipairs(layout.lines) do
            if run.text ~= "" then
                local offset = align == "center" and ((width or layout.width) - run.width) / 2
                    or align == "end" and (width or layout.width) - run.width
                    or 0
                add("text", {
                    text = run.text,
                    font = layout.font,
                    x = x + offset,
                    y = y + run.y,
                    color = Style.color(color),
                })
            end
        end
    end
    if s.shadow then
        local shadow = s.shadow
        local blur = math.clamp(shadow.blur or 8, 0, 48)
        local layers = math.max(1, math.ceil(blur / 4))
        local color = Style.color(shadow.color or "#00000040")
        for i = layers, 1, -1 do
            local spread = blur * i / layers / 2
            local c = table.clone(color)
            c[4] /= layers
            rect(
                b.x + (shadow.x or 0) - spread,
                b.y + (shadow.y or 2) - spread,
                b.width + spread * 2,
                b.height + spread * 2,
                c,
                (s.radius or 0) + spread
            )
        end
    end
    rect(b.x, b.y, b.width, b.height, s.background, s.radius)
    if s.borderWidth > 0 then
        rect(
            b.x,
            b.y,
            b.width,
            b.height,
            s.borderColor or colors.border,
            s.radius,
            true,
            s.borderWidth
        )
    end
    local pad = s.padding
    local x = b.x + pad.left
    local y = b.y + pad.top
    local width = math.max(0, b.width - pad.left - pad.right)
    local height = math.max(0, b.height - pad.top - pad.bottom)
    local kind = node.kind
    if kind == "Text" or kind == "Button" or kind == "IconButton" then
        local layout = Text.layout(
            node.app,
            p.text or p.icon or "",
            s,
            width,
            p.wrap ~= false and kind == "Text"
        )
        local align = s.textAlign or (kind ~= "Text" and "center" or "start")
        local ty = y
            + (
                (s.verticalAlign == "center" or kind ~= "Text") and (height - layout.height) / 2
                or 0
            )
        text(layout, x, ty, s.color, align, width)
    elseif kind == "Checkbox" or kind == "RadioButton" or kind == "Switch" then
        local checked = W.value(node, "checked", false)
        local cy = y + height / 2
        local toggleWidth = kind == "Switch" and 44 or 22
        if kind == "Switch" then
            rect(x, cy - 12, 44, 24, checked and colors.primary or colors.border, 12)
            rect(x + (checked and 24 or 4), cy - 8, 16, 16, "#FFFFFF", 8)
        elseif kind == "RadioButton" then
            rect(x, cy - 10, 20, 20, checked and colors.primary or colors.border, 10, true, 2)
            if checked then
                rect(x + 5, cy - 5, 10, 10, colors.primary, 5)
            end
        else
            rect(x, cy - 10, 20, 20, checked and colors.primary or colors.surface, 4)
            rect(x, cy - 10, 20, 20, checked and colors.primary or colors.border, 4, true, 1)
            if checked then
                line(x + 4, cy, x + 8, cy + 4, "#FFFFFF", 2)
                line(x + 8, cy + 4, x + 16, cy - 4, "#FFFFFF", 2)
            end
        end
        local layout =
            Text.layout(node.app, p.text or "", s, math.max(0, width - toggleWidth - 8), false)
        text(layout, x + toggleWidth + 8, cy - layout.height / 2, s.color)
    elseif kind == "Slider" or kind == "ProgressBar" then
        local min, max = p.min or 0, p.max or (kind == "ProgressBar" and 1 or 100)
        local value = W.value(node, "value", min)
        local ratio = math.clamp((value - min) / (max - min), 0, 1)
        if kind == "Slider" then
            local cy = y + height / 2
            rect(x + 9, cy - 2, math.max(0, width - 18), 4, colors.border, 2)
            rect(x + 9, cy - 2, math.max(0, (width - 18) * ratio), 4, colors.primary, 2)
            rect(x + (width - 18) * ratio, cy - 9, 18, 18, colors.primary, 9)
        else
            rect(x, y, width * ratio, height, colors.primary, s.radius)
        end
    elseif kind == "Image" then
        local image = Backend.image(p.source)
        local iw, ih = image:getSize()
        local dw, dh = width, height
        if p.fit == "contain" then
            local ratio = math.min(width / iw, height / ih)
            dw = iw * ratio
            dh = ih * ratio
        end
        if dw > 0 and dh > 0 then
            add("image", {
                image = image,
                x = x + (width - dw) / 2,
                y = y + (height - dh) / 2,
                width = dw,
                height = dh,
                color = Style.color(p.tint or "#FFFFFF"),
            })
        end
    elseif kind == "TextInput" or kind == "TextArea" then
        local editor = W.editor(node)
        local display, caret, compositionFirst, compositionLast = editor:display(p.password)
        local layout =
            Text.layout(node.app, display, s, width, kind == "TextArea" and p.wrap ~= false)
        node.textLayout = layout
        local cx, cy = Text.caret(layout, caret)
        local minX = math.max(0, cx - width + 3)
        local minY = math.max(0, cy + layout.lineHeight - height)
        editor.scrollX = math.clamp(editor.scrollX, minX, math.max(minX, cx))
        editor.scrollY = math.clamp(editor.scrollY, minY, math.max(minY, cy))
        local tx = x - editor.scrollX
        local ty = y - editor.scrollY
        if width > 0 and height > 0 then
            add("pushClip", { x = x, y = y, width = width, height = height })
            if display == "" and p.placeholder then
                text(Text.layout(node.app, p.placeholder, s, width, false), tx, ty, colors.muted)
            else
                local lo, hi = editor:range()
                if editor.composition == "" and node.interaction.focused and lo ~= hi then
                    for _, run in ipairs(layout.lines) do
                        local a = math.max(lo, run.first)
                        local z = math.min(hi, run.last)
                        if z >= a and hi > run.first and lo <= run.last then
                            local x1 = run.positions[a - run.first + 1] or 0
                            local x2 = run.positions[z - run.first + 1] or run.width
                            if run.newline and hi > run.last then
                                x2 = math.max(x2, width)
                            end
                            rect(
                                tx + x1,
                                ty + run.y,
                                math.max(1, x2 - x1),
                                layout.lineHeight,
                                colors.selection
                            )
                        end
                    end
                end
                text(layout, tx, ty, s.color)
            end
            if compositionFirst then
                local ax, ay = Text.caret(layout, compositionFirst)
                local zx, zy = Text.caret(layout, compositionLast)
                if ay == zy then
                    line(
                        tx + ax,
                        ty + ay + layout.lineHeight - 2,
                        tx + math.max(ax + 1, zx),
                        ty + ay + layout.lineHeight - 2,
                        colors.primary,
                        1
                    )
                end
            end
            if
                node.interaction.focused
                and node.app.focus.windowFocused ~= false
                and node.app._caretVisible ~= false
            then
                rect(tx + cx, ty + cy, 1, layout.lineHeight, s.color)
            end
            add("popClip")
        end
    end
    if node.interaction.focused and node.app.focus.visible and not node.disabled then
        rect(
            b.x + 1,
            b.y + 1,
            math.max(0, b.width - 2),
            math.max(0, b.height - 2),
            colors.focus,
            s.radius,
            true,
            2
        )
    end
    node.commands = commands
    node.paintDirty = false
    return commands
end
return Paint
