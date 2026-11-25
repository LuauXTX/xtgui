-- Explicit test harness: run the actual entrypoint and installed Application.
-- Attach only a frame observer/closer; no source edits or renderer substitutes.
local entry = assert(process.argv[3], "Pass the absolute application entrypoint")
local Application =
    require(assert(process.argv[4], "Pass the installed core/Application.luau path"))
local original = Application.runAll
local completed = 0
Application.runAll = function(apps)
    for _, app in ipairs(apps) do
        local previous = app.options.onFrame
        app.options.onFrame = function(dt, active)
            if previous then
                previous(dt, active)
            end
            assert(not active.diagnostics.lastUpdateLoop)
            assert(not active._needsLayout and not active._needsStyles)
            completed += 1
            if completed >= 3 then
                active:close()
            else
                active:invalidate()
            end
        end
    end
    return original(apps)
end
local ok, err = pcall(require, entry)
Application.runAll = original
assert(ok, tostring(err))
assert(completed >= 3, "Application did not complete three GPU frames")
print("Actual application passed: " .. entry .. ", " .. completed .. " completed GPU frames")
