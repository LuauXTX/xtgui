local C = {}
function C.number(value, name, min, max)
    assert(
        type(value) == "number"
            and value == value
            and math.abs(value) < math.huge
            and value >= (min or -1e7)
            and value <= (max or 1e7),
        "XTGUI invalid " .. name .. ": expected a finite number in range"
    )
    return value
end
function C.dimension(value, available, name)
    if value == nil or value == "auto" then
        return nil
    end
    if type(value) == "string" then
        local percent = value:match("^(%d+%.?%d*)%%$")
        assert(percent, "XTGUI invalid " .. (name or "dimension") .. ": " .. value)
        return available * tonumber(percent) / 100
    end
    return C.number(value, name or "dimension", 0, 1e7)
end
function C.clamp(value, min, max)
    return math.max(min or 0, math.min(max or 1e7, value))
end
function C.box(value)
    if value == nil then
        return { top = 0, right = 0, bottom = 0, left = 0 }
    end
    if type(value) == "number" then
        C.number(value, "spacing", 0)
        return { top = value, right = value, bottom = value, left = value }
    end
    assert(type(value) == "table", "XTGUI padding/margin must be a number or table")
    local top = value.top or value[1] or 0
    local right = value.right or value[2] or top
    local bottom = value.bottom or value[3] or top
    local left = value.left or value[4] or right
    for _, v in ipairs({ top, right, bottom, left }) do
        C.number(v, "spacing", 0)
    end
    return { top = top, right = right, bottom = bottom, left = left }
end
function C.sides(style, availableW, availableH)
    local minW = C.dimension(style.minWidth, availableW, "minWidth") or 0
    local minH = C.dimension(style.minHeight, availableH, "minHeight") or 0
    local maxW = C.dimension(style.maxWidth, availableW, "maxWidth") or 1e7
    local maxH = C.dimension(style.maxHeight, availableH, "maxHeight") or 1e7
    assert(minW <= maxW and minH <= maxH, "XTGUI minimum dimensions exceed maximum dimensions")
    return minW, minH, maxW, maxH
end
return C
