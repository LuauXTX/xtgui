local G=require("../rendering/Geometry")
local V={}
function V.sorted(children)
    local result={};for i,node in ipairs(children) do table.insert(result,{node=node,index=i}) end
    table.sort(result,function(a,b)local az=a.node.style.zIndex or 0;local bz=b.node.style.zIndex or 0;return az<bz or (az==bz and a.index<b.index) end)
    local nodes={};for _,item in ipairs(result) do table.insert(nodes,item.node) end;return nodes
end
function V.update(app)
    local portals={};local entries={};local order=0
    local function visit(node,parentWorld,clips,portal)
        if node.style.display=="none" or node.box.width<=0 or node.box.height<=0 then return end
        if node.props.portal and not portal then table.insert(portals,node);return end
        local localMatrix=G.transform(node.box,node.style.transform)
        node.world=G.multiply(parentWorld,localMatrix);node.inverse=G.inverse(node.world);node.clips=clips
        order+=1;node.paintOrder=order;table.insert(entries,node)
        local childClips=clips
        if node.style.overflow=="hidden" or node.kind=="ScrollView" or node.kind=="TextInput" or node.kind=="TextArea" then
            childClips=table.clone(clips);table.insert(childClips,G.polygon(node.box,node.world))
        end
        for _,child in ipairs(V.sorted(node.children)) do visit(child,node.world,childClips,false) end
    end
    if app.root then visit(app.root,G.identity,{},false) end
    local index=1
    while index<=#portals do local node=portals[index];visit(node,G.identity,{},true);index+=1 end
    app._visual=entries;app._portals=portals
end
function V.hit(app,x,y)
    for i=#app._visual,1,-1 do
        local node=app._visual[i]
        if not node.disabled and node.props.pointerEvents~="none" and node.inverse then
            local lx,ly=G.point(node.inverse,x,y);local b=node.box
            local inside=lx>=b.x and ly>=b.y and lx<b.x+b.width and ly<b.y+b.height
            if inside then for _,clip in ipairs(node.clips) do if not G.contains(clip,x,y) then inside=false;break end end end
            if inside and type(node.kind)=="string" then return node,lx,ly end
        end
    end
end
return V
