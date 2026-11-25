-- Bounded causal traces, containing labels/counters rather than user state values.
local D = { current = nil, serial = 0 }
function D.node(node)
    if not node then
        return "<application>"
    end
    local id = node.props and node.props.id
    return (node.name or "node")
        .. "#"
        .. tostring(node.id or "?")
        .. (id and ("(" .. tostring(id):sub(1, 64) .. ")") or "")
end
function D.tag(value, kind, node, index)
    D.serial += 1
    value._debugLabel = kind
        .. "#"
        .. D.serial
        .. (node and (" " .. D.node(node) .. " hook " .. index) or "")
    if node then
        value._ownerApp = setmetatable({ node.app }, { __mode = "v" })
    end
end
function D.label(value)
    if type(value) == "table" then
        if value._debugLabel then
            local callback = value.callback
            local suffix = ""
            if type(callback) == "function" and debug and debug.info then
                local ok, source, line = pcall(debug.info, callback, "sl")
                if ok then
                    suffix = " at " .. tostring(source) .. ":" .. tostring(line)
                end
            end
            return (value._debugLabel .. suffix):sub(1, 240)
        end
        if value.kind then
            return D.node(value)
        end
    end
    return "scheduler job"
end
function D.call(label, callback, origin)
    local previous = D.current
    D.current = label .. (origin and (" <- " .. origin:sub(1, 240)) or "")
    local result = table.pack(pcall(callback))
    D.current = previous
    if not result[1] then
        error(result[2], 0)
    end
    return table.unpack(result, 2, result.n)
end
function D.begin(app)
    local trace = { sources = {}, count = 0, total = 0, recent = {}, pass = 0, phase = "start" }
    app._flushTrace = trace
    app.diagnostics.recentInvalidations = trace.recent
    return trace
end
function D.record(app, reason, subject)
    local trace = app and app._flushTrace
    if not trace then
        return
    end
    local label = reason
        .. " "
        .. D.label(subject)
        .. (D.current and (" <- " .. D.current:sub(1, 320)) or "")
    trace.total += 1
    if trace.sources[label] then
        trace.sources[label] += 1
    elseif trace.count < 64 then
        trace.sources[label] = 1
        trace.count += 1
    end
    if #trace.recent == 24 then
        table.remove(trace.recent, 1)
    end
    table.insert(trace.recent, "pass " .. trace.pass .. " " .. trace.phase .. ": " .. label)
end
function D.report(app)
    local trace = app._flushTrace
    local sources = {}
    for reason, count in pairs(trace.sources) do
        table.insert(sources, { reason = reason, count = count })
    end
    table.sort(sources, function(a, b)
        return a.count == b.count and a.reason < b.reason or a.count > b.count
    end)
    local lines = {
        "XTGUI layout/effect update loop exceeded 100 passes",
        "phase="
            .. trace.phase
            .. ", layout="
            .. tostring(app._needsLayout)
            .. ", styles="
            .. tostring(app._needsStyles),
    }
    for i = 1, math.min(8, #sources) do
        table.insert(lines, "  " .. sources[i].count .. "x " .. sources[i].reason)
    end
    local report = {
        pass = trace.pass,
        phase = trace.phase,
        sources = sources,
        recent = table.clone(trace.recent),
    }
    app.diagnostics.lastUpdateLoop = report
    return table.concat(lines, "\n")
end
return D
