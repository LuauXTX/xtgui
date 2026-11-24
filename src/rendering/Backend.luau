local Backend = {}
local native
local fonts, images, users = {}, {}, 0
function Backend.native() if not native then native = require("@luauxtx/gfx") end; return native end
function Backend.acquire() users += 1 end
function Backend.release()
    users = math.max(0, users-1)
    if users == 0 then
        for _, font in pairs(fonts) do font:dispose() end
        for _, image in pairs(images) do image:dispose() end
        fonts = {}; images = {}
    end
end
function Backend.font(app, style)
    local size = math.round((style.fontSize or 16)*4)/4
    assert(size > 0 and size <= 512, "XTGUI fontSize must be in (0,512]")
    local family = style.fontFamily or "system"
    local weight = style.fontWeight or 400
    if weight == "normal" then weight=400 elseif weight == "bold" then weight=700 end
    local configured = app.options.fontFiles and app.options.fontFiles[family]
    local path = style.fontPath
    if not path and configured then path = type(configured) == "string" and configured or configured[weight] or configured[tostring(weight)] end
    assert(path or (family == "system" and weight == 400), "XTGUI: configure fontFiles[family][weight] or fontPath for " .. tostring(family) .. " weight " .. tostring(weight))
    local key = tostring(path or "<system>") .. ":" .. tostring(size)
    if not fonts[key] then fonts[key] = Backend.native().loadFont(path,size) end
    return fonts[key], key, size
end
function Backend.image(path)
    assert(type(path) == "string", "XTGUI Image requires a source path")
    if not images[path] then images[path] = Backend.native().loadImage(path) end
    return images[path]
end
function Backend.measure(text, font) return Backend.native().measureText(text,font) end
return Backend
