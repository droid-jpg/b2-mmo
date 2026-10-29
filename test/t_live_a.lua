-- Game A of test/live2.sh: Michael challenges Hilda (game B) to a live battle and plays it.
local K = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "t_live_lib.lua")
dofile(K.env.root .. "test/t_live_two.lua")(K, { name = "Michael", host = true, other = "Hilda" })
