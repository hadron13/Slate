#+private
package render

import "core:strings"
import "core:c"
import "base:runtime"

import "vendor:sdl2"
import "vendor:sdl2/image"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"


MODULE :: #config(MOD, "Render")
import "../slate"


mesh :: struct{
    
}

texture :: struct{

}

shader :: struct{

}

material :: struct{

    ior       : f32,
    metallic  : f32,
    alpha     : f32,
    
    albedo       : texture,
    normal       : texture,
    roughness    : texture,
    displacement : texture,
}


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

test_vbo : u32 
test_ebo : u32 
test_vao : u32
test_shader : u32


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

    core.log(.INFO, "loaded OpenGL version %s", gl.GetString(gl.VERSION))
    core.log(.INFO, "vendor: %s", gl.GetString(gl.VENDOR) )

    vertices := []f32{
       //back
       -1.0, -1.0, -1.0,     1.0, 1.0,   0.0, 0.0, -1.0,
        1.0, -1.0, -1.0,     0.0, 1.0,   0.0, 0.0, -1.0,
        1.0,  1.0, -1.0,     0.0, 0.0,   0.0, 0.0, -1.0,
       -1.0,  1.0, -1.0,     1.0, 0.0,   0.0, 0.0, -1.0,
        //front
       -1.0, -1.0,  1.0,     0.0, 1.0,   0.0, 0.0, 1.0,
        1.0, -1.0,  1.0,     1.0, 1.0,   0.0, 0.0, 1.0,
        1.0,  1.0,  1.0,     1.0, 0.0,   0.0, 0.0, 1.0,
       -1.0,  1.0,  1.0,     0.0, 0.0,   0.0, 0.0, 1.0,
        //left
       -1.0, -1.0, -1.0,     0.0, 1.0,  -1.0, 0.0, 0.0,
       -1.0,  1.0, -1.0,     0.0, 0.0,  -1.0, 0.0, 0.0,
       -1.0,  1.0,  1.0,     1.0, 0.0,  -1.0, 0.0, 0.0,
       -1.0, -1.0,  1.0,     1.0, 1.0,  -1.0, 0.0, 0.0,
        //right
        1.0, -1.0, -1.0,     1.0, 1.0,   1.0, 0.0, 0.0, 
        1.0,  1.0, -1.0,     1.0, 0.0,   1.0, 0.0, 0.0, 
        1.0,  1.0,  1.0,     0.0, 0.0,   1.0, 0.0, 0.0, 
        1.0, -1.0,  1.0,     0.0, 1.0,   1.0, 0.0, 0.0, 
        //down
       -1.0, -1.0, -1.0,     1.0, 0.0,   0.0, -1.0, 0.0,
       -1.0, -1.0,  1.0,     1.0, 1.0,   0.0, -1.0, 0.0,
        1.0, -1.0,  1.0,     0.0, 1.0,   0.0, -1.0, 0.0,
        1.0, -1.0, -1.0,     0.0, 0.0,   0.0, -1.0, 0.0,
        //up
       -1.0,  1.0, -1.0,     0.0, 0.0,   0.0, 1.0, 0.0,
       -1.0,  1.0,  1.0,     0.0, 1.0,   0.0, 1.0, 0.0,
        1.0,  1.0,  1.0,     1.0, 1.0,   0.0, 1.0, 0.0,
        1.0,  1.0, -1.0,     1.0, 0.0,   0.0, 1.0, 0.0,
    }

    indices := []u16{
        0, 1, 2,  0, 2, 3,
        6, 5, 4,  7, 6, 4,
        8, 9, 10,  8, 10, 11,
        14, 13, 12,  15, 14, 12,
        16, 17, 18,  16, 18, 19,
        22, 21, 20,  23, 22, 20
    }
    
    gl.GenVertexArrays(1, &test_vao)
    gl.BindVertexArray(test_vao)

    gl.GenBuffers(1, &test_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, test_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), cast(rawptr)&vertices, gl.STATIC_DRAW)

    gl.GenBuffers(1, & test_ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, test_ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), cast(rawptr)&vertices, gl.STATIC_DRAW)

    // position attribute
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    // texcoord attribute
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), (3 * size_of(f32)))
    gl.EnableVertexAttribArray(1)
    // texture coord attribute
    gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), (5 * size_of(f32)))
    gl.EnableVertexAttribArray(2)
    
    ok : bool
    test_shader, ok = gl.load_shaders_file("mods/render/shaders/vert.glsl", "mods/render/shaders/frag.glsl")
    if !ok {
        core.log(.ERROR, "Could not load the shaders")
    }
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
    
    mvp := glm.mat4Perspective(90, 1.3, 0.1, 100.0)
    model := glm.identity(matrix[4, 4]f32)

    gl.ClearColor(0.1, 0.1, 0.1, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)
    sdl2.GL_SwapWindow(window)
}
