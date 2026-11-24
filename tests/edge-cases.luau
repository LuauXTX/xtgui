return function(t)
    local gui = require("../src/init")
    local Layout = require("../src/layout/LayoutEngine")
    local U = require("../src/input/Unicode")
    local Editing = require("../src/input/TextEditing")
    local function click(app, node)
        local b = node.box
        app:dispatch({ type = "mouseMove", x = b.x + b.width / 2, y = b.y + b.height / 2 })
        app:dispatch({ type = "mouseDown", button = "left" })
        app:dispatch({ type = "mouseUp", button = "left" })
    end
    t.test("custom components forward refs and events exactly once", function()
        local calls = 0
        local ref = gui.ref(nil)
        local Custom = gui.component(function(p)
            return gui.Button({ id = p.id, text = "Custom", onClick = p.onClick, ref = p.ref, width = "50%" })
        end, "Custom")
        local app = gui.createApp({ width = 400, height = 200 })
        app:render(gui.Column({
            children = { Custom({
                id = "custom",
                ref = ref,
                onClick = function()
                    calls += 1
                end,
            }) },
        }))
        assert(ref.current == app:find("custom") and ref.current.box.width == 200)
        click(app, ref.current)
        assert(calls == 1)
        app:destroy()
        assert(ref.current == nil)
    end)
    t.test("root keyboard events work without an initially focused control", function()
        local calls = 0
        local app = gui.createApp()
        app:render(gui.Column({
            onKeyDown = function(e)
                if e.key == "2" then
                    calls += 1
                    e:preventDefault()
                end
            end,
        }))
        app:dispatch({ type = "keyDown", key = "2" })
        assert(calls == 1)
        app:destroy()
    end)
    t.test(
        "disabled controls block overlapping controls and hidden controls cannot focus",
        function()
            local calls = 0
            local app = gui.createApp()
            app:render(
                gui.Stack({
                    children = {
                        gui.Button({
                            id = "back",
                            text = "Back",
                            width = 100,
                            height = 40,
                            onClick = function()
                                calls += 1
                            end,
                        }),
                        gui.Button({
                            id = "disabled",
                            text = "Disabled",
                            width = 100,
                            height = 40,
                            disabled = true,
                            onClick = function()
                                calls += 10
                            end,
                        }),
                        gui.Container({
                            display = "none",
                            children = { gui.Button({ id = "hidden", text = "Hidden" }) },
                        }),
                    },
                })
            )
            click(app, app:find("disabled"))
            assert(calls == 0)
            assert(not app:find("hidden"):focus())
            app:destroy()
        end
    )
    t.test("default radio groups are reachable and arrows select the next radio", function()
        local app = gui.createApp()
        app:render(
            gui.Column({
                children = {
                    gui.RadioButton({ id = "one", group = "test", text = "One", defaultChecked = true }),
                    gui.RadioButton({ id = "two", group = "test", text = "Two" }),
                },
            })
        )
        app:dispatch({ type = "keyDown", key = "Tab" })
        assert(app.focus.current == app:find("one"))
        app:dispatch({ type = "keyDown", key = "ArrowDown" })
        assert(app.focus.current == app:find("two") and app:find("two").data.checked == true)
        app:destroy()
    end)
    t.test("hover events follow ancestor order without duplicate bubbling", function()
        local order = {}
        local app = gui.createApp()
        app:render(gui.Column({
            onMouseEnter = function()
                table.insert(order, "parent")
            end,
            children = {
                gui.Button({
                    id = "child",
                    text = "Child",
                    onMouseEnter = function()
                        table.insert(order, "child")
                    end,
                }),
            },
        }))
        local b = app:find("child").box
        app:dispatch({ type = "mouseMove", x = b.x + 2, y = b.y + 2 })
        assert(table.concat(order, ",") == "parent,child")
        app:destroy()
    end)
    t.test("mount effects see layout and component computed values refresh from props", function()
        local seen = 0
        local ref = gui.ref(nil)
        local cleaned = 0
        local external = gui.state(2)
        local Child = gui.component(function(p)
            local computed = gui.computed(function()
                return p.number * 2
            end)
            gui.effect(function()
                assert(ref.current.box.width == 100)
                seen += 1
                return function()
                    cleaned += 1
                end
            end)
            return gui.Text({ id = "computed", ref = ref, width = 100, text = tostring(
                computed:get()
            ) })
        end)
        local app = gui.createApp()
        app:render(function()
            return gui.Column({ children = { Child({ number = external:get() }) } })
        end)
        assert(seen == 1 and app:find("computed").props.text == "4")
        external:set(3)
        app:flush()
        assert(app:find("computed").props.text == "6" and cleaned == 1)
        app:destroy()
        assert(cleaned == 2)
        external:dispose()
    end)
    t.test("grid track sizes, spans, absolute anchors and percentage components", function()
        local app = gui.createApp({ width = 400, height = 200 })
        app:render(
            gui.Grid({
                columns = { 100, "1fr", "1fr" },
                gap = 10,
                children = {
                    gui.Container({ id = "span", columnSpan = 2, height = 30 }),
                    gui.Container({ id = "cell", height = 30 }),
                    gui.Container({
                        id = "absolute",
                        position = "absolute",
                        right = 10,
                        bottom = 10,
                        width = 20,
                        height = 20,
                    }),
                },
            })
        )
        assert(app:find("span").box.width == 250 and app:find("cell").box.x == 260)
        assert(app:find("absolute").box.x == 370 and app:find("absolute").box.y == 170)
        app:destroy()
    end)
    t.test("graphemes, multiline editing, read-only and selection limits", function()
        assert(#U.split("é👩‍💻🇺🇸é") == 4)
        local editor = Editing.new("one\ntwo", true)
        local app = { options = {} }
        editor:move(0, false)
        editor:move(3, true)
        assert(editor:selection() == "one")
        assert(not editor:replace("bad", { readOnly = true }))
        assert(editor:replace("é", { maxLength = 6 }))
        assert(editor.text == "é\ntwo")
        editor:key("a", { control = true }, nil, {}, app)
        editor:key("x", { control = true }, nil, {}, app)
        assert(editor.text == "")
        editor:key("v", { control = true }, nil, {}, app)
        assert(editor.text == "é\ntwo")
        assert(editor:undo(false) and editor.text == "")
    end)
    t.test("unchanged siblings do not rerender and layout caches stay reusable", function()
        local a, b = gui.state(1), gui.state(1)
        local Child = gui.component(function(p)
            return gui.Text({ id = p.id, text = p.state:get() })
        end)
        local app = gui.createApp()
        app:render(
            gui.Column({ children = { Child({ id = "a", state = a }), Child({ id = "b", state = b }) } })
        )
        local left, right = app:find("a"), app:find("b")
        local count = right.renderCount
        local cache = right.measureCache
        a:set(2)
        app:flush()
        assert(left.props.text == 2 and right.renderCount == count and right.measureCache == cache)
        app:destroy()
        a:dispose()
        b:dispose()
    end)
    t.test("cleanup failures still dispose sibling state and native resources", function()
        local disposed
        local Child = gui.component(function()
            disposed = gui.state(1)
            gui.onCleanup(function()
                error("intentional cleanup failure")
            end)
            return gui.Text({ text = "cleanup" })
        end)
        local app = gui.createApp()
        local font = app:loadFont(nil, 19)
        app:render(Child({}))
        local ok, err = pcall(function()
            app:destroy()
        end)
        assert(
            not ok and tostring(err):find("intentional cleanup failure", 1, true) and app.destroyed
        )
        assert(not pcall(function()
            disposed:get()
        end) and font:isDisposed())
    end)
end
