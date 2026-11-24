local Application=require("./core/Application")
local State=require("./core/State")
local Component=require("./core/Component")
local Theme=require("./styling/Theme")
local Widgets=require("./components/Widgets")
local gui={version="0.1.0",_hosts=Widgets.hosts,_validate=Widgets.validate}
gui.state=State.new;gui.computed=State.computed;gui.effect=State.effect;gui.batch=State.batch;gui.ref=State.ref;gui.onCleanup=State.cleanup
gui.component=Component.new;gui.setTheme=Theme.set;gui.style=function(style)return style end
function gui.createApp(options)return Application.new(options,gui)end
gui.run=Application.runAll
for name in pairs(Widgets.hosts) do
    gui[name]=function(first,second)
        local props=first==gui and second or first;props=props or {}
        assert(type(props)=="table","XTGUI "..name.." expects a properties table")
        return {type=name,props=props,key=props.key}
    end
end
return gui
