#+private
package render

import "core:strings"
import "core:c"
import "base:runtime"


import "core:os"
import "core:time"
import "vendor:sdl2"
import "vendor:sdl2/image"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"


MODULE :: #config(MOD, "Render")
import "../slate"


mesh :: struct{
    VAO: u32,
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
EBO : u32
VAO : u32
test_shader : u32
test_shader_uniforms : map[string]gl.Uniform_Info


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

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl.FRONT)
    // gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)

    ok : bool
    test_shader, ok = gl.load_shaders_file("mods/render/shaders/vert.glsl", "mods/render/shaders/frag.glsl")
    if !ok {
        a, b, c, d := gl.get_last_error_messages()
        core.log(.ERROR, "Could not compile shaders\n %s\n %s", a, c)
    }else{
        core.log(.INFO, "Shaders loaded")
    }
    gl.UseProgram(test_shader)
    test_shader_uniforms = gl.get_uniforms_from_program(test_shader)

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

    indices := []u32{
        0, 1, 2,  0, 2, 3,
        6, 5, 4,  7, 6, 4,
        8, 9, 10,  8, 10, 11,
        14, 13, 12,  15, 14, 12,
        16, 17, 18,  16, 18, 19,
        22, 21, 20,  23, 22, 20
    }

    gl.GenVertexArrays(1, &VAO)
    gl.GenBuffers(1, &VBO)
    gl.GenBuffers(1, &EBO)
    
    gl.BindVertexArray(VAO)

    gl.BindBuffer(gl.ARRAY_BUFFER, VBO);
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(f32), raw_data(vertices), gl.STATIC_DRAW)

    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, EBO)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)
    
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 3 * size_of(f32))
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 5 * size_of(f32))
    gl.EnableVertexAttribArray(2)

    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0)



}

input :: proc"c"(core : ^slate.core_interface){ 
    event: sdl2.Event
    for ;sdl2.PollEvent(&event);{
        #partial switch(event.type){
            case .QUIT:
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
   
    t : f32 = cast(f32)sdl2.GetTicks()/1000.0

    projection := glm.mat4PerspectiveInfinite(90, 800/640, 0.01)
    view := glm.identity(glm.mat4)
    model := glm.mat4Translate(glm.vec3{0.0, 0.0, -4.0}) * glm.mat4Rotate(glm.vec3{0, 1.0, 0}, t)
    
    gl.UseProgram(test_shader)
    // gl.Uniform1f(test_shader_uniforms["t"].location, t)
    gl.UniformMatrix4fv(test_shader_uniforms["proj"].location, 1, gl.FALSE, &projection[0,0])
    gl.UniformMatrix4fv(test_shader_uniforms["view"].location, 1, gl.FALSE, &view[0,0])
    gl.UniformMatrix4fv(test_shader_uniforms["model"].location, 1, gl.FALSE, &model[0,0])



    gl.BindVertexArray(VAO)
    gl.DrawElements(gl.TRIANGLES, 36, gl.UNSIGNED_INT, nil)

    sdl2.GL_SwapWindow(window)
}
