#+private
package render

import "core:strings"
import "core:c"
import "base:runtime"

import "vendor:sdl2"
import "vendor:sdl2/image"
import gl "vendor:OpenGL"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:time"


MODULE :: #config(MOD, "Render")
import "../slate"

@export
load :: proc"c"(core : ^slate.core_interface){
    context = runtime.default_context()
    core.task_add_pool("render", 1)
    core.task_add_once("render/start", "render", start, nil)
    core.task_add_repeated("render/input", "render", input, {"render/start"})
    core.task_add_repeated("render/render", "render", render, {"render/input"})
    render_allocator = runtime.default_allocator()
}

window : ^sdl2.Window
gl_context : sdl2.GLContext
render_allocator: runtime.Allocator




start :: proc"c"(core : ^slate.core_interface){
    context = runtime.default_context()


    sdl2.Init(sdl2.INIT_EVERYTHING)

    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
    
    window_name := core.config_get_string("render/window/name", "Slate")
    window_width := core.config_get_int("render/window/width", 800)
    window_height := core.config_get_int("render/window/height", 640)

    window = sdl2.CreateWindow(strings.clone_to_cstring(window_name, context.temp_allocator), sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED, i32(window_width), i32(window_height), sdl2.WINDOW_RESIZABLE | sdl2.WINDOW_OPENGL)
    if(window == nil){
        core.log(.ERROR, "could not create a window sdl error: %s", sdl2.GetError())
        core.quit(-1)
    }
    // core.log(.INFO, "successfully created a window named %s with dimensions %ix%i", "budega", window_width, window_height)

    gl_context = sdl2.GL_CreateContext(window)
    if(gl_context == nil){
        core.log(.ERROR, "could not create an OpenGL context sdl error: %s", sdl2.GetError())
        core.quit(-1)
    }
    core.log(.INFO, "successfully created an OpenGL context")

    sdl2.GL_SetSwapInterval(-1)

    gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

    version_string := strings.clone_from_cstring(gl.GetString(gl.VERSION))
    core.log(.INFO, "loaded OpenGL version %s", "idoso")

    // core.log(.INFO, "vendor: %v", gl.GetString(gl.VENDOR) )
}


my_log :: proc"c"(format : string, args: ..any){
    context = runtime.default_context()
    fmt.printf(format, ..args)
}

input :: proc"c"(core : ^slate.core_interface){ 
    event: sdl2.Event
    for ;sdl2.PollEvent(&event);{
        if event.type == sdl2.EventType.QUIT {
            sdl2.GL_DeleteContext(gl_context)
            sdl2.DestroyWindow(window)
            sdl2.Quit()
            core.quit(0)
        }
    }
    
}

render :: proc"c"(core : ^slate.core_interface){
    
    gl.ClearColor(0.1, 0.1, 0.1, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    sdl2.GL_SwapWindow(window)
}





