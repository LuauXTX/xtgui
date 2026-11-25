return function(t)
    local gui = require("../src/init")
    t.test("empty application consumes initial layout work without a render tree", function()
        local app = gui.createApp({ width = 320, height = 200 })
        local ok, err = pcall(function()
            app:flush()
            assert(not app._needsLayout and not app._needsStyles)
            app:flush()
            assert(app.diagnostics.layouts == 0 and not next(app._pending))
            app:resize(360, 240)
            app:flush()
            app:render(function()
                return nil
            end)
            app:flush()
        end)
        app:destroy()
        assert(ok, tostring(err))
    end)
    t.test(
        "effects track dependencies without feeding owner rerenders back into themselves",
        function()
            local app = gui.createApp()
            local dependency, unrelated = gui.state(1), gui.state(0)
            local localState, firstState
            local runs, cleanups = 0, 0
            local Counter = gui.component(function(p)
                localState = gui.state(7)
                local derived = gui.state({ value = 0 })
                gui.effect(function()
                    runs += 1
                    derived:set({ value = dependency:get() * p.factor })
                    return function()
                        cleanups += 1
                    end
                end)
                return gui.Text({
                    id = "effect-counter",
                    text = derived:get().value .. ":" .. localState:get() .. ":" .. unrelated:get(),
                })
            end, "EffectCounter")
            app:render(Counter({ factor = 2 }))
            firstState = localState
            assert(runs == 1 and app:find("effect-counter").props.text == "2:7:0")
            unrelated:set(1)
            app:flush()
            assert(runs == 1 and localState == firstState)
            localState:set(8)
            app:flush()
            assert(localState == firstState and runs == 1)
            dependency:set(3)
            app:flush()
            assert(runs == 2 and cleanups == 1 and app:find("effect-counter").props.text == "6:8:1")
            app:render(Counter({ factor = 3 }))
            assert(
                runs == 3
                    and localState == firstState
                    and app:find("effect-counter").props.text == "9:8:1"
            )
            app:destroy()
            assert(cleanups == 3)
            dependency:dispose()
            unrelated:dispose()
        end
    )
    t.test("owned effects observe the latest committed layout after dependency changes", function()
        local app = gui.createApp({ width = 400 })
        local width = gui.state(80)
        local runs = 0
        local View = gui.component(function()
            gui.effect(function()
                assert(app:find("measured").box.width == width:get(), "effect ran before layout")
                runs += 1
            end)
            return gui.Container({ id = "measured", width = width:get(), height = 40 })
        end, "MeasuredEffect")
        app:render(View({}))
        width:set(120)
        app:flush()
        assert(runs == 2)
        app:flush()
        assert(runs == 2)
        app:destroy()
        width:dispose()
    end)
    t.test("tracked effects can converge and removing the final root clears layout work", function()
        local app = gui.createApp()
        local state
        local View = gui.component(function()
            state = gui.state(0)
            gui.effect(function()
                local value = state:get()
                if value < 3 then
                    state:set(value + 1)
                end
            end)
            return gui.Text({ id = "converged", text = state:get() })
        end, "ConvergingEffect")
        app:render(View({}))
        assert(state:get() == 3 and app:find("converged").props.text == 3)
        app.root:destroy()
        app:flush()
        assert(
            app.root == nil and #app._visual == 0 and #app._portals == 0 and not app._needsLayout
        )
        app:destroy()
    end)
    t.test("unchanged state props resize and stable refs do not enqueue updates", function()
        local app = gui.createApp({ width = 400, height = 200 })
        local value = gui.state("same")
        local refs, layouts = 0, 0
        local stableRef = function(node)
            if node then
                refs += 1
            end
        end
        app:render(gui.Container({
            id = "stable",
            width = 100,
            height = 40,
            ref = stableRef,
            onLayout = function()
                layouts += 1
            end,
            children = { gui.Text({ text = value }) },
        }))
        local node = app:find("stable")
        local before = app.diagnostics.layouts
        assert(value:set("same") == false)
        node:setProps({ width = 100, height = 40 })
        app:resize(400, 200)
        app:flush()
        assert(app.diagnostics.layouts == before and not next(app._pending))
        node:setProps({ width = 120 })
        app:flush()
        assert(refs == 1 and layouts == 2)
        app:destroy()
        value:dispose()
    end)
    t.test("portal relayout reports only final changed bounds", function()
        local app = gui.createApp({ width = 500, height = 300 })
        local anchor = gui.ref(nil)
        local calls, last = 0, nil
        app:render(gui.Column({
            children = {
                gui.Button({
                    ref = anchor,
                    width = 100,
                    height = 30,
                    transform = { x = 50, y = 40 },
                }),
                gui.Container({
                    id = "anchored",
                    portal = true,
                    position = "absolute",
                    anchor = anchor,
                    width = 120,
                    height = 40,
                    onLayout = function(bounds)
                        calls += 1
                        last = bounds
                    end,
                }),
            },
        }))
        assert(calls == 1 and last.x == 50 and last.y == 74)
        app:_layout(app.root)
        app:flush()
        assert(calls == 1, "unchanged final portal bounds emitted onLayout again")
        app:destroy()
    end)
    t.test("real effect feedback reports its component hook and causal state", function()
        local app = gui.createApp()
        local Loop = gui.component(function()
            local count = gui.state(0)
            gui.effect(function()
                count:set(count:get() + 1)
            end)
            return gui.Text({ text = count:get() })
        end, "FeedbackComponent")
        local ok, err = pcall(function()
            app:render(Loop({}))
        end)
        local report = app.diagnostics.lastUpdateLoop
        assert(not ok and tostring(err):find("100 passes", 1, true))
        assert(
            tostring(err):find("FeedbackComponent", 1, true)
                and tostring(err):find("effect", 1, true)
                and tostring(err):find("state", 1, true)
        )
        assert(report and report.pass == 100 and #report.sources <= 64 and #report.recent <= 24)
        app:destroy()
        assert(require("../src/core/Diagnostics").current == nil)
    end)
    t.test("oscillating layout diagnostics identify the responsible node and callback", function()
        local app = gui.createApp()
        local ok, err = pcall(function()
            app:render(gui.Container({
                id = "oscillating-layout",
                width = 50,
                height = 40,
                onLayout = function(bounds, node)
                    node:setProps({ width = bounds.width == 50 and 60 or 50 })
                end,
            }))
        end)
        assert(
            not ok
                and tostring(err):find("oscillating-layout", 1, true)
                and tostring(err):find("onLayout", 1, true),
            tostring(err)
        )
        assert(app.diagnostics.flushPasses == 100)
        app:destroy()
    end)
end
