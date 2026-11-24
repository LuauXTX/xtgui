local Component = {}
function Component.new(render, name)
    assert(type(render) == "function", "XTGUI component requires a render function")
    local definition = { render = render, name = name or "Component", _component = true }
    return setmetatable(definition, { __call = function(self, props)
        props = props or {}; return { type = self, props = props, key = props.key }
    end })
end
return Component
