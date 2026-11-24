local State=require("../core/State")
local Component=require("../core/Component")
return function(gui)
    local function define(name,render)
        local definition=Component.new(render,name)
        gui[name]=function(a,b)return definition((a==gui and b or a) or {})end
    end
    local function control(props,key,default)
        local initial=props["default"..key:sub(1,1):upper()..key:sub(2)];if initial==nil then initial=default end
        local localValue=gui.state(initial)
        local value=State.read(props[key]);if props[key]==nil then value=localValue:get() end
        local function set(nextValue)
            if State.is(props[key]) then props[key]:set(nextValue) elseif props[key]==nil then localValue:set(nextValue) end
            if props.onChange then props.onChange(nextValue) end
        end
        return value,set
    end
    gui._control=control;gui._define=define
    local function dismissLayer(app,close,z)
        return gui.Container({portal=true,position="absolute",x=0,y=0,width=app.width,height=app.height,zIndex=z,onMouseDown=function(e)e:preventDefault();e:stopPropagation();close()end,onWheel=function(e)e:preventDefault()end})
    end
    local function panel(props)
        props.background=props.background or "$elevated";props.borderColor=props.borderColor or "$border";props.borderWidth=props.borderWidth or 1;props.radius=props.radius or 7;props.padding=props.padding or 6
        props.shadow=props.shadow or {blur=12,color="#00000050",y=4};return gui.Column(props)
    end
    define("Popover",function(p)
        local app=gui.useApp();gui.useViewport();local open,setOpen=control(p,"open",false);local anchor=gui.ref(nil)
        local function close()setOpen(false);if p.onDismiss then p.onDismiss() end end
        local content={}
        if p.trigger then table.insert(content,gui.Container({ref=anchor,onClick=function()if not State.read(p.disabled) then setOpen(not open) end end,children={p.trigger}})) end
        if open then
            table.insert(content,dismissLayer(app,close,p.zIndex or 1000))
            table.insert(content,panel({id=p.id,portal=true,position="absolute",anchor=p.anchor or anchor,x=p.x,y=p.y,width=p.width or 260,zIndex=(p.zIndex or 1000)+1,focusTrap=p.trapFocus==true,role="dialog",ariaLabel=p.ariaLabel,
                onKeyDown=function(e)if e.key=="Escape" then e:preventDefault();close()end end,children=p.children or {}}))
        end
        return gui.Column({width=p.triggerWidth,height=p.triggerHeight,children=content})
    end)
    define("Modal",function(p)
        local viewport=gui.useViewport();local open,setOpen=control(p,"open",false)
        local function close()if p.dismissible~=false then setOpen(false);if p.onDismiss then p.onDismiss()end end end
        if not open then return nil end
        local width=math.min(p.width or 440,math.max(1,viewport.width-32));local height=p.height
        return gui.Stack({children={
            gui.Container({portal=true,position="absolute",x=0,y=0,width=viewport.width,height=viewport.height,background=p.backdropColor or "#00000090",zIndex=p.zIndex or 2000,onMouseDown=function(e)e:preventDefault();close()end,onWheel=function(e)e:preventDefault()end}),
            panel({id=p.id,portal=true,position="absolute",x=(viewport.width-width)/2,y=p.y or math.max(16,(viewport.height-(height or 200))/2),width=width,height=height,padding=p.padding or 20,gap=p.gap or 12,zIndex=(p.zIndex or 2000)+1,focusTrap=true,role="dialog",ariaLabel=p.ariaLabel or p.title,
                onKeyDown=function(e)if e.key=="Escape" then e:preventDefault();close()end end,children=p.children or {}})
        }})
    end)
    local function options(items)
        local result={}
        for i,item in ipairs(items or {}) do
            if type(item)=="table" then table.insert(result,{label=tostring(item.label or item.value or i),value=item.value~=nil and item.value or item.label,key=item.key or item.value or i,disabled=item.disabled})
            else table.insert(result,{label=tostring(item),value=item,key=item,disabled=false}) end
        end
        return result
    end
    define("Select",function(p)
        local app=gui.useApp();gui.useViewport();local selected,setSelected=control(p,"value",nil)
        local open=gui.state(false);local highlighted=gui.state(1);local anchor=gui.ref(nil);local rows={};local items=options(State.read(p.items) or State.read(p.options))
        local label=p.placeholder or "Select…"
        for _,item in ipairs(items) do if item.value==selected then label=item.label end end
        local function choose(i)
            local item=items[i];if item and not item.disabled then setSelected(item.value);open:set(false);if anchor.current then anchor.current:focus()end end
        end
        local function move(direction)
            if #items==0 then return end
            local index=highlighted:get()
            for _=1,#items do index=(index+direction-1)%#items+1;if not items[index].disabled then highlighted:set(index);break end end
        end
        local function keyboard(e)
            if e.key=="Escape" then open:set(false);e:preventDefault()
            elseif e.key=="ArrowDown" or e.key=="ArrowUp" then if not open:get() then open:set(true) else move(e.key=="ArrowDown" and 1 or -1) end;e:preventDefault()
            elseif e.key=="Home" then highlighted:set(1);e:preventDefault()
            elseif e.key=="End" then highlighted:set(#items);e:preventDefault()
            elseif e.key=="Enter" or e.key==" " then if open:get() then choose(highlighted:get()) else open:set(true) end;e:preventDefault()
            elseif #e.key==1 and not(e.modifiers and (e.modifiers.control or e.modifiers.super)) then
                for offset=1,#items do local i=(highlighted:get()+offset-1)%#items+1;if not items[i].disabled and items[i].label:lower():sub(1,#e.key)==e.key:lower() then highlighted:set(i);break end end
            end
        end
        local children={gui.Button({id=p.id,ref=anchor,width="100%",text=label.."  ▾",disabled=State.read(p.disabled),role="combobox",ariaLabel=p.ariaLabel,expanded=open:get(),onClick=function()open:set(not open:get())end,onKeyDown=keyboard})}
        if open:get() and not State.read(p.disabled) then
            for i,item in ipairs(items) do table.insert(rows,gui.Button({key=item.key,text=item.label,height=32,flexShrink=0,textAlign="start",disabled=item.disabled,background=i==highlighted:get() and "$hover" or "$elevated",role="option",selected=item.value==selected,tabIndex=-1,onMouseEnter=function()highlighted:set(i)end,onClick=function()choose(i)end})) end
            table.insert(children,dismissLayer(app,function()open:set(false)end,1000))
            table.insert(children,panel({portal=true,position="absolute",anchor=anchor,width=p.width or 220,zIndex=1001,padding=4,onKeyDown=keyboard,children={gui.ScrollView({height=math.min(p.maxHeight or 240,#rows*32),children=rows})}}))
        end
        return gui.Column({width=p.width or 220,height=36,children=children})
    end)
    gui.Dropdown=gui.Select
    define("Tooltip",function(p)
        local app=gui.useApp();gui.useViewport();local shown=gui.state(false);local anchor=gui.ref(nil);local timer=gui.ref(nil)
        gui.onCleanup(function()if timer.current then timer.current()end end)
        local function hide()if timer.current then timer.current();timer.current=nil end;shown:set(false)end
        local function show()
            if State.read(p.disabled) then return end
            if timer.current then timer.current() end
            timer.current=app:after(p.delay or 0.5,function()shown:set(true)end)
        end
        local children=table.clone(p.children or {})
        if shown:get() then table.insert(children,panel({portal=true,position="absolute",anchor=anchor,width=p.width or 220,zIndex=3000,pointerEvents="none",role="tooltip",padding=8,children={gui.Text({text=p.text or "",fontSize=p.fontSize or 13})}})) end
        return gui.Container({id=p.id,ref=anchor,width=p.triggerWidth,height=p.triggerHeight,onMouseEnter=show,onMouseLeave=hide,onFocus=show,onBlur=hide,children=children})
    end)
    define("ContextMenu",function(p)
        local app=gui.useApp();gui.useViewport();local position=gui.state(nil);local source=State.read(p.items) or {};local items=options(source)
        local children=table.clone(p.children or {})
        if position:get() then
            local point=position:get();local rows={}
            for i,item in ipairs(items) do table.insert(rows,gui.Button({key=item.key,text=item.label,textAlign="start",height=32,disabled=item.disabled,role="menuitem",onClick=function()
                position:set(nil);local original=source[i];if type(original)=="table" and original.onSelect then original.onSelect(item.value) end;if p.onSelect then p.onSelect(item.value)end
            end})) end
            table.insert(children,dismissLayer(app,function()position:set(nil)end,1500))
            table.insert(children,panel({portal=true,position="absolute",x=point.x,y=point.y,width=p.width or 200,zIndex=1501,focusTrap=true,role="menu",onKeyDown=function(e)
                if e.key=="Escape" then position:set(nil);e:preventDefault()elseif e.key=="ArrowDown" or e.key=="ArrowUp" then app.focus:tab(e.key=="ArrowUp");e:preventDefault()end
            end,children=rows}))
        end
        return gui.Container({id=p.id,width=p.triggerWidth,height=p.triggerHeight,onContextMenu=function(e)if not State.read(p.disabled) then e:preventDefault();position:set({x=e.x,y=e.y})end end,children=children})
    end)
    define("Tabs",function(p)
        local tabs=State.read(p.tabs) or {};local selected,setSelected=control(p,"value",tabs[1] and (tabs[1].key or 1));local headers,contents={},{}
        local app=gui.useApp();local refs=gui.ref({})
        for i,tab in ipairs(tabs) do
            local key=tab.key or i;local active=key==selected;refs.current[key]=refs.current[key] or {}
            local function select(index)
                if tabs[index] and not tabs[index].disabled then local nextKey=tabs[index].key or index;setSelected(nextKey);local ref=refs.current[nextKey];if ref and ref.current then app.focus:set(ref.current,true)end end
            end
            table.insert(headers,gui.Button({key=key,ref=refs.current[key],text=tab.label or tostring(key),role="tab",selected=active,disabled=tab.disabled,background=active and "$primary" or "$surface",tabIndex=active and 0 or -1,onClick=function()setSelected(key)end,onKeyDown=function(e)
                local direction=(e.key=="ArrowLeft" or e.key=="ArrowUp") and -1 or (e.key=="ArrowRight" or e.key=="ArrowDown") and 1
                if direction then for offset=1,#tabs do local index=(i+direction*offset-1)%#tabs+1;if not tabs[index].disabled then select(index);break end end;e:preventDefault()
                elseif e.key=="Home" then select(1);e:preventDefault()elseif e.key=="End" then select(#tabs);e:preventDefault()end
            end}))
            if active or p.keepAlive then table.insert(contents,gui.Container({key=key,display=active and "flex" or "none",role="tabpanel",flexGrow=1,children=tab.children or (tab.content and {tab.content}) or {}})) end
        end
        return gui.Column({id=p.id,width=p.width,height=p.height,gap=p.gap or 8,children={gui.Row({gap=4,role="tablist",children=headers}),gui.Column({flexGrow=1,children=contents})}})
    end)
    define("Accordion",function(p)
        local expanded,setExpanded=control(p,"value",p.multiple and {} or nil);local sections={}
        for i,item in ipairs(State.read(p.items) or {}) do
            local key=item.key or i;local open=p.multiple and type(expanded)=="table" and expanded[key]==true or expanded==key
            local function toggle()
                if p.multiple then local nextValue=table.clone(expanded or {});nextValue[key]=not open;setExpanded(nextValue)elseif open then setExpanded(false)else setExpanded(key)end
            end
            table.insert(sections,gui.Column({key=key,gap=4,children={gui.Button({text=(open and "▾ " or "▸ ")..(item.label or tostring(key)),textAlign="start",expanded=open,disabled=item.disabled,onClick=toggle,onKeyDown=function(e)
                if (e.key=="ArrowRight" and not open) or (e.key=="ArrowLeft" and open) then toggle();e:preventDefault()end
            end}),open and gui.Container({padding=p.contentPadding or 8,children=item.children or (item.content and {item.content}) or {}}) or false}}))
        end
        return gui.Column({id=p.id,width=p.width,height=p.height,gap=p.gap or 6,children=sections})
    end)
end
