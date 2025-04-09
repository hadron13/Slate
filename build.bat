mkdir mods\render

odin build render -out:mods/render/render.dll -build-mode:shared -debug
odin build slate -out:slate.exe -debug