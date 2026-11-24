local Scheduler = { queue = {}, keyed = {}, depth = 0, flushing = false, limit = 1000 }
function Scheduler.enqueue(key, callback)
    if Scheduler.keyed[key] then return end
    Scheduler.keyed[key] = true
    table.insert(Scheduler.queue, { key, callback })
end
function Scheduler.flush()
    if Scheduler.flushing or Scheduler.depth > 0 then return end
    Scheduler.flushing = true
    local count = 0
    local ok, err = pcall(function()
        while #Scheduler.queue > 0 do
            local work = Scheduler.queue
            Scheduler.queue = {}
            for _, item in ipairs(work) do
                Scheduler.keyed[item[1]] = nil
                count += 1
                assert(count <= Scheduler.limit, "XTGUI reactive update loop exceeded 1000 jobs")
                item[2]()
            end
        end
    end)
    Scheduler.flushing = false
    if not ok then Scheduler.queue = {}; Scheduler.keyed = {}; error(err, 0) end
end
function Scheduler.batch(callback)
    Scheduler.depth += 1
    local result = table.pack(pcall(callback))
    Scheduler.depth -= 1
    if result[1] then Scheduler.flush(); return table.unpack(result, 2, result.n) end
    error(result[2], 0)
end
return Scheduler
