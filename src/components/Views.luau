local State=require("../core/State")
local C=require("../layout/Constraints")
return function(gui)
    local define,control=gui._define,gui._control
    define("ListView",function(p)
        local items=State.read(p.items) or {};assert(type(items)=="table","XTGUI ListView items must be an array")
        local rowHeight=p.rowHeight or 32;C.number(rowHeight,"ListView rowHeight",1,10000)
        local selected,setSelected=control(p,"value",nil);local offset=gui.state(0);local viewport=gui.state(type(p.height)=="number" and p.height or 240);local scrollRef=gui.ref(nil);local keyCache=gui.ref(nil)
        local overscan=p.overscan or 3;C.number(overscan,"ListView overscan",0,100);assert(overscan%1==0,"XTGUI overscan must be an integer")
        local keyFor=p.itemKey or function(item,index)return type(item)=="table" and item.key or index end
        if not keyCache.current or keyCache.current.items~=items or keyCache.current.fn~=p.itemKey then
            local keys,indices={},{}
            for i,item in ipairs(items) do local key=keyFor(item,i);assert(type(key)=="string" or type(key)=="number","XTGUI ListView itemKey must return a string/number");assert(not indices[key],"XTGUI ListView duplicate key: "..tostring(key));keys[i]=key;indices[key]=i end
            keyCache.current={items=items,fn=p.itemKey,keys=keys,indices=indices}
        end
        local keys=keyCache.current.keys;local indices=keyCache.current.indices
        local height=viewport:get();local maxOffset=math.max(0,#items*rowHeight-height);local scroll=math.min(offset:get(),maxOffset)
        local first=math.max(1,math.floor(scroll/rowHeight)+1-overscan);local last=math.min(#items,math.ceil((scroll+height)/rowHeight)+overscan)
        local rows={}
        local function select(index)
            if #items==0 then return end;index=math.clamp(index,1,#items)
            setSelected(keys[index]);if p.onSelect then p.onSelect(items[index],index) end
            local top=(index-1)*rowHeight;local target=scroll
            if top<scroll then target=top elseif top+rowHeight>scroll+height then target=top+rowHeight-height end
            if scrollRef.current then scrollRef.current:scrollTo(0,target) end
        end
        for i=first,last do
            local item=items[i];local key=keys[i];local active=key==selected
            local content=p.renderItem and p.renderItem(item,i,active) or gui.Text({text=type(item)=="table" and (item.label or tostring(key)) or tostring(item),wrap=false})
            table.insert(rows,gui.Container({key=key,position="absolute",x=0,y=(i-1)*rowHeight,width="100%",height=rowHeight,padding=p.itemPadding or {5,8},background=active and "$selection" or nil,hoverStyle={background="$hover"},overflow="hidden",role=p.itemRole or "option",selected=active,ariaLabel=type(item)=="table" and item.label or tostring(item),onClick=function()select(i);if scrollRef.current then scrollRef.current:focus()end end,children={content}}))
        end
        return gui.ScrollView({id=p.id,ref=scrollRef,width=p.width,height=p.height or 240,flexGrow=p.flexGrow,disabled=State.read(p.disabled),focusable=true,role=p.role or "listbox",ariaLabel=p.ariaLabel,itemCount=#items,activeDescendant=selected,onKeyDown=function(e)
            if p.onKeyDown then p.onKeyDown(e,selected,indices[selected]) end;if e.defaultPrevented then return end
            local index=indices[selected] or 0;local nextIndex
            if e.key=="ArrowDown" then nextIndex=index+1 elseif e.key=="ArrowUp" then nextIndex=index-1 elseif e.key=="Home" then nextIndex=1 elseif e.key=="End" then nextIndex=#items
            elseif e.key=="PageDown" then nextIndex=index+math.max(1,math.floor(height/rowHeight)) elseif e.key=="PageUp" then nextIndex=index-math.max(1,math.floor(height/rowHeight))
            elseif e.key=="Enter" and p.onActivate and items[index] then p.onActivate(items[index],index);e:preventDefault()end
            if nextIndex then select(nextIndex);e:preventDefault()end
        end,onLayout=function(bounds,node)
            viewport:set(bounds.height);local target=math.min(offset:get(),math.max(0,#items*rowHeight-bounds.height))
            if target~=(node.data.scrollY or 0) then node:scrollTo(0,target) end
            if p.onLayout then p.onLayout(bounds,node) end
        end,onScroll=function(event,node)offset:set(event.y);if p.onScroll then p.onScroll(event,node)end end,
        children={gui.Container({height=#items*rowHeight,flexShrink=0,children=rows})}})
    end)
    define("Table",function(p)
        local columns=State.read(p.columns) or {};local items=State.read(p.items) or {};local sort=gui.state(nil);local sorting=sort:get()
        if sorting then
            items=table.clone(items)
            table.sort(items,function(a,b)
                local av,bv=a[sorting.key],b[sorting.key];if av==bv then return false end
                if type(av)~=type(bv) or (type(av)~="number" and type(av)~="string") then av=tostring(av);bv=tostring(bv) end
                return sorting.descending and av>bv or (not sorting.descending and av<bv)
            end)
        end
        local headers={}
        for _,column in ipairs(columns) do
            assert(column.key,"XTGUI Table columns need a key")
            table.insert(headers,gui.Button({key=column.key,text=(column.label or tostring(column.key))..(sorting and sorting.key==column.key and (sorting.descending and " ▾" or " ▴") or ""),width=column.width,flexGrow=column.width and 0 or column.grow or 1,textAlign="start",role="columnheader",height=p.headerHeight or 34,onClick=function()
                if p.sortable or column.sortable then sort:set({key=column.key,descending=sorting and sorting.key==column.key and not sorting.descending or false});if p.onSort then p.onSort(column.key)end end
            end}))
        end
        return gui.Column({id=p.id,width=p.width,height=p.height or 300,role="table",ariaLabel=p.ariaLabel,children={gui.Row({height=p.headerHeight or 34,flexShrink=0,children=headers}),gui.ListView({items=items,itemKey=p.itemKey,rowHeight=p.rowHeight or 32,height=(type(p.height)=="number" and p.height or 300)-(p.headerHeight or 34),flexGrow=1,value=p.value,defaultValue=p.defaultValue,onChange=p.onChange,onActivate=p.onActivate,itemRole="row",role="rowgroup",renderItem=function(item,index,selected)
            local cells={}
            for _,column in ipairs(columns) do
                local content=column.render and column.render(item[column.key],item,index,selected) or gui.Text({text=tostring(item[column.key] or ""),wrap=false})
                table.insert(cells,gui.Container({key=column.key,width=column.width,flexGrow=column.width and 0 or column.grow or 1,padding={0,6},overflow="hidden",role="cell",children={content}}))
            end
            return gui.Row({height="100%",children=cells})
        end})}})
    end)
    define("TreeView",function(p)
        local expanded,setExpanded=control({value=p.expanded,defaultValue=p.defaultExpanded or {},onChange=p.onExpandedChange},"value",{})
        local selected,setSelected=control(p,"value",nil);local items=State.read(p.items) or {};local flat={};local path={};local keys={};local byKey={}
        local function flatten(nodes,depth,parent)
            assert(depth<=128,"XTGUI TreeView nesting exceeds 128 levels")
            for i,item in ipairs(nodes) do
                assert(type(item)=="table" and not path[item],"XTGUI TreeView contains a cycle or invalid item")
                local key=p.itemKey and p.itemKey(item,i) or item.key;assert(type(key)=="string" or type(key)=="number","XTGUI TreeView items need unique keys");assert(not keys[key],"XTGUI TreeView duplicate key: "..tostring(key));keys[key]=true
                local children=p.getChildren and p.getChildren(item) or item.children or {};local record={key=key,item=item,label=item.label or tostring(key),depth=depth,parent=parent,hasChildren=#children>0,expanded=expanded[key]==true}
                table.insert(flat,record);byKey[key]=record
                if record.expanded then path[item]=true;flatten(children,depth+1,key);path[item]=nil end
            end
        end
        flatten(items,0,nil)
        local function toggle(key,value)local copy=table.clone(expanded);copy[key]=value==nil and not copy[key] or value;setExpanded(copy)end
        return gui.ListView({id=p.id,width=p.width,height=p.height or 260,items=flat,itemKey=function(item)return item.key end,rowHeight=p.rowHeight or 30,value=selected,onChange=setSelected,role="tree",itemRole="treeitem",ariaLabel=p.ariaLabel,onKeyDown=function(e,key,index)
            local item=byKey[key]
            if item and e.key=="ArrowRight" then if item.hasChildren and not item.expanded then toggle(key,true)elseif item.expanded and flat[(index or 0)+1] then setSelected(flat[index+1].key)end;e:preventDefault()
            elseif item and e.key=="ArrowLeft" then if item.expanded then toggle(key,false)elseif item.parent then setSelected(item.parent)end;e:preventDefault()end
        end,renderItem=function(record)
            return gui.Row({height="100%",gap=4,padding={0,0,0,record.depth*(p.indent or 18)},children={gui.IconButton({text=record.hasChildren and (record.expanded and "▾" or "▸") or "",width=20,height=22,padding=0,background="transparent",borderWidth=0,focusable=false,onClick=function(e)e:stopPropagation();if record.hasChildren then toggle(record.key)end end}),gui.Text({text=record.label,wrap=false,role="treeitem",expanded=record.hasChildren and record.expanded or nil,level=record.depth+1})}})
        end})
    end)
    define("SplitPane",function(p)
        local ratio,setRatio=control(p,"ratio",0.5);C.number(ratio,"SplitPane ratio",0,1)
        local vertical=p.direction=="vertical";local bounds=gui.state({width=type(p.width)=="number" and p.width or 500,height=type(p.height)=="number" and p.height or 260});local ref=gui.ref(nil)
        local b=bounds:get();local total=vertical and b.height or b.width;local thickness=p.handleSize or 6;local position=math.clamp(ratio*total,p.minFirst or 0,math.max(p.minFirst or 0,total-(p.minSecond or 0)))
        local function move(value)setRatio(math.clamp(value/math.max(1,total),(p.minFirst or 0)/math.max(1,total),math.max((p.minFirst or 0)/math.max(1,total),1-(p.minSecond or 0)/math.max(1,total))))end
        local children=p.children or {};local first=p.first or children[1];local second=p.second or children[2]
        return gui.Container({id=p.id,ref=ref,width=p.width or "100%",height=p.height or 260,onLayout=function(value)if value.width~=b.width or value.height~=b.height then bounds:set(value)end end,children={
            gui.Stack({position="absolute",x=0,y=0,width=vertical and "100%" or math.max(0,position-thickness/2),height=vertical and math.max(0,position-thickness/2) or "100%",overflow="hidden",children={first}}),
            gui.Stack({position="absolute",x=vertical and 0 or position+thickness/2,y=vertical and position+thickness/2 or 0,width=vertical and "100%" or math.max(0,total-position-thickness/2),height=vertical and math.max(0,total-position-thickness/2) or "100%",overflow="hidden",children={second}}),
            gui.Container({position="absolute",x=vertical and 0 or position-thickness/2,y=vertical and position-thickness/2 or 0,width=vertical and "100%" or thickness,height=vertical and thickness or "100%",background="$border",hoverStyle={background="$primary"},cursor=vertical and "resize-vertical" or "resize-horizontal",focusable=true,draggable=true,disabled=State.read(p.disabled),role="separator",ariaLabel=p.ariaLabel or "Resize panes",onDrag=function(e)
                local container=ref.current;if container then local origin=container.box;move(vertical and e.y-origin.y or e.x-origin.x)end
            end,onKeyDown=function(e)
                if e.key=="ArrowLeft" or e.key=="ArrowUp" then move(position-(p.keyboardStep or 10));e:preventDefault()elseif e.key=="ArrowRight" or e.key=="ArrowDown" then move(position+(p.keyboardStep or 10));e:preventDefault()end
            end})}})
    end)
end
