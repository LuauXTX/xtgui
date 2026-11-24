local U=require("./Unicode")
local Text=require("../rendering/TextLayout")
local Editor={};Editor.__index=Editor
local sessionClipboard=""
function Editor.new(text,multiline)
    local self=setmetatable({text=text or "",multiline=multiline,caret=0,anchor=0,undoStack={},redoStack={},composition="",scrollX=0,scrollY=0},Editor)
    self.parts=U.split(self.text);self.caret=#self.parts;self.anchor=self.caret;return self
end
function Editor:sync(text)
    text=tostring(text or "")
    if text==self.text then return end
    self.text=text;self.parts=U.split(text);self.caret=math.min(self.caret,#self.parts);self.anchor=math.min(self.anchor,#self.parts)
    self.undoStack={};self.redoStack={};self.composition=""
end
function Editor:range() return math.min(self.caret,self.anchor),math.max(self.caret,self.anchor) end
function Editor:selection() local lo,hi=self:range();return U.slice(self.parts,lo,hi) end
function Editor:snapshot() return {text=self.text,caret=self.caret,anchor=self.anchor} end
function Editor:restore(snapshot)
    self.text=snapshot.text;self.parts=U.split(self.text);self.caret=snapshot.caret;self.anchor=snapshot.anchor;self.composition="";self.goalX=nil
end
function Editor:replace(text,options)
    options=options or {}
    if options.readOnly then return false end
    text=text:gsub("\r\n","\n"):gsub("\r","\n"):gsub("[%z\1-\8\11\12\14-\31\127]","")
    if not self.multiline then text=text:gsub("[\n\t]","") end
    local lo,hi=self:range();local insert=U.split(text)
    if options.maxLength then local max=math.max(0,options.maxLength-(#self.parts-(hi-lo)));while #insert>max do table.remove(insert) end end
    local nextText=U.slice(self.parts,0,lo)..table.concat(insert)..U.slice(self.parts,hi)
    if nextText==self.text then self.composition="";return false end
    table.insert(self.undoStack,self:snapshot());if #self.undoStack>100 then table.remove(self.undoStack,1) end
    self.redoStack={};self.text=nextText;self.parts=U.split(nextText);self.caret=lo+#insert;self.anchor=self.caret;self.composition="";self.goalX=nil
    return true
end
function Editor:move(index,extend)
    self.caret=math.clamp(index,0,#self.parts);if not extend then self.anchor=self.caret end;self.goalX=nil
end
function Editor:word(index,direction)
    if direction<0 then
        while index>0 and not U.word(self.parts[index]) do index-=1 end
        while index>0 and U.word(self.parts[index]) do index-=1 end
    else
        while index<#self.parts and U.word(self.parts[index+1]) do index+=1 end
        while index<#self.parts and not U.word(self.parts[index+1]) do index+=1 end
    end
    return index
end
function Editor:clipboard(app,write)
    local provider=app.options.clipboard
    if write~=nil then
        assert(type(write)=="string","XTGUI clipboard contents must be a string")
        if provider then provider.set(write) else sessionClipboard=write end
        return write
    end
    local text=provider and provider.get() or sessionClipboard
    assert(type(text)=="string" and utf8.len(text),"XTGUI clipboard provider returned invalid UTF-8")
    return text
end
function Editor:undo(redo)
    local from=redo and self.redoStack or self.undoStack;local to=redo and self.undoStack or self.redoStack
    local item=table.remove(from);if not item then return false end
    table.insert(to,self:snapshot());self:restore(item);return true
end
function Editor:key(key,mods,layout,options,app)
    mods=mods or {};options=options or {};local command=mods.control or mods.super;local word=command or mods.alt
    local lower=string.lower(key);local changed=false
    if command and lower=="a" then self.anchor=0;self.caret=#self.parts
    elseif command and (lower=="c" or lower=="x") then
        if not options.password then self:clipboard(app,self:selection()) end
        if lower=="x" and not options.password then changed=self:replace("",options) end
    elseif command and lower=="v" then changed=self:replace(self:clipboard(app),options)
    elseif command and lower=="z" then if not options.readOnly then changed=self:undo(mods.shift) end
    elseif command and lower=="y" then if not options.readOnly then changed=self:undo(true) end
    elseif key=="ArrowLeft" or key=="ArrowRight" then
        local direction=key=="ArrowLeft" and -1 or 1;local lo,hi=self:range();local index=self.caret
        if not mods.shift and lo~=hi then index=direction<0 and lo or hi else index=word and self:word(index,direction) or index+direction end
        self:move(index,mods.shift)
    elseif key=="Home" or key=="End" then
        local index=key=="Home" and 0 or #self.parts
        if not command and layout then local _,_,line=Text.caret(layout,self.caret);index=key=="Home" and layout.lines[line].first or layout.lines[line].last end
        self:move(index,mods.shift)
    elseif (key=="ArrowUp" or key=="ArrowDown" or key=="PageUp" or key=="PageDown") and self.multiline and layout then
        local cx,cy=Text.caret(layout,self.caret);local goal=self.goalX or cx
        local step=(key=="PageUp" or key=="PageDown") and math.max(1,math.floor((options.viewportHeight or 120)/layout.lineHeight)) or 1
        local dy=(key=="ArrowUp" or key=="PageUp") and -step or step
        self:move(Text.index(layout,goal,cy+dy*layout.lineHeight),mods.shift);self.goalX=goal
    elseif key=="Backspace" or key=="Delete" then
        local lo,hi=self:range()
        if lo==hi then local direction=key=="Backspace" and -1 or 1;self.anchor=math.clamp(word and self:word(self.caret,direction) or self.caret+direction,0,#self.parts) end
        changed=self:replace("",options)
    elseif key=="Enter" and self.multiline and not command then changed=self:replace("\n",options)
    elseif key=="Tab" and self.multiline and options.acceptTab then changed=self:replace("\t",options)
    else return false,false end
    return true,changed
end
function Editor:display(password)
    local parts=self.parts
    if password then parts=table.create(#parts,"•") end
    local lo,hi=self:range()
    if self.composition~="" then
        local preedit=U.split(self.composition);local display=U.slice(parts,0,lo)..self.composition..U.slice(parts,hi)
        return display,lo+(self.compositionCursor or #preedit),lo,lo+#preedit
    end
    return table.concat(parts),self.caret
end
return Editor
