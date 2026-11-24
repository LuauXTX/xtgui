local suite=require("xtest").create()
require("./reactivity")(suite)
require("./application")(suite)
local result=suite.run()
local failed=0
for _,test in ipairs(result.tests) do
    if test.status=="failed" then failed+=1;print("FAIL "..test.fullName.."\n"..table.concat(test.failures,"\n")) end
end
print(string.format("XTGUI: %d tests, %d failed",#result.tests,failed))
assert(failed==0,"XTGUI tests failed")
