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
-- Execute as a script, outside require's synchronous native module-loader
-- boundary. gfx.run must be able to yield to LuauXTX's native event loop.
local source = require("@luauxtx/system/fs").readSync(entry)
local chunk = assert(loadstring(source, "@" .. entry))
chunk()
Application.runAll = original
assert(completed >= 3, "Application did not complete three GPU frames")
print("Actual application passed: " .. entry .. ", " .. completed .. " completed GPU frames")
