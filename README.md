# Slate
A Minimalist Modular Game Engine

## Compiling

### Requirements
- [Odin Compiler](https://odin-lang.org/docs/install/)
### Windows
_optionally you can use the [quick setup](https://github.com/hadron13/Slate/quick_setup.bat) script to download the Odin compiler using **curl**_
```cmd
  ./build.bat
```
### Linux
```cmd
  ./build.sh
```
## Running
`./slate.bin` on **Linux** or `./slate.exe` on **Windows**

The slate executable will search for a `config.txt` file and a `mods/` directory wherever it's executed

## Developing
### Introduction
The Slate game engine is subdivided into **Modules**, which are each loaded by the **Core**.
The Core is the main executable, and provides basic functionality to build on:
- Multithreaded task system
- Module management
- Module code injection (TBD)
- Module hot reload (TBD)
- Config system
- Logging


### Hello Module (in Odin)
Creating a new module is made as simple as possible, to create one yourself follow these steps:
- Create an Odin file with the following code:
```odin
package mymod
import "slate"

@export
load :: proc(core: ^slate.core_interface){
  core.log(.INFO, "Hello Module!")
}
```
- Copy the `slate.odin` file into the same directory as the file you just created
- Compile the file with `odin build myfile.odin -file -build-mode:shared`
- Move the resulting file inside the `mods` directory, inside another directory with the same name as your binary (e.g. `mods/mymod/mymod.dll`)
- Execute Slate
