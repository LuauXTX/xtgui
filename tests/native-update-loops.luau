local gui = require("../src/init")
local mode = process.argv[3] or "empty"
local saved, current
local dependency = gui.state(1)
local runs = 0
local app = gui.createApp({
    title = "XTGUI update-loop regression: " .. mode,
    width = 420,
    height = 240,
    onFrame = function(_, active)
        assert(not active.diagnostics.lastUpdateLoop)
        if mode == "reactive" then
            assert(current == saved, "component state identity changed")
            if active.diagnostics.frames == 1 then
                assert(runs == 1 and active:find("value").props.text == "1")
                dependency:set(2)
                active:flush()
                assert(runs == 2 and active:find("value").props.text == "2")
            end
        else
            assert(active.root == nil and active.diagnostics.layouts == 0)
        end
        assert(not active._needsLayout and not active._needsStyles)
        if active.diagnostics.frames >= 3 then
            active:close()
        else
            active:invalidate()
        end
    end,
})
if mode == "reactive" then
    local View = gui.component(function()
        current = gui.state({ value = 0 })
        saved = saved or current
        gui.effect(function()
            runs += 1
            current:set({ value = dependency:get() })
        end)
        return gui.Text({ id = "value", text = tostring(current:get().value) })
    end, "NativeEffectView")
    app:render(View({}))
else
    app:flush() -- No render() call: matches the reported application.
end
app:after(10, function()
    error("update-loop native test timed out")
end)
app:run()
assert(app.destroyed and app.diagnostics.frames >= 3)
dependency:dispose()
print(
    "XTGUI "
        .. mode
        .. " update-loop regression passed: "
        .. app.diagnostics.frames
        .. " completed GPU frames"
)
