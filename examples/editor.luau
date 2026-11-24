local gui = require("../src/init")
local fs = require("@luauxtx/system/fs")
local task = require("@luauxtx/async/task")
local support = require("./support")
local content = gui.state(
    "Welcome to XTGUI.\n\nUnicode: café — 日本語 — 👩‍💻\n\nTry selection, Ctrl/Cmd+A, C, V, Z, and Shift+Z.\nClipboard defaults to this process; see the clipboard provider documentation.\n"
)
local path = gui.state("")
local status = gui.state("Untitled document")
local busy = gui.state(false)
local changed = gui.state(false)
local closing = gui.state(false)
local app
local function fileAction(save)
    if busy:get() then
        return
    end
    local destination = path:get()
    if destination == "" then
        status:set("Enter a file path first.")
        return
    end
    busy:set(true)
    task.spawn(function()
        local ok, result = pcall(function()
            if save then
                fs.write(destination, content:get()):await()
                return "Saved " .. destination
            end
            local text = fs.read(destination):await()
            content:set(text)
            return "Opened " .. destination
        end)
        if app.destroyed then
            return
        end
        if ok then
            changed:set(false)
            status:set(result)
        else
            status:set("File error: " .. tostring(result))
        end
        busy:set(false)
    end)
end
app = gui.createApp({
    title = "XTGUI Text Editor",
    width = 900,
    height = 620,
    onClose = function()
        if changed:get() then
            closing:set(true)
            return false
        end
        return true
    end,
})
app:shortcut("mod+s", function()
    fileAction(true)
end)
app:shortcut("mod+o", function()
    fileAction(false)
end)
app:render(function(ui)
    local text = content:get()
    local _, newlines = text:gsub("\n", "")
    return ui:Column({
        padding = 16,
        gap = 12,
        children = {
            ui:Row({
                gap = 8,
                alignItems = "center",
                children = {
                    ui:TextInput({
                        value = path,
                        placeholder = "Path to a UTF-8 text file",
                        flexGrow = 1,
                    }),
                    ui:Button({
                        text = "Open",
                        disabled = busy,
                        onClick = function()
                            fileAction(false)
                        end,
                    }),
                    ui:Button({
                        text = "Save",
                        disabled = busy,
                        onClick = function()
                            fileAction(true)
                        end,
                    }),
                },
            }),
            ui:TextArea({
                id = "document",
                value = content,
                flexGrow = 1,
                fontSize = 16,
                wrap = true,
                onChange = function()
                    changed:set(true)
                end,
                ariaLabel = "Document",
            }),
            ui:Row({
                gap = 12,
                children = {
                    ui:Text({ text = status:get(), flexGrow = 1, color = "$muted", fontSize = 13 }),
                    ui:Text({
                        text = tostring(newlines + 1)
                            .. " lines"
                            .. (changed:get() and " • modified" or ""),
                        fontSize = 13,
                        color = "$muted",
                    }),
                },
            }),
            ui:Modal({
                open = closing,
                title = "Unsaved changes",
                children = {
                    ui:Text({ text = "Discard unsaved changes?", fontSize = 22 }),
                    ui:Row({
                        gap = 8,
                        children = {
                            ui:Button({
                                text = "Keep editing",
                                onClick = function()
                                    closing:set(false)
                                end,
                            }),
                            ui:Button({
                                text = "Discard and close",
                                background = "$danger",
                                onClick = function()
                                    app:close()
                                end,
                            }),
                        },
                    }),
                },
            }),
        },
    })
end)
support.run(app, "editor", function(a)
    a:find("document"):focus()
    a:dispatch({ type = "textInput", text = "test" })
    assert(changed:get())
end)
-- Outstanding async I/O may still finish; its completion checks app.destroyed.
for _, state in ipairs({ content, path, status, busy, changed, closing }) do
    state:dispose()
end
