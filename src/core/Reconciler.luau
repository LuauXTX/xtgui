local State = require("./State")
local Element = require("./Element")
local Style = require("../styling/Style")
local R = {}

local function descriptor(value)
    if value == nil or value == false then return nil end
    if type(value) == "string" or type(value) == "number" then return { type="Text",props={text=tostring(value)} } end
    assert(type(value)=="table" and value.type and type(value.props)=="table", "XTGUI expected a component descriptor in children")
    return value
end
local function disposeHook(hook)
    local value=hook.value
    if type(value)=="table" and type(value.dispose)=="function" then value:dispose() end
end
function R.destroy(node)
    if not node or not node.alive then return end
    node.alive=false; State.detach(node)
    local function cleanup(callback)
        local ok,err=pcall(callback)
        if not ok then node.app._cleanupErrors=node.app._cleanupErrors or {};table.insert(node.app._cleanupErrors,node.name..": "..tostring(err)) end
    end
    for _, child in ipairs(node.children) do R.destroy(child) end
    -- Detach effects before disposing their state dependencies.
    for _, hook in ipairs(node.hooks) do if hook.kind=="effect" then cleanup(function()disposeHook(hook)end) end end
    for _, hook in ipairs(node.hooks) do if hook.kind~="effect" then cleanup(function()disposeHook(hook)end) end end
    local ref=node.props.ref
    if type(ref)=="table" and ref.current==node then ref.current=nil elseif type(ref)=="function" then cleanup(function()ref(nil)end) end
    cleanup(function()node.app:_unmounted(node)end)
    if node.props.onUnmount then cleanup(function()node.props.onUnmount(node)end) end
end
local function propsRead(source)
    local result={}
    for k,v in pairs(source) do result[k]= k=="children" and v or State.read(v) end
    return result
end
function R.prepare(app, old, value)
    local created, scopes = {}, {}
    local count=0
    local build
    build=function(previous, description, parent, depth)
        description=descriptor(description)
        if not description then return nil end
        count+=1;assert(depth<=128 and count<=100000,"XTGUI component nesting/tree limit exceeded")
        local kind=description.type
        assert((type(kind)=="string" and app.api._hosts[kind]) or (type(kind)=="table" and kind._component),"XTGUI unknown component: "..tostring(kind))
        local key=description.key or description.props.key
        assert(key==nil or type(key)=="string" or type(key)=="number","XTGUI keys must be strings or numbers")
        local node=previous
        if not node or not node.alive or node.kind~=kind or node.key~=key then node=Element.new(kind,app);table.insert(created,node) end
        if node==previous and node.descriptor==description and not node.dirty and not node.subtreeDirty then return {node=node,reuse=true} end
        local plan={node=node,description=description,parent=parent,key=key,children={}}
        local children
        if type(kind)=="table" then
            local scope={name=kind.name,app=app,node=node,hooks=table.clone(node.hooks),hookIndex=0,hookCount=node.hookCount,pendingEffects={},computedChanges={}}
            table.insert(scopes,{scope=scope,oldCount=#node.hooks})
            local owner,rendering=State.owner,State.rendering
            State.owner=scope;State.rendering=true
            local ok,deps,output=pcall(function() return State.capture(function() return kind.render(description.props,app.api) end) end)
            State.owner=owner;State.rendering=rendering
            if not ok then error("XTGUI "..kind.name..": "..tostring(deps),0) end
            assert(not scope.hookCount or scope.hookIndex==scope.hookCount,"XTGUI hook count changed in "..kind.name)
            scope.hookCount=scope.hookIndex
            plan.scope=scope;plan.dependencies=deps;plan.props=description.props
            children={output}
        else
            plan.dependencies,plan.props=State.capture(function() return propsRead(description.props) end)
            Style.validate(plan.props,kind)
            if app.api._validate then app.api._validate(kind,plan.props) end
            children=plan.props.children or {}
            assert(type(children)=="table","XTGUI "..kind.." children must be an array")
            if kind=="Text" or kind=="Image" or kind=="TextInput" or kind=="TextArea" then assert(#children==0,"XTGUI "..kind.." cannot contain children") end
        end
        local keyed={};local keys={}
        for _,child in ipairs(node.children) do if child.key~=nil then keyed[child.key]=child end end
        for index,child in ipairs(children) do
            child=descriptor(child)
            if child then
                local childKey=child.key or child.props.key
                if childKey~=nil then assert(not keys[childKey],"XTGUI duplicate key: "..tostring(childKey));keys[childKey]=true end
                local candidate=childKey~=nil and keyed[childKey] or node.children[index]
                local childPlan=build(candidate,child,node,depth+1)
                if childPlan then table.insert(plan.children,childPlan) end
            end
        end
        return plan
    end
    local ok,plan=pcall(function()
        local result=build(old,value,old and old.parent,1)
        if app._preflight then app:_preflight(result) end
        return result
    end)
    if not ok then
        for _,item in ipairs(scopes) do
            for _,change in ipairs(item.scope.computedChanges) do
                change.value.callback=change.callback;change.value.dirty=change.dirty;change.value.value=change.cached;State.commitDependencies(change.value,change.dependencies)
            end
            for i=item.oldCount+1,#item.scope.hooks do disposeHook(item.scope.hooks[i]) end
        end
        for _,node in ipairs(created) do node.alive=false end
        error(plan,0)
    end
    return plan
end
function R.commit(app,plan,parent)
    if not plan then return nil end
    local node=plan.node
    node.parent=parent
    if plan.reuse then return node end
    local mounted=node.descriptor==nil
    local oldRef=node.props.ref
    node.descriptor=plan.description;node.key=plan.key;node.rawProps=table.clone(plan.description.props);node.props=plan.props
    node.dirty=false;node.subtreeDirty=false;node.paintDirty=true;node.layoutDirty=true;node.renderCount+=1
    State.commitDependencies(node,plan.dependencies)
    if plan.scope then
        node.hooks=plan.scope.hooks;node.hookCount=plan.scope.hookCount
        for _,pending in ipairs(plan.scope.pendingEffects) do
            pending.effect.callback=pending.callback;pending.effect.started=true
            table.insert(app._afterLayout,function() pending.effect:invalidate() end)
        end
    end
    local used={};local children={}
    for _,childPlan in ipairs(plan.children) do local child=R.commit(app,childPlan,node);used[child]=true;table.insert(children,child) end
    for _,child in ipairs(node.children) do if not used[child] then R.destroy(child) end end
    node.children=children
    if oldRef~=node.props.ref then
        if type(oldRef)=="table" and oldRef.current==node then oldRef.current=nil elseif type(oldRef)=="function" then oldRef(nil) end
    end
    local ref=node.props.ref
    if type(ref)=="table" then ref.current=node elseif type(ref)=="function" then ref(node) end
    if mounted and node.props.onMount then table.insert(app._afterLayout,function() if node.alive then node.props.onMount(node) end end) end
    return node
end
return R
