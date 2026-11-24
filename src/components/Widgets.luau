local Editor=require("../input/TextEditing")
local State=require("../core/State")
local C=require("../layout/Constraints")
local W={}
W.hosts={Text=true,Button=true,IconButton=true,TextInput=true,TextArea=true,Checkbox=true,RadioButton=true,Switch=true,Slider=true,ProgressBar=true,Image=true,Separator=true,Row=true,Column=true,Stack=true,Grid=true,Container=true,Spacer=true,ScrollView=true,Canvas=true}
function W.validate(kind,p)
    if kind=="Slider" or kind=="ProgressBar" then
        local min=p.min or 0;local max=p.max or (kind=="ProgressBar" and 1 or 100)
        C.number(min,"minimum");C.number(max,"maximum");assert(max>min,"XTGUI "..kind.." maximum must exceed minimum")
        if p.value~=nil then C.number(p.value,"value") end
        if p.step~=nil then C.number(p.step,"step",0.000001) end
    end
    if kind=="TextInput" or kind=="TextArea" then
        assert(p.value==nil or type(p.value)=="string","XTGUI text input value must be a string")
        if p.maxLength then C.number(p.maxLength,"maxLength",0,65536);assert(p.maxLength%1==0,"XTGUI maxLength must be an integer") end
    end
    if p.text~=nil then assert(utf8.len(tostring(p.text)),"XTGUI text must contain valid UTF-8") end
    if p.value and type(p.value)=="string" then assert(utf8.len(p.value),"XTGUI value must contain valid UTF-8") end
    if kind=="Canvas" then assert(type(p.onPaint)=="function","XTGUI Canvas needs onPaint(frame,bounds,element)") end
    for name,callback in pairs(p) do if type(name)=="string" and name:match("^on%u") and callback~=nil then assert(type(callback)=="function","XTGUI "..kind.." "..name.." must be a function") end end
end
function W.editor(node)
    local data=node.data
    if not data.editor then data.editor=Editor.new(node.props.value or node.props.defaultValue or "",node.kind=="TextArea") end
    if node.props.value~=nil then data.editor:sync(node.props.value) end
    return data.editor
end
function W.value(node,key,default)
    if node.props[key]~=nil then return node.props[key] end
    if node.data[key]==nil then node.data[key]=node.props["default"..key:sub(1,1):upper()..key:sub(2)] or default end
    return node.data[key]
end
function W.change(node,key,value)
    node.data[key]=value
    local source=node.rawProps[key]
    if State.is(source) then source:set(value);node.props[key]=value end
    if node.props.onChange then node.props.onChange(value,node) end
    node.paintDirty=true;node.app:_redraw()
end
function W.editChanged(node)
    local editor=node.data.editor
    local source=node.rawProps.value
    if State.is(source) then source:set(editor.text);node.props.value=editor.text end
    if node.props.onChange then node.props.onChange(editor.text,node) end
    node.paintDirty=true;node.app:_ime();node.app:_redraw()
end
function W.activate(node,event)
    if node.disabled then return end
    if node.kind=="Checkbox" or node.kind=="Switch" then W.change(node,"checked",not W.value(node,"checked",false))
    elseif node.kind=="RadioButton" then
        if node.props.group then
            for _,other in ipairs(node.app._visual) do
                if other~=node and other.kind=="RadioButton" and other.props.group==node.props.group and W.value(other,"checked",false) then W.change(other,"checked",false) end
            end
        end
        W.change(node,"checked",true)
    end
    if node.props.onActivate then node.props.onActivate(event,node) end
end
function W.slider(node,x)
    local p=node.props;local min,max=p.min or 0,p.max or 100;local b=node.box
    local value=min+math.clamp((x-b.x-9)/math.max(1,b.width-18),0,1)*(max-min)
    if p.step then value=min+math.round((value-min)/p.step)*p.step end
    W.change(node,"value",math.clamp(value,min,max))
end
return W
