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
            return gui.Button({
                id = p.id,
                text = "Custom",
                onClick = p.onClick,
                ref = p.ref,
                width = "50%",
            })
        end, "Custom")
        local app = gui.createApp({ width = 400, height = 200 })
        app:render(gui.Column({
            children = {
                Custom({
                    id = "custom",
                    ref = ref,
                    onClick = function()
                        calls += 1
                    end,
                }),
            },
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
            app:render(gui.Stack({
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
            }))
            click(app, app:find("disabled"))
            assert(calls == 0)
            assert(not app:find("hidden"):focus())
            app:destroy()
        end
    )
    t.test("default radio groups are reachable and arrows select the next radio", function()
        local app = gui.createApp()
        app:render(gui.Column({
            children = {
                gui.RadioButton({ id = "one", group = "test", text = "One", defaultChecked = true }),
                gui.RadioButton({ id = "two", group = "test", text = "Two" }),
            },
        }))
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
            return gui.Text({
                id = "computed",
                ref = ref,
                width = 100,
                text = tostring(computed:get()),
            })
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
        app:render(gui.Grid({
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
        }))
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
        app:render(gui.Column({
            children = { Child({ id = "a", state = a }), Child({ id = "b", state = b }) },
        }))
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
    t.test("candidate constraints and invalid grid spans preserve the mounted tree", function()
        local app = gui.createApp({ width = 800, height = 400 })
        app:render(gui.Column({
            children = {
                gui.Container({
                    width = 100,
                    children = {
                        gui.Container({
                            id = "valid",
                            minWidth = "50%",
                            maxWidth = 100,
                            height = 20,
                        }),
                    },
                }),
            },
        }))
        local previous = app:find("valid")
        assert(previous.box.width == 100)
        local ok = pcall(function()
            app:render(gui.Grid({ columns = 1, children = { gui.Container({ columnSpan = 2 }) } }))
        end)
        assert(not ok and app:find("valid") == previous and previous.alive)
        previous:setProps({ minWidth = 200, maxWidth = 100 })
        assert(not pcall(function()
            app:flush()
        end))
        assert(previous.props.minWidth == "50%" and previous.rawProps.minWidth == "50%")
        previous:setProps({ height = 30 })
        app:flush()
        assert(previous.box.height == 30)
        app:destroy()
    end)
    t.test(
        "grid auto tracks measure content and invalid timeline play cancels partial work",
        function()
            local app = gui.createApp({ width = 300, height = 180 })
            app:render(gui.Grid({
                columns = { "auto", "1fr" },
                gap = 10,
                children = {
                    gui.Container({ id = "auto", width = 80, height = 30 }),
                    gui.Container({ id = "fraction", height = 30 }),
                },
            }))
            assert(app:find("auto").box.width == 80 and app:find("fraction").box.width == 210)
            local timeline = gui.timeline()
                :to(app:find("auto"), { opacity = 0.5 })
                :to(app:find("fraction"), { opacity = 3 })
            assert(not pcall(function()
                timeline:play()
            end))
            assert(not next(app._tweens))
            app:destroy()
        end
    )
    t.test("nested modals restore each opener and nested popup layers remain above them", function()
        local a, b = gui.state(false), gui.state(false)
        local app = gui.createApp({ width = 600, height = 500 })
        app:render(gui.Column({
            children = {
                gui.Button({
                    id = "outside",
                    text = "Open",
                    onClick = function()
                        a:set(true)
                    end,
                }),
                gui.Modal({
                    open = a,
                    children = {
                        gui.Button({
                            id = "inside-a",
                            text = "Nested",
                            onClick = function()
                                b:set(true)
                            end,
                        }),
                        gui.Modal({
                            open = b,
                            children = { gui.Select({ id = "inside-b", items = { "one", "two" } }) },
                        }),
                    },
                }),
            },
        }))
        click(app, app:find("outside"))
        click(app, app:find("inside-a"))
        assert(app.focus.current == app:find("inside-b"))
        app:dispatch({ type = "keyDown", key = "ArrowDown" })
        assert(#app._portals == 6)
        local last = app._portals[#app._portals]
        assert(last.props.zIndex == 1001)
        app:dispatch({ type = "keyDown", key = "Escape" })
        assert(b:get())
        app:dispatch({ type = "keyDown", key = "Escape" })
        assert(not b:get() and app.focus.current == app:find("inside-a"))
        app:dispatch({ type = "keyDown", key = "Escape" })
        assert(not a:get() and app.focus.current == app:find("outside"))
        app:destroy()
        a:dispose()
        b:dispose()
    end)
    t.test("popup anchors follow transformed bounds", function()
        local ref = gui.ref(nil)
        local app = gui.createApp({ width = 500, height = 400 })
        app:render(gui.Column({
            children = {
                gui.Button({
                    id = "anchor",
                    ref = ref,
                    text = "Anchor",
                    width = 100,
                    height = 30,
                    transform = { x = 50, y = 40 },
                }),
                gui.Popover({
                    id = "popup",
                    open = true,
                    anchor = ref,
                    width = 120,
                    children = { gui.Text({ text = "Popup" }) },
                }),
            },
        }))
        local popup = app:find("popup")
        assert(popup.box.x == 50 and popup.box.y == 74)
        app:destroy()
    end)
    t.test("component computed subscriptions are notified after prop commits", function()
        local source = gui.state(2)
        local exposed
        local Child = gui.component(function(p)
            exposed = gui.computed(function()
                return p.value * 2
            end)
            return gui.Text({ text = exposed:get() })
        end)
        local app = gui.createApp()
        app:render(function()
            return Child({ value = source:get() })
        end)
        local observed
        local stop = exposed:subscribe(function(v)
            observed = v
        end)
        source:set(3)
        app:flush()
        assert(observed == 6)
        stop()
        app:destroy()
        source:dispose()
    end)
    t.test("reactive disabled props apply across component boundaries", function()
        local disabled = gui.state(false)
        local calls = 0
        local Custom = gui.component(function()
            return gui.Button({
                id = "button",
                text = "Test",
                onClick = function()
                    calls += 1
                end,
            })
        end)
        local app = gui.createApp()
        app:render(Custom({ disabled = disabled }))
        click(app, app:find("button"))
        assert(calls == 1)
        disabled:set(true)
        app:flush()
        click(app, app:find("button"))
        assert(calls == 1 and app:find("button").disabled)
        app:destroy()
        disabled:dispose()
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
