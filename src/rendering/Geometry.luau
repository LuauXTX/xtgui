local G = {}
G.identity = { 1, 0, 0, 1, 0, 0 }
function G.multiply(a, b)
    return {
        a[1] * b[1] + a[3] * b[2],
        a[2] * b[1] + a[4] * b[2],
        a[1] * b[3] + a[3] * b[4],
        a[2] * b[3] + a[4] * b[4],
        a[1] * b[5] + a[3] * b[6] + a[5],
        a[2] * b[5] + a[4] * b[6] + a[6],
    }
end
function G.point(m, x, y)
    return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end
function G.inverse(m)
    local d = m[1] * m[4] - m[2] * m[3]
    if math.abs(d) < 1e-10 then
        return nil
    end
    return {
        m[4] / d,
        -m[2] / d,
        -m[3] / d,
        m[1] / d,
        (m[3] * m[6] - m[4] * m[5]) / d,
        (m[2] * m[5] - m[1] * m[6]) / d,
    }
end
function G.transform(box, t)
    t = t or {}
    local r = t.rotation or 0
    local s, c = math.sin(r), math.cos(r)
    local sx, sy = t.scaleX or 1, t.scaleY or 1
    return G.multiply(
        { c * sx, s * sx, -s * sy, c * sy, box.x + (t.x or 0), box.y + (t.y or 0) },
        { 1, 0, 0, 1, -box.x, -box.y }
    )
end
function G.polygon(box, m)
    local result = {}
    for _, p in ipairs({
        { box.x, box.y },
        { box.x + box.width, box.y },
        { box.x + box.width, box.y + box.height },
        { box.x, box.y + box.height },
    }) do
        local x, y = G.point(m, p[1], p[2])
        table.insert(result, { x, y })
    end
    return result
end
function G.contains(poly, x, y)
    if not poly or #poly < 3 then
        return poly == nil
    end
    local sign
    for i, a in ipairs(poly) do
        local b = poly[i % #poly + 1]
        local cross = (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1])
        if math.abs(cross) > 1e-6 then
            local nextSign = cross > 0
            if sign ~= nil and sign ~= nextSign then
                return false
            end
            sign = nextSign
        end
    end
    return sign ~= nil
end
function G.aabb(box, m)
    local points = G.polygon(box, m)
    local x, y, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(points) do
        x = math.min(x, p[1])
        y = math.min(y, p[2])
        x2 = math.max(x2, p[1])
        y2 = math.max(y2, p[2])
    end
    return { x = x, y = y, width = x2 - x, height = y2 - y }
end
function G.overlaps(a, b)
    return a.x < b.x + b.width
        and a.x + a.width > b.x
        and a.y < b.y + b.height
        and a.y + a.height > b.y
end
return G
