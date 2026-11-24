local Flex = {}
-- Freeze constrained items and redistribute remaining space. At most n+1 passes.
function Flex.distribute(items, available, gap)
    local occupied = gap * math.max(0, #items - 1)
    for _, item in ipairs(items) do
        item.size = math.clamp(item.basis, item.min, item.max)
        occupied += item.size + item.before + item.after
    end
    local remaining = available - occupied
    local growing = remaining > 0
    local frozen = {}
    for _ = 1, #items + 1 do
        if math.abs(remaining) < 0.001 then
            break
        end
        local weight = 0
        for _, item in ipairs(items) do
            if not frozen[item] then
                weight += growing and item.grow or item.shrink * item.basis
            end
        end
        if weight == 0 then
            break
        end
        local consumed = 0
        for _, item in ipairs(items) do
            if not frozen[item] then
                local fraction = (growing and item.grow or item.shrink * item.basis) / weight
                local proposed = item.size + remaining * fraction
                local size = math.clamp(proposed, item.min, item.max)
                consumed += size - item.size
                item.size = size
                if math.abs(size - proposed) > 0.001 then
                    frozen[item] = true
                end
            end
        end
        remaining -= consumed
    end
    return remaining
end
function Flex.spacing(justify, left, count, gap)
    left = math.max(0, left)
    if justify == "center" then
        return left / 2, gap
    elseif justify == "end" then
        return left, gap
    elseif justify == "space-between" and count > 1 then
        return 0, gap + left / (count - 1)
    elseif justify == "space-around" and count > 0 then
        return left / count / 2, gap + left / count
    elseif justify == "space-evenly" and count > 0 then
        return left / (count + 1), gap + left / (count + 1)
    end
    return 0, gap
end
return Flex
