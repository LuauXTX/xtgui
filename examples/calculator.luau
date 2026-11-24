local gui = require("../src/init")
local support = require("./support")
local display = gui.state("0")
local accumulator, operation, fresh = nil, nil, true
local function calculate(left, right, op)
    if op == "+" then
        return left + right
    elseif op == "−" then
        return left - right
    elseif op == "×" then
        return left * right
    elseif op == "÷" then
        assert(right ~= 0, "Division by zero")
        return left / right
    end
    return right
end
local function formatted(value)
    assert(value == value and math.abs(value) < math.huge, "Result is not finite")
    return string.format("%.12g", value)
end
local function press(key)
    local ok, result = pcall(function()
        local current = display:get()
        if key:match("^%d$") then
            display:set(
                (fresh or current == "0") and key or (#current < 16 and current .. key or current)
            )
            fresh = false
        elseif key == "." then
            if fresh then
                display:set("0.")
                fresh = false
            elseif not current:find(".", 1, true) then
                display:set(current .. ".")
            end
        elseif key == "C" then
            display:set("0")
            accumulator = nil
            operation = nil
            fresh = true
        elseif key == "⌫" then
            if not fresh then
                display:set(#current > 1 and current:sub(1, -2) or "0")
            end
        elseif key == "±" then
            display:set(formatted(-(tonumber(current) or 0)))
        elseif key == "%" then
            display:set(formatted((tonumber(current) or 0) / 100))
        else
            local value = assert(tonumber(current), "Clear the error first")
            if operation and accumulator and not fresh then
                value = calculate(accumulator, value, operation)
                display:set(formatted(value))
            end
            accumulator = value
            operation = key == "=" and nil or key
            fresh = true
        end
    end)
    if not ok then
        display:set("Error")
        accumulator = nil
        operation = nil
        fresh = true
    end
end
local app = gui.createApp({ title = "XTGUI Calculator", width = 360, height = 470, theme = "dark" })
local keys = {
    "C",
    "±",
    "%",
    "÷",
    "7",
    "8",
    "9",
    "×",
    "4",
    "5",
    "6",
    "−",
    "1",
    "2",
    "3",
    "+",
    "⌫",
    "0",
    ".",
    "=",
}
app:render(function(ui)
    local buttons = {}
    for _, key in ipairs(keys) do
        table.insert(
            buttons,
            ui:Button({
                key = key,
                id = "key-" .. key,
                text = key,
                fontSize = 22,
                height = 52,
                background = key == "=" and "$primary" or "$surface",
                onClick = function()
                    press(key)
                end,
            })
        )
    end
    return ui:Column({
        padding = 20,
        gap = 14,
        onKeyDown = function(e)
            local aliases = {
                Enter = "=",
                Backspace = "⌫",
                Escape = "C",
                ["*"] = "×",
                ["/"] = "÷",
                ["-"] = "−",
            }
            local key = aliases[e.key] or e.key
            if key:match("^[%d%.%%+]$") or aliases[e.key] then
                press(key)
                e:preventDefault()
            end
        end,
        children = {
            ui:Container({
                height = 72,
                padding = 12,
                background = "$surface",
                radius = 8,
                overflow = "hidden",
                children = {
                    ui:Text({
                        text = display:get(),
                        fontSize = 32,
                        textAlign = "end",
                        wrap = false,
                    }),
                },
            }),
            ui:Grid({ columns = 4, gap = 8, children = buttons }),
            ui:Text({
                text = "Keyboard: digits, + − × ÷, Enter, Esc",
                fontSize = 12,
                color = "$muted",
            }),
        },
    })
end)
support.run(app, "calculator", function()
    press("2")
    press("+")
    press("3")
    press("=")
    assert(display:get() == "5")
end)
display:dispose()
