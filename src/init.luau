local Application = require("./core/Application")
local Types = require("./Types")
export type State<T> = Types.State<T>
export type App = Types.App
export type AppOptions = Types.AppOptions
export type Element = Types.Element
export type Props = Types.Props
export type Style = Types.Style
export type Node = Types.Node
export type Gui = Types.Gui
local State = require("./core/State")
local Component = require("./core/Component")
local Theme = require("./styling/Theme")
local Widgets = require("./components/Widgets")
local Tween = require("./animation/Tween")
local Timeline = require("./animation/Timeline")
Tween.attach(Application)
local gui = { version = "0.1.0", _hosts = Widgets.hosts, _validate = Widgets.validate }
gui.state = State.new
gui.computed = State.computed
gui.effect = State.effect
gui.batch = State.batch
gui.ref = State.ref
gui.onCleanup = State.cleanup
gui.component = Component.new
gui.setTheme = Theme.set
gui.style = function(style)
    return style
end
function gui.createApp(options)
    return Application.new(options, gui)
end
gui.run = Application.runAll
gui.tween = Tween.new
gui.timeline = Timeline.new
function gui.useApp()
    assert(State.owner and State.owner.app, "XTGUI useApp must be called inside a component")
    return State.owner.app
end
function gui.useViewport()
    return gui.useApp()._viewport:get()
end
for name in pairs(Widgets.hosts) do
    gui[name] = function(first, second)
        local props = first == gui and second or first
        props = props or {}
        assert(type(props) == "table", "XTGUI " .. name .. " expects a properties table")
        return { type = name, props = props, key = props.key }
    end
end
require("./components/Overlays")(gui)
require("./components/Views")(gui)
local Semantics = require("./accessibility/Semantics")
function Application:getSemantics()
    return Semantics.snapshot(self)
end
return (gui :: any) :: Types.Gui
