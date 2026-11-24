-- Indices throughout editing are zero-based grapheme boundaries, never UTF-8 bytes.
local U = {}
local function extend(cp)
    return (cp >= 0x300 and cp <= 0x36f)
        or (cp >= 0x1ab0 and cp <= 0x1aff)
        or (cp >= 0x1dc0 and cp <= 0x1dff)
        or (cp >= 0x20d0 and cp <= 0x20ff)
        or (cp >= 0xfe00 and cp <= 0xfe0f)
        or (cp >= 0xfe20 and cp <= 0xfe2f)
        or (cp >= 0x1f3fb and cp <= 0x1f3ff)
        or (cp >= 0xe0100 and cp <= 0xe01ef)
end
function U.split(text)
    assert(type(text) == "string" and utf8.len(text), "XTGUI text must contain valid UTF-8")
    local result = {}
    local previous = nil
    local regional = 0
    local start = nil
    for index, cp in utf8.codes(text) do
        local isRegional = cp >= 0x1f1e6 and cp <= 0x1f1ff
        local join = start
            and (
                extend(cp)
                or cp == 0x200d
                or previous == 0x200d
                or (previous == 13 and cp == 10)
                or (isRegional and regional % 2 == 1)
            )
        if not join then
            if start then
                table.insert(result, text:sub(start, index - 1))
            end
            start = index
        end
        regional = isRegional and (regional + 1) or 0
        previous = cp
    end
    if start then
        table.insert(result, text:sub(start))
    end
    return result
end
function U.slice(parts, first, last)
    return table.concat(parts, "", first + 1, last or #parts)
end
function U.word(part)
    return part and (part:match("[%w_]") ~= nil or (utf8.codepoint(part) or 0) > 127)
end
function U.byteToIndex(text, byte)
    local offset, index = 0, 0
    for _, part in ipairs(U.split(text)) do
        if offset >= byte then
            break
        end
        offset += #part
        index += 1
    end
    return index
end
return U
