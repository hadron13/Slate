mkdir -p mods/render

odin build render -out:mods/render/render.so -build-mode:shared -debug
odin build slate -out:slate.bin -debug

