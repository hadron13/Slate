mkdir mods\render

odin build render -out:mods/render/render.dll -build-mode:shared -debug
odin build slate -out:slate.exe -debug


IF NOT EXISTS mods\render\SDL2.dll (
    echo SDL2.dll not found, copying from Odin directory
    FOR /F "tokens=*" %%g IN ('where odin') do (SET SUBDIR=%%g)
    SET ODIN_PATH=%SUBDIR:~0,-8%
    SET SDL2_DIR="vendor\sdl2\SDL2.dll"
    SET SDL2_PATH=%ODIN_PATH%%SDL2_DIR%
    echo %SDL2_PATH%
    copy %SDL2_PATH% mods\render\SDL2.dll
)
