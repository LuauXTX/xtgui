local gui=require("../src/init")
local count=gui.state(0)
local app=gui.createApp({title="XTGUI native integration",width=520,height=360,onFrame=function(_,app)
    if app.diagnostics.frames==1 then
        local b=app:find("button").box
        app:dispatch({type="mouseMove",x=b.x+5,y=b.y+5});app:dispatch({type="mouseDown",button="left"});app:dispatch({type="mouseUp",button="left"})
        assert(count:get()==1);app:resize(600,400)
    elseif app.diagnostics.frames==2 then app.window:requestRedraw()
    elseif app.diagnostics.frames>=3 then app:close() end
end})
app:render(function(ui)return ui:Column({padding=20,gap=12,children={ui:Text({text="Native XTGUI ✓",fontSize=24}),ui:Button({id="button",text="Count: "..count:get(),onClick=function()count:set(count:get()+1)end}),ui:TextInput({placeholder="Unicode / IME",value=gui.state("")}),ui:ScrollView({height=100,children={ui:Text({text=string.rep("Clipped text\n",20)})}})}})end)
app:after(10,function()error("native integration timed out")end)
app:run()
assert(app.diagnostics.frames>=3 and app.destroyed)
count:dispose()
print("XTGUI native integration passed: "..app.diagnostics.frames.." GPU frames")
