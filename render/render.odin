#+private
package render

import "core:strings"
import "core:c"
import "base:runtime"


import "core:os"
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

camera :: struct{
    position : [3]f32,
    rotation : quaternion128,
    fov      : f32,
}

scene :: struct{
    meshes    : []mesh,
    textures  : []texture, 
    materials : []material,
    //lights
    camera    : camera
}

// RENDER API
render_interface :: struct{ 
    render_scene : proc (scene : scene),
    mesh_create  : proc () -> mesh 
}


@export
load :: proc"c"(core : ^slate.core_interface){
    context = runtime.default_context()
    core.task_add_pool("render", 1)
    core.task_add_once("render/start", "render", start, nil)
    core.task_add_repeated("render/input", "render", input, {"render/start"})
    core.task_add_repeated("render/render", "render", render, {"render/input"})
}

window : ^sdl2.Window
gl_context : sdl2.GLContext

VBO : u32 
VAO : u32
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
    core.log(.INFO, "successfully created a window named %s with dimensions %ix%i", window_name, window_width, window_height)

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


    ok : bool
    test_shader, ok = gl.load_shaders_file("mods/render/shaders/vert.glsl", "mods/render/shaders/frag.glsl")
    if !ok {
        a, b, c, d := gl.get_last_error_messages()
        core.log(.ERROR, "Could not compile shaders\n %s\n %s", a, c)
    }else{
        core.log(.INFO, "Shaders loaded")
    }
    gl.UseProgram(test_shader)

    vertices := []f32{
        -0.5, -0.5, 0.0,
         0.5, -0.5, 0.0,
         0.0,  0.5, 0.0
    }

    gl.GenVertexArrays(1, &VAO)
    gl.GenBuffers(1, &VBO)
    
    gl.BindVertexArray(VAO)

    gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(f32), raw_data(vertices), gl.STATIC_DRAW)

    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)

    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0)



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
    
    gl.ClearColor(0.4, 0.1, 0.3, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
    

    gl.UseProgram(test_shader)
    gl.BindVertexArray(VAO)
    gl.DrawArrays(gl.TRIANGLES, 0, 3)

    sdl2.GL_SwapWindow(window)
}
