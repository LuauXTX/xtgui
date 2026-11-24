local gui = require("../src/init")
local support = require("./support")
local app =
    gui.createApp({ title = "XTGUI Component Gallery", width = 1040, height = 760, theme = "dark" })
local name, checked, volume = gui.state("LuauXTX"), gui.state(true), gui.state(45)
local choice, modal, selected = gui.state("Stable"), gui.state(false), gui.state(nil)
local records = {}
for i = 1, 10000 do
    records[i] = {
        key = i,
        name = "Package " .. i,
        version = "1." .. (i % 10) .. ".0",
        status = i % 3 == 0 and "Testing" or "Ready",
    }
end
local font = app:loadFont(nil, 14)

local Controls = gui.component(function()
    local controls = gui.Column({
        width = 340,
        gap = 14,
        children = {
            gui.Text({ text = "Controls", fontSize = 22 }),
            gui.TextInput({ id = "name", value = name, placeholder = "Your application" }),
            gui.Checkbox({ checked = checked, text = "Enable preview" }),
            gui.Switch({ text = "Live updates", checked = checked }),
            gui.Row({
                gap = 12,
                children = {
                    gui.RadioButton({ group = "channel", text = "Stable", defaultChecked = true }),
                    gui.RadioButton({ group = "channel", text = "Preview" }),
                },
            }),
            gui.Select({
                id = "channel",
                value = choice,
                items = { "Stable", "Preview", "Nightly" },
                width = 280,
            }),
            gui.Slider({ value = volume, min = 0, max = 100, step = 1, width = 300 }),
            gui.ProgressBar({ value = volume, min = 0, max = 100, height = 10 }),
            gui.Button({
                text = "Open modal",
                onClick = function()
                    modal:set(true)
                end,
                transition = { duration = 0.16 },
                hoverStyle = { background = "$primary" },
            }),
            gui.Popover({
                trigger = gui.Button({ text = "Show popover" }),
                children = {
                    gui.Text({ text = "Rendered above ancestor clips." }),
                    gui.Button({ text = "Focusable action" }),
                },
            }),
        },
    })
    local graphics = gui.Column({
        flexGrow = 1,
        gap = 14,
        children = {
            gui.Text({ text = "Custom drawing & scrolling", fontSize = 22 }),
            gui.Canvas({
                height = 200,
                background = "$surface",
                radius = 8,
                onPaint = function(frame, b)
                    for i = 0, 7 do
                        frame:rect({
                            x = b.x + 20 + i * 48,
                            y = b.y + 160 - i * 13,
                            width = 32,
                            height = 20 + i * 13,
                            color = { 50 + i * 18, 110, 225 },
                            radius = 4,
                        })
                    end
                    frame:text({
                        text = "Canvas: " .. name:get(),
                        font = font,
                        x = b.x + 20,
                        y = b.y + 14,
                        color = { 235, 240, 255 },
                    })
                end,
            }),
            gui.ScrollView({
                height = 180,
                background = "$surface",
                padding = 12,
                children = {
                    gui.Text({
                        text = string.rep(
                            "Scroll and resize — clips stay in logical pixels.\n",
                            20
                        ),
                    }),
                },
            }),
        },
    })
    return gui.Row({ gap = 24, children = { controls, graphics } })
end, "GalleryControls")

local function treeDemo()
    local tree = gui.TreeView({
        height = 500,
        items = {
            {
                key = "src",
                label = "src",
                children = {
                    {
                        key = "core",
                        label = "core",
                        children = {
                            { key = "state", label = "State.luau" },
                            { key = "app", label = "Application.luau" },
                        },
                    },
                    { key = "components", label = "components" },
                },
            },
            { key = "tests", label = "tests" },
        },
    })
    local details = gui.ContextMenu({
        items = {
            {
                label = "Inspect",
                value = "inspect",
                onSelect = function()
                    modal:set(true)
                end,
            },
        },
        children = {
            gui.Column({
                padding = 20,
                gap = 12,
                children = {
                    gui.Text({ text = "Drag the divider", fontSize = 22 }),
                    gui.Text({
                        text = "Or focus it and use arrow keys. Right-click here for a context menu.",
                    }),
                    gui.Accordion({
                        items = {
                            {
                                key = "layout",
                                label = "Layout",
                                content = gui.Text({
                                    text = "Rows, columns, grids and absolute positioning.",
                                }),
                            },
                            {
                                key = "input",
                                label = "Input",
                                content = gui.Text({
                                    text = "Capture, bubbling, pointer capture and keyboard focus.",
                                }),
                            },
                        },
                    }),
                },
            }),
        },
    })
    return gui.SplitPane({
        height = 500,
        ratio = 0.4,
        minFirst = 160,
        minSecond = 180,
        children = {
            tree,
            details,
        },
    })
end

app:render(function(ui)
    return ui:Column({
        padding = 24,
        gap = 16,
        children = {
            ui:Row({
                gap = 16,
                alignItems = "center",
                children = {
                    ui:Column({
                        flexGrow = 1,
                        children = {
                            ui:Text({ text = "XTGUI", fontSize = 30 }),
                            ui:Text({
                                text = "Retained UI • reactive state • native graphics",
                                color = "$muted",
                            }),
                        },
                    }),
                    ui:Tooltip({
                        text = "External Luau components can supply their own UI systems.",
                        children = {
                            ui:Button({
                                text = "About",
                                onClick = function()
                                    modal:set(true)
                                end,
                            }),
                        },
                    }),
                },
            }),
            ui:Tabs({
                height = 580,
                tabs = {
                    { key = "controls", label = "Controls & Canvas", content = Controls({}) },
                    {
                        key = "data",
                        label = "Virtualized Data",
                        content = ui:Table({
                            id = "packages",
                            height = 520,
                            sortable = true,
                            items = records,
                            value = selected,
                            columns = {
                                { key = "name", label = "Package", grow = 2 },
                                { key = "version", label = "Version", grow = 1 },
                                { key = "status", label = "Status", grow = 1 },
                            },
                        }),
                    },
                    { key = "tree", label = "Tree & SplitPane", content = treeDemo() },
                },
            }),
            ui:Modal({
                open = modal,
                title = "About XTGUI",
                children = {
                    ui:Text({ text = "GUI design stays in Luau.", fontSize = 24 }),
                    ui:Text({
                        text = "Native gfx provides windows, text, input and draw primitives. XTGUI supplies the retained tree and controls.",
                    }),
                    ui:Button({
                        text = "Close",
                        onClick = function()
                            modal:set(false)
                        end,
                    }),
                },
            }),
        },
    })
end)
support.run(app, "gallery", function(a)
    assert(a:find("channel") and a.diagnostics.paint.commands > 0)
end)
for _, state in ipairs({ name, checked, volume, choice, modal, selected }) do
    state:dispose()
end
