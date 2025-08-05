@echo off
mkdir mods\render
mkdir mods\world

:: For when quick_setup.bat is used
set PATH=%PATH%;.\odin

echo building...

odin build render -out:mods/render/render.dll -build-mode:shared -debug
odin build world -out:mods/world/world.dll -build-mode:shared -debug
odin build slate -out:slate.exe -debug


set SDL2_DEST=mods\render\SDL2.dll

:: Check if SDL2.dll exists in destination
if exist "%SDL2_DEST%" (
    exit /b 0
)
echo importing SDL...

:: Get Odin path and construct SDL2 source path
for /f "delims=" %%i in ('where odin') do (
    set ODIN_PATH=%%i
    set SDL2_SRC=%%~dpivendor\sdl2\SDL2.dll
    goto :copy
)
:copy
echo copying SDL2 DLL...
copy "%SDL2_SRC%" "%SDL2_DEST%"
