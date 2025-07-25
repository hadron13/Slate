mkdir -p mods/render

if [[ render/render.odin -nt mods/render/render.so ]]; then
    odin build render -out:mods/render/render.so -build-mode:shared -debug
fi
if [[ slate/slate.odin -nt slate.bin ]]; then
    odin build slate -out:slate.bin -debug
fi

