local Support = {}
function Support.smoke()
    for _, argument in ipairs(process.argv) do
        if argument == "--smoke" then
            return true
        end
    end
    return false
end
function Support.run(app, name, verify)
    if Support.smoke() then
        local ready = app.options.onReady
        app.options.onReady = function(a)
            if ready then
                ready(a)
            end
            a:after(0.2, function()
                assert(a.diagnostics.frames > 0, "Example did not paint")
                if verify then
                    verify(a)
                end
                a:close()
            end)
        end
        app:after(20, function()
            error("Example smoke test timed out: " .. name)
        end)
    end
    app:run()
    if Support.smoke() then
        print("XTGUI example passed: " .. name)
    end
end
return Support
