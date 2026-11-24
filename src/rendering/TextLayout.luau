local Backend=require("./Backend")
local U=require("../input/Unicode")
local Text={};local cache={};local order={};local limit=2048
function Text.layout(app,text,style,width,wrap)
    text=tostring(text or "");assert(#text<=65536,"XTGUI text exceeds native 64 KiB limit")
    local font,fontKey,size=Backend.font(app,style)
    local lineHeight=style.lineHeight or size*1.3
    local key=fontKey..":"..tostring(width)..":"..tostring(wrap)..":"..tostring(lineHeight)..":"..text
    if cache[key] then return cache[key] end
    local parts=U.split(text);local lines={};local first=0;local current="";local currentWidth=0;local maxWidth=0
    local function add(last,newline)
        local line={text=current,width=currentWidth,first=first,last=last,newline=newline,y=#lines*lineHeight,positions={0}}
        for i=first+1,last do local measured=Backend.measure(U.slice(parts,first,i),font);table.insert(line.positions,measured) end
        table.insert(lines,line);maxWidth=math.max(maxWidth,currentWidth)
    end
    for i,part in ipairs(parts) do
        if part=="\n" or part=="\r\n" or part=="\r" then
            add(i-1,true);first=i;current="";currentWidth=0
        else
            local candidate=current..part;local measured=Backend.measure(candidate,font)
            if wrap and width and width>0 and measured>width and current~="" then add(i-1,false);first=i-1;current=part;currentWidth=Backend.measure(part,font)
            else current=candidate;currentWidth=measured end
        end
    end
    add(#parts,false)
    local result={font=font,lines=lines,width=maxWidth,height=#lines*lineHeight,lineHeight=lineHeight,parts=parts}
    cache[key]=result;table.insert(order,key)
    if #order>limit then cache[table.remove(order,1)]=nil end
    return result
end
function Text.caret(layout,index)
    for i,line in ipairs(layout.lines) do
        if index<=line.last or i==#layout.lines then local localIndex=math.clamp(index-line.first,0,#line.positions-1);return line.positions[localIndex+1],line.y,i end
    end
    return 0,0,1
end
function Text.index(layout,x,y)
    local line=layout.lines[math.clamp(math.floor(y/layout.lineHeight)+1,1,#layout.lines)]
    for i=1,#line.positions-1 do if x<(line.positions[i]+line.positions[i+1])/2 then return line.first+i-1 end end
    return line.last
end
function Text.clear() cache={};order={} end
return Text
