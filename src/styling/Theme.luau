local Theme = {}
local base = {
    radius = 7,
    spacing = 8,
    fontSize = 16,
    fontFamily = "system",
    colors = {
        primary = "#3B82F6",
        background = "#111827",
        surface = "#1F2937",
        elevated = "#293548",
        text = "#F3F4F6",
        muted = "#9CA3AF",
        border = "#42516A",
        hover = "#33445F",
        active = "#26364F",
        focus = "#60A5FA",
        danger = "#EF4444",
        selection = "#315C9D",
    },
}
local function merge(a, b)
    local out = {}
    for k, v in pairs(a or {}) do
        out[k] = type(v) == "table" and merge(v, {}) or v
    end
    for k, v in pairs(b or {}) do
        out[k] = type(v) == "table" and merge(type(out[k]) == "table" and out[k] or {}, v) or v
    end
    return out
end
Theme.merge = merge
Theme.dark = base
Theme.light = merge(base, {
    colors = {
        background = "#F3F4F6",
        surface = "#FFFFFF",
        elevated = "#E5E7EB",
        text = "#111827",
        muted = "#4B5563",
        border = "#CBD5E1",
        hover = "#DBEAFE",
        active = "#BFDBFE",
        selection = "#BFDBFE",
    },
})
Theme.current = "dark"
function Theme.resolve(value, parent)
    if value == nil then
        return parent or Theme.resolve(Theme.current)
    end
    if type(value) == "string" then
        assert(Theme[value] and type(Theme[value]) == "table", "XTGUI unknown theme: " .. value)
        return Theme[value]
    end
    assert(type(value) == "table", "XTGUI theme must be light, dark, or a definition table")
    return merge(parent or base, value)
end
function Theme.set(value)
    Theme.current = value
    return Theme.resolve(value)
end
return Theme
