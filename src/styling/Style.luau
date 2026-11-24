local C=require("../layout/Constraints")
local Theme=require("./Theme")
local S={}
local keys={"width","height","minWidth","maxWidth","minHeight","maxHeight","padding","margin","gap","rowGap","columnGap","flexGrow","flexShrink","flexBasis","alignItems","alignSelf","justifyContent","position","x","y","left","right","top","bottom","background","color","borderColor","borderWidth","radius","opacity","fontSize","fontFamily","fontWeight","fontPath","lineHeight","textAlign","verticalAlign","zIndex","overflow","display","cursor","transform","shadow"}
local layoutKeys={width=true,height=true,minWidth=true,maxWidth=true,minHeight=true,maxHeight=true,padding=true,margin=true,gap=true,rowGap=true,columnGap=true,flexGrow=true,flexShrink=true,flexBasis=true,alignItems=true,alignSelf=true,justifyContent=true,position=true,x=true,y=true,left=true,right=true,top=true,bottom=true,fontSize=true,fontFamily=true,fontWeight=true,fontPath=true,lineHeight=true,display=true}
local named={white="#FFFFFF",black="#000000",red="#FF0000",green="#008000",blue="#0000FF",transparent="#00000000",gray="#808080"}
local colorCache={}
function S.color(value,opacity)
    if value==nil then return nil end
    local c=value
    if type(value)=="string" then
        value=named[value] or value
        c=colorCache[value]
        if not c then
            local hex=value:match("^#(%x+)$");assert(hex,"XTGUI invalid color: "..value)
            if #hex==3 or #hex==4 then hex=hex:gsub(".",function(x)return x..x end) end
            assert(#hex==6 or #hex==8,"XTGUI colors use #RGB, #RGBA, #RRGGBB or #RRGGBBAA")
            c={tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16),#hex==8 and tonumber(hex:sub(7,8),16) or 255};colorCache[value]=c
        end
    end
    assert(type(c)=="table","XTGUI color must be a hex string or RGB(A) table")
    for i=1,4 do C.number(c[i] or (i==4 and 255 or -1),"color channel",0,255) end
    return {c[1],c[2],c[3],(c[4] or 255)*(opacity or 1)}
end
local function overlay(out,style)
    if not style then return end
    assert(type(style)=="table","XTGUI style must be a table")
    if style[1] then for _,s in ipairs(style) do overlay(out,s) end else for k,v in pairs(style) do out[k]=v end end
end
function S.validate(props,name)
    local style={};overlay(style,props.style);for _,k in ipairs(keys) do if props[k]~=nil then style[k]=props[k] end end
    for _,key in ipairs({"width","height","minWidth","maxWidth","minHeight","maxHeight","flexBasis","left","right","top","bottom"}) do if style[key]~=nil then C.dimension(style[key],100,key) end end
    for _,key in ipairs({"x","y"}) do if style[key]~=nil then C.number(style[key],key) end end
    for _,key in ipairs({"gap","rowGap","columnGap","borderWidth","radius","flexGrow","flexShrink"}) do if style[key]~=nil then C.number(style[key],key,0) end end
    if style.opacity~=nil then C.number(style.opacity,"opacity",0,1) end
    if style.fontSize~=nil then C.number(style.fontSize,"fontSize",1,512) end
    if style.padding~=nil then C.box(style.padding) end;if style.margin~=nil then C.box(style.margin) end
    for _,key in ipairs({"background","color","borderColor"}) do if style[key]~=nil and not(type(style[key])=="string" and style[key]:sub(1,1)=="$") then S.color(style[key]) end end
    if props.disabled~=nil then assert(type(props.disabled)=="boolean",name.." disabled must be boolean") end
    if props.text~=nil then assert(type(props.text)=="string" or type(props.text)=="number",name.." text must be string/number") end
    if style.position then assert(style.position=="absolute" or style.position=="relative","XTGUI invalid position") end
    if style.display then assert(style.display=="none" or style.display=="flex","XTGUI display must be flex or none") end
end
function S.resolve(node,parent,theme)
    local p=node.props;local colors=theme.colors
    local out={fontSize=parent and parent.fontSize or theme.fontSize,fontFamily=parent and parent.fontFamily or theme.fontFamily,fontWeight=parent and parent.fontWeight or 400,color=parent and parent.color or colors.text,
        alignItems="stretch",justifyContent="start",opacity=1,borderWidth=0,radius=0,gap=0,padding=0,margin=0,flexGrow=0,flexShrink=1}
    local kind=node.kind
    if kind=="Button" or kind=="IconButton" then overlay(out,{background=colors.surface,borderColor=colors.border,borderWidth=1,radius=theme.radius,padding={8,14},cursor="pointer",height=36}) end
    if kind=="IconButton" then out.width=36;out.padding=6 end
    if kind=="TextInput" or kind=="TextArea" then overlay(out,{background=colors.surface,borderColor=colors.border,borderWidth=1,radius=theme.radius,padding={7,10},cursor="text"}) end
    if kind=="ScrollView" then out.overflow="hidden" end
    if kind=="Spacer" then out.flexGrow=1 end
    if kind=="Separator" then out.background=colors.border end
    if kind=="ProgressBar" then out.background=colors.border;out.radius=4 end
    if kind=="Checkbox" or kind=="RadioButton" or kind=="Switch" or kind=="Slider" then out.cursor="pointer" end
    overlay(out,theme.components and theme.components[kind])
    overlay(out,p.style)
    for _,k in ipairs(keys) do if p[k]~=nil then out[k]=p[k] end end
    for _,state in ipairs({"hover","active","focused","disabled"}) do
        local active=state=="disabled" and node.disabled or node.interaction[state]
        if active then
            if (kind=="Button" or kind=="IconButton") and state=="hover" then out.background=colors.hover end
            if (kind=="Button" or kind=="IconButton") and state=="active" then out.background=colors.active end
            if state=="disabled" then out.opacity*=0.45 end
            overlay(out,p[state.."Style"] or (type(p.style)=="table" and p.style[state]))
        end
    end
    for _,k in ipairs({"background","color","borderColor"}) do if type(out[k])=="string" and out[k]:sub(1,1)=="$" then local token=out[k]:sub(2);assert(colors[token],"XTGUI unknown color token: "..token);out[k]=colors[token] end end
    out.padding=C.box(out.padding);out.margin=C.box(out.margin)
    return out
end
function S.affectsLayout(before,after)
    for k in pairs(layoutKeys) do if before[k]~=after[k] then return true end end
    return false
end
return S
