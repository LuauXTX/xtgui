return {
    linear=function(t)return t end,
    easeInQuad=function(t)return t*t end,
    easeOutQuad=function(t)return 1-(1-t)^2 end,
    easeInOutQuad=function(t)return t<0.5 and 2*t*t or 1-(-2*t+2)^2/2 end,
    easeInCubic=function(t)return t^3 end,
    easeOutCubic=function(t)return 1-(1-t)^3 end,
    easeInOutCubic=function(t)return t<0.5 and 4*t^3 or 1-(-2*t+2)^3/2 end,
    easeOutSine=function(t)return math.sin(t*math.pi/2) end,
    easeInOutSine=function(t)return -(math.cos(math.pi*t)-1)/2 end,
}
