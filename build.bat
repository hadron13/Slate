mkdir mods\render

odin build render -out:mods/render/render.dll -build-mode:shared -debug
odin build slate -out:slate.exe -debug

set SDL2_DEST=mods\render\SDL2.dll

:: Check if SDL2.dll exists in destination
if exist "%SDL2_DEST%" (
    exit /b 0
)

:: Get Odin path and construct SDL2 source path
for /f "delims=" %%i in ('where odin') do (
    set ODIN_PATH=%%i
    set SDL2_SRC=%%~dpivendor\sdl2\SDL2.dll
    goto :copy
)
:copy
copy "%SDL2_SRC%" "%SDL2_DEST%"
