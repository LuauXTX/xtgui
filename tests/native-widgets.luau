local gui = require("../src/init")
local imagePath =
    assert(process.argv[3], "Pass the generated PNG fixture (tests/run.py --gui does this)")
local tab = gui.state("controls")
local open = gui.state(false)
local choice = gui.state("one")
local selected = gui.state(nil)
local items = {}
for i = 1, 10000 do
    items[i] = { key = i, label = "Item " .. i, value = i }
end
local canvasDraws = 0
local stage = 0
local main, second
local sharedFont, sharedImage
local function click(app, node)
    local b = node.box
    app:dispatch({ type = "mouseMove", x = b.x + b.width / 2, y = b.y + b.height / 2 })
    app:dispatch({ type = "mouseDown", button = "left" })
    app:dispatch({ type = "mouseUp", button = "left" })
end
main = gui.createApp({
    title = "XTGUI native widget integration",
    width = 1000,
    height = 800,
    onFrame = function(_, app)
        stage += 1
        if stage == 1 then
            app:find("select"):focus()
            app:dispatch({ type = "keyDown", key = "ArrowDown" })
            app:dispatch({ type = "keyDown", key = "ArrowDown" })
            app:dispatch({ type = "keyDown", key = "Enter" })
            assert(choice:get() == "two")
            open:set(true)
            app:resize(980, 780)
        elseif stage == 2 then
            assert(#app._portals == 2 and app.focus.current == app:find("modal-button"))
            app:dispatch({ type = "keyDown", key = "Escape" })
            assert(not open:get())
            tab:set("data")
        elseif stage == 3 then
            local list = app:find("list")
            list:focus()
            app:dispatch({ type = "keyDown", key = "End" })
            assert(selected:get() == 10000 and list.data.scrollY > 300000)
            tab:set("visual")
        elseif stage == 4 then
            assert(canvasDraws > 0 and app:find("image"))
            gui.tween(app:find("image"), { opacity = 0.5 }, { duration = 0.05 })
        elseif stage >= 5 then
            assert(not sharedFont:isDisposed() and not sharedImage:isDisposed())
            app:destroy()
        end
    end,
})
sharedFont = main:loadFont(nil, 16)
sharedImage = main:loadImage(imagePath)
main:render(gui.Column({
    padding = 20,
    gap = 12,
    children = {
        gui.Text({
            text = "Real native widgets, images, transforms, clips and two windows",
            fontSize = 22,
        }),
        gui.Tabs({
            value = tab,
            height = 650,
            tabs = {
                {
                    key = "controls",
                    label = "Controls",
                    content = gui.Column({
                        gap = 12,
                        children = {
                            gui.Select({
                                id = "select",
                                value = choice,
                                items = {
                                    "one",
                                    "two",
                                    "three",
                                },
                            }),
                            gui.TextArea({
                                value = "Unicode: café 日本語 👩‍💻",
                                height = 100,
                            }),
                            gui.Checkbox({ text = "Checked", defaultChecked = true }),
                            gui.Switch({ text = "Enabled", defaultChecked = true }),
                            gui.Slider({ defaultValue = 50 }),
                            gui.ProgressBar({ value = 0.6 }),
                            gui.Button({
                                text = "Transition",
                                transition = { duration = 0.1 },
                                hoverStyle = { background = "$primary" },
                            }),
                        },
                    }),
                },
                {
                    key = "data",
                    label = "Data",
                    content = gui.Row({
                        gap = 16,
                        children = {
                            gui.ListView({
                                id = "list",
                                items = items,
                                value = selected,
                                width = 280,
                                height = 500,
                            }),
                            gui.Table({
                                items = items,
                                height = 500,
                                width = 350,
                                columns = {
                                    { key = "label", label = "Label" },
                                    { key = "value", label = "Value" },
                                },
                            }),
                            gui.TreeView({
                                items = {
                                    {
                                        key = "root",
                                        label = "Root",
                                        children = {
                                            { key = "leaf", label = "Leaf" },
                                        },
                                    },
                                },
                                defaultExpanded = { root = true },
                                height = 500,
                                width = 200,
                            }),
                        },
                    }),
                },
                {
                    key = "visual",
                    label = "Visual",
                    content = gui.Column({
                        gap = 16,
                        children = {
                            gui.Image({
                                id = "image",
                                source = imagePath,
                                width = 80,
                                height = 80,
                                fit = "contain",
                                transform = { rotation = 0.1 },
                            }),
                            gui.Container({
                                width = 240,
                                height = 100,
                                overflow = "hidden",
                                transform = { rotation = 0.05 },
                                children = {
                                    gui.Canvas({
                                        width = 300,
                                        height = 120,
                                        onPaint = function(frame, b)
                                            canvasDraws += 1
                                            frame:pushClip({
                                                x = b.x,
                                                y = b.y,
                                                width = 200,
                                                height = 90,
                                            })
                                            frame:pushTransform({ x = 5, y = 5 })
                                            frame:rect({
                                                x = b.x,
                                                y = b.y,
                                                width = 280,
                                                height = 100,
                                                color = { 70, 120, 240 },
                                                radius = 12,
                                            })
                                            frame:text({
                                                text = "Native Canvas",
                                                font = sharedFont,
                                                x = b.x + 12,
                                                y = b.y + 12,
                                                color = { 255, 255, 255 },
                                            })
                                            frame:popTransform()
                                            frame:popClip()
                                        end,
                                    }),
                                },
                            }),
                        },
                    }),
                },
            },
        }),
        gui.Modal({
            open = open,
            title = "Native modal",
            children = {
                gui.Text({ text = "Focus is trapped" }),
                gui.Button({
                    id = "modal-button",
                    text = "Close",
                    onClick = function()
                        open:set(false)
                    end,
                }),
            },
        }),
    },
}))
second = gui.createApp({
    title = "XTGUI shared resource lifetime",
    width = 340,
    height = 180,
    onReady = function(app)
        local function finish()
            if not main.destroyed then
                app:after(0.05, finish)
                return
            end
            assert(
                not sharedFont:isDisposed() and not sharedImage:isDisposed(),
                "Closing one app disposed another app's resources"
            )
            app:invalidate()
            app:after(0.05, function()
                app:close()
            end)
        end
        app:after(0.1, finish)
    end,
})
second:render(gui.Column({
    padding = 20,
    children = {
        gui.Text({ text = "Other windows keep shared fonts alive." }),
        gui.Image({ source = imagePath, width = 40, height = 40 }),
    },
}))
second:after(15, function()
    error("multi-window integration timed out")
end)
gui.run({ main, second })
assert(stage >= 5 and canvasDraws > 0 and sharedFont:isDisposed() and sharedImage:isDisposed())
for _, state in ipairs({ tab, open, choice, selected }) do
    state:dispose()
end
print(
    "XTGUI native widget integration passed: images, canvas, overlays, virtualized views and shared cleanup"
)
