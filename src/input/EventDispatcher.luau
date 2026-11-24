local Visual=require("./VisualTree")
local Geometry=require("../rendering/Geometry")
local W=require("../components/Widgets")
local Text=require("../rendering/TextLayout")
local U=require("./Unicode")
local Input={};Input.__index=Input
local names={mouseDown="MouseDown",mouseUp="MouseUp",mouseMove="MouseMove",click="Click",doubleClick="DoubleClick",mouseEnter="MouseEnter",mouseLeave="MouseLeave",wheel="Wheel",keyDown="KeyDown",keyUp="KeyUp",textInput="TextInput",focus="Focus",blur="Blur",dragStart="DragStart",drag="Drag",dragEnd="DragEnd",pointerCancel="PointerCancel",contextMenu="ContextMenu"}
function Input.new(app) return setmetatable({app=app,x=0,y=0,mods={},shortcuts={},captureMode="none"},Input) end
function Input:emit(kind,target,source)
    if not target or not target.alive then return nil end
    local event=table.clone(source or {});event.type=kind;event.target=target;event.defaultPrevented=false;event.propagationStopped=false;event.app=self.app
    function event:preventDefault()self.defaultPrevented=true end
    function event:stopPropagation()self.propagationStopped=true end
    function event:capturePointer()self.app.input:capture(self.currentTarget)end
    function event:releasePointer()self.app.input:release(self.currentTarget)end
    local path={};local node=target
    while node do table.insert(path,node);node=node.parent end
    local name=names[kind] or kind:sub(1,1):upper()..kind:sub(2)
    local function call(current,capture)
        if not current.alive then return end
        event.currentTarget=current;event.phase=capture and "capture" or "bubble"
        if current.inverse and event.x and event.y then local x,y=Geometry.point(current.inverse,event.x,event.y);event.localX=x-current.box.x;event.localY=y-current.box.y end
        local callback=current.props["on"..name..(capture and "Capture" or "")]
        if callback then callback(event,current) end
    end
    for i=#path,1,-1 do call(path[i],true);if event.propagationStopped then break end end
    if not event.propagationStopped then for _,current in ipairs(path) do call(current,false);if event.propagationStopped then break end end end
    return event
end
function Input:capture(node)
    assert(node.alive and node.app==self.app,"XTGUI invalid pointer capture target")
    if self.captured and self.captured~=node then self:release() end
    self.captured=node;self.captureMode="none"
    if self.app.window and self.app._ready and not self.synthetic then
        local ok,mode=pcall(function()return self.app.window:setMouseCapture(true)end);if ok then self.captureMode=mode end
    end
    return self.captureMode
end
function Input:release(node)
    if node and node~=self.captured then return false end
    if self.captureMode~="none" and self.app.window and self.app._ready then pcall(function()self.app.window:setMouseCapture(false)end) end
    self.captured=nil;self.captureMode="none";return true
end
function Input:cancel()
    local pressed=self.pressed
    self:release();self.pressed=nil;self.dragging=false;self.buttons={}
    if pressed and pressed.alive then pressed.interaction.active=false;self:emit("pointerCancel",pressed,{x=self.x,y=self.y});pressed.paintDirty=true end
    self.app:_styles()
end
local function actionable(node)
    while node do
        if W.hosts[node.kind] and (node.app.focus:eligible(node) or node.props.onClick or node.props.onMouseDown or node.props.onDrag or node.props.draggable) then return node end
        node=node.parent
    end
end
function Input:hover(target,source)
    if self.hovered==target then return end
    local oldPath,newPath={},{};local n=self.hovered
    while n do oldPath[n]=true;n=n.parent end;n=target;while n do newPath[n]=true;n=n.parent end
    for node in pairs(oldPath) do if not newPath[node] then node.interaction.hover=false;node.paintDirty=true;self:emit("mouseLeave",node,source) end end
    for node in pairs(newPath) do if not oldPath[node] then node.interaction.hover=true;node.paintDirty=true;self:emit("mouseEnter",node,source) end end
    self.hovered=target
    local cursor="default";n=target;while n do if n.style.cursor then cursor=n.style.cursor;break end;n=n.parent end
    if self.app.window and self.app._ready then self.app.window:setCursor(cursor) end
    self.app:_styles()
end
function Input:editorLayout(node)
    local s=node.style;local b=node.box;local p=s.padding;local editor=W.editor(node)
    local text=editor:display(node.props.password)
    local layout=Text.layout(self.app,text,s,math.max(0,b.width-p.left-p.right),node.kind=="TextArea" and node.props.wrap~=false)
    node.textLayout=layout;return editor,layout
end
function Input:editorPointer(node,event,extend)
    local editor,layout=self:editorLayout(node);local x,y=Geometry.point(node.inverse,event.x,event.y);local p=node.style.padding
    local index=Text.index(layout,x-node.box.x-p.left+editor.scrollX,y-node.box.y-p.top+editor.scrollY)
    editor:move(index,extend);node.paintDirty=true;self.app:_ime();self.app:_redraw()
