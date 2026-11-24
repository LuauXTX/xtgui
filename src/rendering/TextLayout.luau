local Backend = require("./Backend")
local U = require("../input/Unicode")
local Text = {}
local cache = {}
local order = {}
local limit = 1024
function Text.layout(app, text, style, width, wrap)
    text = tostring(text or "")
    assert(#text <= 65536, "XTGUI text exceeds native 64 KiB limit")
    local font, fontKey, size = Backend.font(app, style)
    local lineHeight = style.lineHeight or size * 1.3
    assert(
        type(lineHeight) == "number" and lineHeight > 0 and lineHeight < 1e7,
        "XTGUI lineHeight must be positive and finite"
    )
    local key = fontKey
        .. ":"
        .. tostring(width)
        .. ":"
        .. tostring(wrap)
        .. ":"
        .. tostring(lineHeight)
        .. ":"
        .. text
    if cache[key] then
        return cache[key]
    end
    local parts = U.split(text)
    local lines = {}
    local maxWidth = 0
    local function measure(first, last)
        local value = Backend.measure(U.slice(parts, first, last), font)
        return value
    end
    local function add(first, last, newline)
        local current = U.slice(parts, first, last)
        local measured = measure(first, last)
        -- gfx exposes run widths, not glyph positions. Measure caret prefixes lazily.
        local positions = setmetatable({ [1] = 0 }, {
            __index = function(self, index)
                local value = measure(first, math.clamp(first + index - 1, first, last))
                rawset(self, index, value)
                return value
            end,
        })
        table.insert(lines, {
            text = current,
            width = measured,
            first = first,
            last = last,
            newline = newline,
            y = #lines * lineHeight,
            positions = positions,
        })
        maxWidth = math.max(maxWidth, measured)
    end
    local function paragraph(first, last, newline)
        if not wrap or not width or width <= 0 or first == last then
            add(first, last, newline)
            return
        end
        while first < last do
            local low, high = first + 1, last
            local fits = first + 1
            if measure(first, last) <= width then
                add(first, last, newline)
                break
            end
            while low <= high do
                local middle = math.floor((low + high) / 2)
                if measure(first, middle) <= width then
                    fits = middle
                    low = middle + 1
                else
                    high = middle - 1
                end
            end
            local finish = fits
            if fits < last then
                for index = fits, first + 1, -1 do
                    if parts[index]:match("^%s+$") then
                        finish = index
                        break
                    end
                end
            end
            add(first, finish, finish == last and newline)
            first = finish
        end
    end
    local start = 0
    for index, part in ipairs(parts) do
        if part == "\n" or part == "\r\n" or part == "\r" then
            paragraph(start, index - 1, true)
            start = index
        end
    end
    paragraph(start, #parts, false)
    local result = {
        font = font,
        lines = lines,
        width = maxWidth,
        height = #lines * lineHeight,
        lineHeight = lineHeight,
        parts = parts,
    }
    cache[key] = result
    table.insert(order, key)
    if #order > limit then
        cache[table.remove(order, 1)] = nil
    end
    return result
end
function Text.caret(layout, index)
    for i, line in ipairs(layout.lines) do
        if index <= line.last or i == #layout.lines then
            local offset = math.clamp(index - line.first, 0, line.last - line.first)
            return line.positions[offset + 1], line.y, i
        end
    end
    return 0, 0, 1
end
function Text.index(layout, x, y)
    local line = layout.lines[math.clamp(math.floor(y / layout.lineHeight) + 1, 1, #layout.lines)]
    local count = line.last - line.first
    local low, high = 0, count
    while low < high do
        local middle = math.floor((low + high) / 2)
        if x < (line.positions[middle + 1] + line.positions[middle + 2]) / 2 then
            high = middle
        else
            low = middle + 1
        end
    end
    return line.first + low
end
function Text.clear()
    cache = {}
    order = {}
end
return Text
