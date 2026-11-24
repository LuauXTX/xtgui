local gui = require("../src/init") -- Installed applications use require("xtgui").
local support = require("./support")
local app = gui.createApp({
    title = "Hello XTGUI",
    width = 540,
    height = 320,
    theme = "dark",
    resizable = true,
})
local count = gui.state(0)
app:render(function(ui)
    return ui:Column({
        padding = 24,
        gap = 12,
        children = {
            ui:Text({ text = "Hello from XTGUI!", fontSize = 28 }),
            ui:Text({ text = "A retained, reactive desktop interface.", color = "$muted" }),
            ui:Button({
                id = "counter",
                text = "Clicked " .. count:get() .. " times",
                width = 220,
                onClick = function()
                    count:update(function(old)
                        return old + 1
                    end)
                end,
            }),
            ui:Text({
                text = "Resize the window. Tab and Enter work too.",
                fontSize = 13,
                color = "$muted",
            }),
        },
    })
end)
support.run(app, "hello", function(a)
    local b = a:find("counter").box
    a:dispatch({ type = "mouseMove", x = b.x + 4, y = b.y + 4 })
    a:dispatch({ type = "mouseDown", button = "left" })
    a:dispatch({ type = "mouseUp", button = "left" })
    assert(count:get() == 1)
end)
count:dispose()