end
function Input:shortcut(chord,callback)
    assert(type(chord)=="string" and type(callback)=="function","XTGUI shortcut expects chord and callback")
    local id={};self.shortcuts[id]={chord=chord:lower():gsub("%s",""),callback=callback}
    return function()self.shortcuts[id]=nil end
end
local function matchChord(chord,key,mods)
    local pieces=string.split(chord,"+");local expected=table.remove(pieces);local flags={control=false,super=false,alt=false,shift=false}
    for _,part in ipairs(pieces) do
        if part=="ctrl" or part=="control" then flags.control=true elseif part=="cmd" or part=="super" or part=="meta" then flags.super=true elseif part=="mod" then if mods.super then flags.super=true else flags.control=true end elseif part=="alt" then flags.alt=true elseif part=="shift" then flags.shift=true else return false end
    end
    if expected~=key:lower() then return false end
    for k,v in pairs(flags) do if v~=(mods[k]==true) then return false end end
    return true
end
function Input:dispatch(source)
    self.synthetic=source.synthetic==true
    local event=table.clone(source);local kind=event.type;local app=self.app
    if kind=="modifiers" then self.mods={shift=event.shift,control=event.control,alt=event.alt,super=event.super};return end
    if kind=="mouseMove" then
        if self.captureMode=="locked" and not self.synthetic then return end
        event.deltaX=event.x-self.x;event.deltaY=event.y-self.y;self.x=event.x;self.y=event.y
    elseif kind=="rawMouseMotion" and self.captured and self.captureMode=="locked" then
        event.x=math.clamp(self.x+(event.dx or 0),0,app.width);event.y=math.clamp(self.y+(event.dy or 0),0,app.height);event.deltaX=event.x-self.x;event.deltaY=event.y-self.y;self.x=event.x;self.y=event.y;kind="mouseMove";event.type=kind
    elseif event.x and event.y and (kind=="mouseDown" or kind=="mouseUp") then self.x=event.x;self.y=event.y end
    if kind=="mouseMove" or kind=="mouseDown" or kind=="mouseUp" or kind=="scroll" then event.x=self.x;event.y=self.y end
    local hit=Visual.hit(app,self.x,self.y)
    if kind=="mouseLeave" then self:hover(nil,event)
    elseif kind=="mouseMove" then
        self:hover(hit,event);local target=self.captured or hit
        self:emit("mouseMove",target,event)
        if self.pressed and self.pressed.alive then
            event.totalX=self.x-self.startX;event.totalY=self.y-self.startY
            if not self.dragging and event.totalX^2+event.totalY^2>=9 then self.dragging=true;self:emit("dragStart",self.pressed,event) end
            if self.dragging then self:emit("drag",self.pressed,event) end
            if self.pressed.kind=="Slider" then local x=Geometry.point(self.pressed.inverse,self.x,self.y);W.slider(self.pressed,x)
            elseif self.pressed.kind=="TextInput" or self.pressed.kind=="TextArea" then self:editorPointer(self.pressed,event,true) end
        end
    elseif kind=="mouseDown" then
        local emitted=self:emit("mouseDown",hit,event)
        if event.button=="right" then local menu=self:emit("contextMenu",hit,event);if menu and menu.defaultPrevented then return end end
        if event.button~="left" or (emitted and emitted.defaultPrevented) then return end
        local node=actionable(hit)
        if node then
            if app.focus:eligible(node) then app.focus:set(node,false) end
            self.pressed=node;self.startX=self.x;self.startY=self.y;node.interaction.active=true;node.paintDirty=true;self.dragging=false
            if node.kind=="Slider" then self:capture(node);local x=Geometry.point(node.inverse,self.x,self.y);W.slider(node,x)
            elseif node.kind=="TextInput" or node.kind=="TextArea" then self:capture(node);self:editorPointer(node,event,self.mods.shift) end
            if node.props.draggable then self:capture(node) end
            app:_styles()
        else app.focus:set(nil,false) end
    elseif kind=="mouseUp" then
        self:emit("mouseUp",self.captured or hit,event)
        if event.button~="left" then return end
        local pressed=self.pressed;self.pressed=nil;self:release()
        if pressed and pressed.alive then
            pressed.interaction.active=false;pressed.paintDirty=true
            if self.dragging then self:emit("dragEnd",pressed,event) end
            local inside=hit and pressed:contains(hit)
            if inside and not self.dragging then
                local click=self:emit("click",pressed,event)
                if click and not click.defaultPrevented then W.activate(pressed,click) end
                local now=event.time or os.clock()
                if self.lastClick==pressed and now-(self.lastClickTime or 0)<0.4 then
                    self:emit("doubleClick",pressed,event)
                    if pressed.kind=="TextInput" or pressed.kind=="TextArea" then local editor=W.editor(pressed);local i=editor.caret;editor.anchor=editor:word(i,-1);editor.caret=editor:word(i,1);pressed.paintDirty=true end
                    self.lastClick=nil
                else self.lastClick=pressed;self.lastClickTime=now end
            end
        end
        self.dragging=false;app:_styles()
    elseif kind=="scroll" then
        event.scrollX=source.x or 0;event.scrollY=source.y or 0;event.unit=source.unit
        local emitted=self:emit("wheel",hit,event)
        if not emitted or not emitted.defaultPrevented then
            local node=hit;local amount=source.unit=="pixels" and 1 or 36
            while node do
                if node.kind=="ScrollView" then
                    local dx=-(source.x or 0)*amount;local dy=-(source.y or 0)*amount
                    if self.mods.shift then dx,dy=dy,dx end
                    if app:_scroll(node,(node.data.scrollX or 0)+dx,(node.data.scrollY or 0)+dy) then break end
                end
                node=node.parent
            end
        end
    elseif kind=="keyDown" or kind=="keyUp" then
        local mods=event.modifiers or self.mods;event.modifiers=mods
        local target=app.focus.current;local emitted=self:emit(kind,target,event)
        if emitted and emitted.defaultPrevented then return end
        local key=event.key
        if kind=="keyDown" then
            for _,shortcut in pairs(self.shortcuts) do if matchChord(shortcut.chord,key,mods) then if shortcut.callback(event)~=false then return end end end
            if key=="Tab" and not(target and target.props.acceptTab) then app.focus:tab(mods.shift);return end
            if target and not target.disabled then
                if target.kind=="TextInput" or target.kind=="TextArea" then
                    local editor,layout=self:editorLayout(target);local opts=table.clone(target.props);opts.viewportHeight=target.box.height
                    local handled,changed=editor:key(key,mods,layout,opts,app)
                    if changed then W.editChanged(target) end
                    if handled then target.paintDirty=true;app:_redraw();app:_ime();app:_caretTimer();return end
                    if key=="Enter" and target.props.onSubmit then target.props.onSubmit(editor.text,target) end
                elseif target.kind=="Slider" then
                    local p=target.props;local value=W.value(target,"value",p.min or 0);local step=p.step or ((p.max or 100)-(p.min or 0))/100
                    local nextValue=key=="Home" and (p.min or 0) or key=="End" and (p.max or 100) or (key=="ArrowLeft" or key=="ArrowDown") and value-step or (key=="ArrowRight" or key=="ArrowUp") and value+step
                    if nextValue then W.change(target,"value",math.clamp(nextValue,p.min or 0,p.max or 100)) end
                elseif target.kind=="RadioButton" and (key=="ArrowLeft" or key=="ArrowUp" or key=="ArrowRight" or key=="ArrowDown") then
                    local radios={};local current=1
                    for _,node in ipairs(app._visual) do if node.kind=="RadioButton" and node.props.group==target.props.group and not node.disabled then table.insert(radios,node);if node==target then current=#radios end end end
                    local nextRadio=radios[(current+((key=="ArrowLeft" or key=="ArrowUp") and -1 or 1)-1)%#radios+1]
                    app.focus:set(nextRadio,true);W.activate(nextRadio,event)
                elseif key=="Enter" and not event["repeat"] then local click=self:emit("click",target,event);if not click.defaultPrevented then W.activate(target,click) end
                elseif key==" " or key=="Space" then target.interaction.active=true;target.paintDirty=true;app:_styles() end
            end
        elseif target and (key==" " or key=="Space") and target.interaction.active then
            target.interaction.active=false;local click=self:emit("click",target,event);if not click.defaultPrevented then W.activate(target,click) end;app:_styles()
        end
    elseif kind=="textInput" then
        local target=app.focus.current;local emitted=self:emit("textInput",target,event)
        if target and not target.disabled and (target.kind=="TextInput" or target.kind=="TextArea") and not(emitted and emitted.defaultPrevented) then
            if not (self.mods.control or self.mods.super) or event.ime then
                local text=event.text or ""
                -- Enter/Tab are handled by key events. IME commits may contain newlines.
                if not event.ime then text=text:gsub("[\r\n\t]","") end
                local editor=W.editor(target)
                if editor:replace(text,target.props) then W.editChanged(target) end
                app:_caretTimer()
            end
        end
    elseif kind=="imeComposition" then
        local target=app.focus.current
        if target and (target.kind=="TextInput" or target.kind=="TextArea") then
            local editor=W.editor(target);editor.composition=event.text or "";editor.compositionCursor=event.cursorEnd and U.byteToIndex(editor.composition,event.cursorEnd) or #U.split(editor.composition)
            target.paintDirty=true;app:_redraw();app:_ime()
        end
    elseif kind=="imeDisabled" then local target=app.focus.current;if target and target.data.editor then target.data.editor.composition="";target.paintDirty=true;app:_redraw() end
    elseif kind=="focus" then
        app.focus.windowFocused=event.focused
        if not event.focused then self.mods={};self:cancel();self:hover(nil,event) end
        if app.focus.current then app.focus.current.paintDirty=true end;app:_caretTimer();app:_redraw()
    end
end
return Input
