mkdir -p mods/world
mkdir -p mods/render
mkdir -p mods/render/shaders

if find render -type f -newer mods/render/render.so | grep -q . || [[ ! -f mods/render/render.so ]]; then
    odin build render -out:mods/render/render.so -build-mode:shared -o:speed -debug
fi
if find world -type f -newer mods/world/world.so | grep -q . || [[ ! -f mods/world/world.so ]]; then
    odin build world -out:mods/world/world.so -build-mode:shared -o:speed -debug
fi
if [[ slate/slate.odin -nt slate.bin ]]; then
    odin build slate -out:slate.bin -o:speed -define:TRACY_ENABLE=true -debug
fi

cp render/shaders/* mods/render/shaders
