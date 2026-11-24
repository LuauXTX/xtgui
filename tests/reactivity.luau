return function(t)
    local State = require("../src/core/State")
    local Scheduler = require("../src/core/Scheduler")
    local Component = require("../src/core/Component")
    local R = require("../src/core/Reconciler")
    local L = require("../src/layout/LayoutEngine")
    local Theme = require("../src/styling/Theme")
    local function app()
        local a = {
            options = {},
            api = { _hosts = { Column = true, Row = true, Text = true, Container = true } },
            _afterCommit = {},
            _afterLayout = {},
            width = 300,
            height = 200,
            theme = Theme.resolve("dark"),
            diagnostics = { layouts = 0 },
        }
        function a:_queue(node)
            self.pending = node
        end
        function a:_unmounted() end
        return a
    end
    local function host(kind, p)
        return { type = kind, props = p or {}, key = p and p.key }
    end
    t.test("computed dependency switching and batched subscriptions", function()
        local a, b, choose = State.new(1), State.new(2), State.new(true)
        local calls = 0
        local c = State.computed(function()
            calls += 1
            return choose:get() and a:get() or b:get()
        end)
        assert(c:get() == 1 and calls == 1)
        local observed = {}
        local unsub = c:subscribe(function(v)
            table.insert(observed, v)
        end)
        State.batch(function()
            a:set(3)
            a:set(4)
        end)
        assert(#observed == 1 and observed[1] == 4)
        choose:set(false)
        assert(c:get() == 2)
        a:set(8)
        assert(c:get() == 2)
        b:set(9)
        assert(c:get() == 9)
        unsub()
        c:dispose()
        a:dispose()
        b:dispose()
        choose:dispose()
    end)
    t.test("effect cleanup, cycle guard and disposed values", function()
        local state = State.new(0)
        local runs, cleanups = 0, 0
        local stop = State.effect(function()
            state:get()
            runs += 1
            return function()
                cleanups += 1
            end
        end)
        state:set(2)
        assert(runs == 2 and cleanups == 1)
        stop()
        assert(cleanups == 2)
        state:dispose()
        assert(not pcall(function()
            state:set(3)
        end))
        local c
        c = State.computed(function()
            return c:get()
        end)
        assert(not pcall(function()
            c:get()
        end))
        c:dispose()
        local looping = {}
        function looping:run()
            Scheduler.enqueue(self, function()
                self:run()
            end)
        end
        looping:run()
        assert(not pcall(Scheduler.flush))
        Scheduler.flush()
    end)
    t.test("keyed reconciliation retains elements and rejects duplicates atomically", function()
        local a = app()
        a.root = R.commit(
            a,
            R.prepare(
                a,
                nil,
                host(
                    "Column",
                    {
                        children = {
                            host("Container", { key = "a" }),
                            host("Container", { key = "b" }),
                        },
                    }
                )
            )
        )
        local first, second = a.root.children[1], a.root.children[2]
        a.root = R.commit(
            a,
            R.prepare(
                a,
                a.root,
                host(
                    "Column",
                    {
                        children = {
                            host("Container", { key = "b" }),
                            host("Container", { key = "a" }),
                        },
                    }
                )
            )
        )
        assert(a.root.children[1] == second and a.root.children[2] == first)
        assert(not pcall(function()
            R.prepare(
                a,
                a.root,
                host(
                    "Column",
                    { children = { host("Text", { key = "x" }), host("Text", { key = "x" }) } }
                )
            )
        end))
        assert(first.alive and a.root.children[1] == second)
        R.destroy(a.root)
    end)
    t.test("component hooks persist, track only readers, and dispose on unmount", function()
        local a = app()
        local localState
        local cleaned = 0
        local Counter = Component.new(function()
            localState = State.new(2)
            State.cleanup(function()
                cleaned += 1
            end)
            return host("Text", { text = tostring(localState:get()) })
        end, "Counter")
        a.root = R.commit(a, R.prepare(a, nil, Counter({})))
        local saved = localState
        local id = a.root.children[1].id
        saved:set(5)
        assert(a.pending == a.root)
        a.root = R.commit(a, R.prepare(a, a.root, Counter({})))
        assert(
            saved == localState
                and a.root.children[1].id == id
                and a.root.children[1].props.text == "5"
        )
        R.destroy(a.root)
        assert(cleaned == 1 and not pcall(function()
            saved:get()
        end))
    end)
    t.test("nested flex dimensions, min/max, percentage and grow", function()
        local a = app()
        a.root = R.commit(
            a,
            R.prepare(
                a,
                nil,
                host("Column", {
                    padding = 10,
                    gap = 10,
                    children = {
                        host("Row", {
                            height = 40,
                            gap = 10,
                            children = {
                                host("Container", { width = "50%" }),
                                host("Container", { flexGrow = 1, maxWidth = 80 }),
                            },
                        }),
                        host("Container", { flexGrow = 1 }),
                    },
                })
            )
        )
        L.run(a)
        local row = a.root.children[1]
        local grow = a.root.children[2]
        assert(row.box.width == 280 and row.box.height == 40)
        assert(row.children[1].box.width == 140 and row.children[2].box.width == 80)
        assert(grow.box.height == 130 and grow.box.y == 60)
        R.destroy(a.root)
    end)
end
