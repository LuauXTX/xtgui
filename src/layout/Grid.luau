local C = require("./Constraints")
local Grid = {}
function Grid.count(columns)
    if type(columns) == "number" then
        assert(
            columns % 1 == 0 and columns >= 1 and columns <= 1024,
            "XTGUI Grid columns must be 1..1024"
        )
        return columns
    end
    assert(
        columns == nil or (type(columns) == "table" and #columns > 0 and #columns <= 1024),
        "XTGUI invalid Grid columns"
    )
    return columns and #columns or 1
end
function Grid.tracks(definition, count, available, gap, natural)
    local result = {}
    local weights = {}
    local used = math.max(0, count - 1) * gap
    local total = 0
    for i = 1, count do
        local value = type(definition) == "table" and definition[i] or "1fr"
        if value == "auto" then
            result[i] = natural and natural[i] or 0
        elseif type(value) == "string" and value:match("^%d*%.?%d+fr$") then
            weights[i] = tonumber(value:sub(1, -3))
            total += weights[i]
            result[i] = 0
        else
            result[i] = C.dimension(value, available, "grid track") or (natural and natural[i] or 0)
        end
        used += result[i]
    end
    for i, weight in pairs(weights) do
        result[i] = math.max(0, available - used) * weight / math.max(total, 1e-9)
    end
    return result
end
function Grid.cells(children, columns)
    local result = {}
    local occupied = {}
    local cursor = 1
    local maxRow = 1
    for _, child in ipairs(children) do
        local p = child.props
        local cs = p.columnSpan or 1
        local rs = p.rowSpan or 1
        assert(
            type(cs) == "number"
                and cs % 1 == 0
                and cs >= 1
                and cs <= columns
                and type(rs) == "number"
                and rs % 1 == 0
                and rs >= 1
                and rs <= 1024,
            "XTGUI invalid Grid span"
        )
        local column = p.gridColumn
        local row = p.gridRow
        if column or row then
            column = column or 1
            row = row or 1
            assert(
                type(column) == "number"
                    and column % 1 == 0
                    and column >= 1
                    and column + cs - 1 <= columns
                    and type(row) == "number"
                    and row % 1 == 0
                    and row >= 1
                    and row <= 100000,
                "XTGUI invalid Grid cell"
            )
        else
            while true do
                row = math.floor((cursor - 1) / columns) + 1
                column = (cursor - 1) % columns + 1
                local fits = column + cs - 1 <= columns
                if fits then
                    for r = row, row + rs - 1 do
                        for c = column, column + cs - 1 do
                            if occupied[(r - 1) * columns + c] then
                                fits = false
                            end
                        end
                    end
                end
                if fits then
                    break
                end
                cursor += 1
                assert(cursor <= 100000, "XTGUI Grid placement limit exceeded")
            end
        end
        for r = row, row + rs - 1 do
            for c = column, column + cs - 1 do
                occupied[(r - 1) * columns + c] = true
            end
        end
        maxRow = math.max(maxRow, row + rs - 1)
        table.insert(
            result,
            { node = child, column = column, row = row, columnSpan = cs, rowSpan = rs }
        )
        cursor += cs
    end
    return result, maxRow
end
return Grid
