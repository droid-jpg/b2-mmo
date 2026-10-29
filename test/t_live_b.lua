-- Game B of test/live2.sh: Hilda answers Michael's challenge with Yes in the game's text box and plays.
LIVE_OUT = "out/b/"
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "t_live_lib.lua")
dofile(K.env.root .. "test/t_live_two.lua")(K, { name = "Hilda", host = false, other = "Michael" })
