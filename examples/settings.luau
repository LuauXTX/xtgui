local gui = require("../src/init")
local support = require("./support")
local name = gui.state("Luau Developer")
local notifications = gui.state(true)
local telemetry = gui.state(false)
local volume = gui.state(65)
local theme = gui.state("dark")
local language = gui.state("English")
local saved = gui.state(false)
local app = gui.createApp({ title = "XTGUI Settings", width = 740, height = 540 })
app:render(function(ui)
    gui.effect(function()
        app:setTheme(theme:get())
    end)
    return ui:Column({
        padding = 24,
        gap = 16,
        children = {
            ui:Text({ text = "Settings", fontSize = 28 }),
            ui:Tabs({
                height = 360,
                tabs = {
                    {
                        key = "general",
                        label = "General",
                        content = ui:Column({
                            padding = 8,
                            gap = 16,
                            children = {
                                ui:Text({ text = "Display name" }),
                                ui:TextInput({
                                    id = "name",
                                    value = name,
                                    placeholder = "Your name",
                                    width = 320,
                                }),
                                ui:Switch({
                                    text = "Desktop notifications",
                                    checked = notifications,
                                }),
                                ui:Checkbox({
                                    text = "Share anonymous diagnostics",
                                    checked = telemetry,
                                }),
                                ui:Row({
                                    gap = 16,
                                    alignItems = "center",
                                    children = {
                                        ui:Text({ text = "Volume", width = 90 }),
                                        ui:Slider({
                                            value = volume,
                                            min = 0,
                                            max = 100,
                                            step = 1,
                                            width = 260,
                                        }),
                                        ui:Text({ text = volume:get() .. "%", width = 50 }),
                                    },
                                }),
                                ui:Row({
                                    gap = 16,
                                    alignItems = "center",
                                    children = {
                                        ui:Text({ text = "Language", width = 90 }),
                                        ui:Select({
                                            value = language,
                                            items = { "English", "Español", "日本語" },
                                            width = 220,
                                        }),
                                    },
                                }),
                            },
                        }),
                    },
                    {
                        key = "appearance",
                        label = "Appearance",
                        content = ui:Column({
                            padding = 8,
                            gap = 16,
                            children = {
                                ui:Text({ text = "Color theme" }),
                                ui:Select({
                                    id = "theme",
                                    value = theme,
                                    items = {
                                        { label = "Dark", value = "dark" },
                                        { label = "Light", value = "light" },
                                    },
                                }),
                                ui:Text({
                                    text = "XTGUI inherits theme tokens through the retained tree.",
                                    color = "$muted",
                                }),
                            },
                        }),
                    },
                },
            }),
            ui:Row({
                justifyContent = "end",
                children = {
                    ui:Button({
                        id = "save",
                        text = "Apply settings",
                        background = "$primary",
                        onClick = function()
                            saved:set(true)
                        end,
                    }),
                },
            }),
            ui:Modal({
                open = saved,
                title = "Settings applied",
                children = {
                    ui:Text({ text = "Settings applied for this session.", fontSize = 20 }),
                    ui:Text({ text = "This example does not write user configuration." }),
                    ui:Button({
                        text = "Done",
                        onClick = function()
                            saved:set(false)
                        end,
                    }),
                },
            }),
        },
    })
end)
support.run(app, "settings", function(a)
    a:find("name"):focus()
    a:dispatch({ type = "textInput", text = " ✓" })
    assert(name:get():find("✓", 1, true))
end)
for _, state in ipairs({ name, notifications, telemetry, volume, theme, language, saved }) do
    state:dispose()
end
