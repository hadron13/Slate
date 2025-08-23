mkdir -p mods/world
mkdir -p mods/render
mkdir -p mods/render/shaders

if find render -type f -newer mods/render/render.so | grep -q .; then
    odin build render -out:mods/render/render.so -build-mode:shared -o:speed
fi
if find world -type f -newer mods/world/world.so | grep -q .; then
    odin build world -out:mods/world/world.so -build-mode:shared -o:speed
fi
if [[ slate/slate.odin -nt slate.bin ]]; then
    odin build slate -out:slate.bin -o:speed
fi

cp render/shaders/* mods/render/shaders
