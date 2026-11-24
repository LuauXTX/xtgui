return function(t)
    local gui = require("../src/init")
    local function click(app, node)
        local b = node.box
        app:dispatch({ type = "mouseMove", x = b.x + b.width / 2, y = b.y + b.height / 2 })
        app:dispatch({ type = "mouseDown", button = "left" })
        app:dispatch({ type = "mouseUp", button = "left" })
    end
    t.test("public counter API and retained subtree updates", function()
        local app = gui.createApp({ width = 500, height = 300 })
        local count = gui.state(0)
        app:render(function(ui)
            return ui:Column({
                padding = 24,
                gap = 12,
                children = {
                    ui:Text({ text = "Hello", fontSize = 28 }),
                    ui:Button({
                        id = "counter",
                        text = "Clicked " .. count:get() .. " times",
                        onClick = function()
                            count:update(function(v)
                                return v + 1
                            end)
                        end,
                    }),
                },
            })
        end)
        local button = app:find("counter")
        click(app, button)
        assert(
            count:get() == 1
                and app:find("counter") == button
                and button.props.text == "Clicked 1 times"
        )
        app:destroy()
        count:dispose()
    end)
    t.test("keyboard navigation, cancellation, checkboxes and sliders", function()
        local app = gui.createApp()
        local checked = gui.state(false)
        local value = gui.state(0)
        app:render(gui.Column({
            children = {
                gui.Checkbox({ id = "check", checked = checked, text = "Enable" }),
                gui.Slider({ id = "slider", value = value, min = 0, max = 10, step = 1 }),
                gui.Button({
                    text = "Blocked",
                    onClick = function(e)
                        e:preventDefault()
                    end,
                }),
            },
        }))
        app:dispatch({ type = "keyDown", key = "Tab" })
        assert(app.focus.current == app:find("check"))
        app:dispatch({ type = "keyDown", key = " " })
        app:dispatch({ type = "keyUp", key = " " })
        assert(checked:get())
        app:dispatch({ type = "keyDown", key = "Tab" })
        app:dispatch({ type = "keyDown", key = "ArrowRight" })
        assert(value:get() == 1)
        app:destroy()
        checked:dispose()
        value:dispose()
    end)
    t.test("Unicode input, clipboard, undo, composition and caret", function()
        local app = gui.createApp()
        local text = gui.state("")
        app:render(
            gui.Column({
                children = {
                    gui.TextArea({ id = "editor", value = text, width = 300, height = 100 }),
                },
            })
        )
        app:find("editor"):focus()
        app:dispatch({ type = "textInput", text = "aé👩‍💻" })
        assert(text:get() == "aé👩‍💻")
        app:dispatch({ type = "keyDown", key = "Backspace" })
        assert(text:get() == "aé")
        app:dispatch({ type = "keyDown", key = "a", modifiers = { control = true } })
        app:dispatch({ type = "keyDown", key = "c", modifiers = { control = true } })
        app:dispatch({ type = "keyDown", key = "End" })
        app:dispatch({ type = "keyDown", key = "v", modifiers = { control = true } })
        assert(text:get() == "aéaé")
        app:dispatch({ type = "keyDown", key = "z", modifiers = { control = true } })
        assert(text:get() == "aé")
        app:dispatch({ type = "imeComposition", text = "日本", cursorEnd = 6 })
        assert(text:get() == "aé" and app:find("editor").data.editor.composition == "日本")
        app:dispatch({ type = "textInput", text = "日本", ime = true })
        assert(text:get() == "aé日本")
        app:destroy()
        text:dispose()
    end)
    t.test("stacking, transformed hit testing, clipping and event order", function()
        local app = gui.createApp({ width = 300, height = 200 })
        local order = {}
        app:render(gui.Stack({
            onClickCapture = function()
                table.insert(order, "capture")
            end,
            onClick = function()
                table.insert(order, "bubble")
            end,
            children = {
                gui.Button({
                    id = "back",
                    width = 80,
                    height = 40,
                    onClick = function()
                        table.insert(order, "back")
                    end,
                }),
                gui.Button({
                    id = "front",
                    width = 80,
                    height = 40,
                    zIndex = 2,
                    transform = { x = 20, y = 20 },
                    onClick = function()
                        table.insert(order, "front")
                    end,
                }),
            },
        }))
        app:dispatch({ type = "mouseMove", x = 30, y = 30 })
        app:dispatch({ type = "mouseDown", button = "left" })
        app:dispatch({ type = "mouseUp", button = "left" })
        assert(table.concat(order, ",") == "capture,front,bubble")
        app:destroy()
    end)
    t.test("failed render retains mounted tree and missing resources fail clearly", function()
        local app = gui.createApp()
        app:render(gui.Text({ id = "valid", text = "Keep" }))
        local old = app.root
        assert(not pcall(function()
            app:render(gui.Text({ text = "Bad", minWidth = 200, maxWidth = 10 }))
        end))
        assert(app.root == old and app:find("valid"))
        assert(not pcall(function()
            app:render(gui.Image({ source = "missing-xtgui-image.png" }))
        end))
        assert(app:find("valid"))
        app:destroy()
    end)
end
