#+private
package render

import "core:strings"
import "core:c"
import "base:runtime"
import "core:math"

import "core:os"
import "core:time"
import "vendor:sdl2"
import "vendor:sdl2/image"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import stb "vendor:stb/image"


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
    velocity : [3]f32,
    yaw,pitch: f32,
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
    size : u64,
    version : slate.version,
    render_scene : proc (scene : scene),
    mesh_create  : proc () -> mesh 
}



chunk:: struct{
    blocks    : [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]u32,
    vao, vbo  : u32,
    offset    : [3]u32,
    transform : glm.mat4,    
}


@export
load :: proc"c"(core : ^slate.core_interface){
    context = runtime.default_context()
    core.task_add_pool("render", 1)
    core.task_add_once("render/start", "render", start, nil)
    core.task_add_repeated("render/input", "render", input, {"render/start"})
    core.task_add_repeated("render/render", "render", render, {"render/input"})

    core.module_set_version("render", {0, 0, 1})
}

window : ^sdl2.Window
gl_context : sdl2.GLContext
core : ^slate.core_interface


quad_ebo : u32

test_texture : u32
test_shader : u32
test_chunk : chunk
test_shader_uniforms : map[string]gl.Uniform_Info
main_camera : camera


camera_update :: proc"c"(camera : ^camera, delta_time : f32) -> glm.mat4{

    front :[3]f32= glm.normalize(
    [3]f32{math.cos(glm.radians(main_camera.yaw)) * math.cos(glm.radians(main_camera.pitch)),
           math.sin(glm.radians(main_camera.pitch)),
           math.sin(glm.radians(main_camera.yaw)) * math.cos(glm.radians(main_camera.pitch))})
    
    front_straight := glm.normalize([3]f32{front.x, 0, front.z})

    up := [3]f32{0, 1, 0} 
    right := glm.normalize(glm.cross(up, front_straight))

    main_camera.position -= right          * main_camera.velocity.x * delta_time
    main_camera.position += up             * main_camera.velocity.y * delta_time
    main_camera.position -= front_straight * main_camera.velocity.z * delta_time 

    return glm.mat4LookAt(main_camera.position, main_camera.position + front, {0, 1, 0})
}


chunk_create :: proc() -> chunk{
    
    chunk : chunk

    for x := 0; x < CHUNK_SIZE ; x+=1{
        for y := 0; y < CHUNK_SIZE ; y+=1{
            for z := 0; z < CHUNK_SIZE ; z+=1{
                chunk.blocks[x][y][z] = 0 
                if x+y+z < 7{ 
                    chunk.blocks[x][y][z] = 1 
                }
            }
        }
    }
    
    vertices:= chunk_mesh(&chunk)



    gl.GenVertexArrays(1, &(chunk.vao))
    gl.GenBuffers(1, &chunk.vbo)
    
    gl.BindVertexArray(chunk.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, chunk.vbo);
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(f32), raw_data(vertices), gl.STATIC_DRAW)

    
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 5 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 5 * size_of(f32), 3 * size_of(f32))
    gl.EnableVertexAttribArray(1)

    return chunk

}


//vertex format: XYZ - UV
append_quad :: proc(vertices : ^[dynamic]f32, a, b, c, d : [5]f32){
    last_vert :u32= cast(u32)len(vertices)/5
   
    append(vertices, a[0], a[1], a[2], a[3], a[4])
    append(vertices, b[0] + a[0], b[1] + a[1], b[2] + a[2], b[3], b[4])
    append(vertices, c[0] + a[0], c[1] + a[1], c[2] + a[2], c[3], c[4])
    append(vertices, d[0] + a[0], d[1] + a[1], d[2] + a[2], d[3], d[4])
    
    // append(indices, last_vert, last_vert+1, last_vert+2, last_vert+2, last_vert+1, last_vert+3)
}

CHUNK_SIZE :: 8

chunk_mesh :: proc(chunk : ^chunk) -> []f32{
    vertices := make([dynamic]f32, 0, 512 * 3)

    for x := 0; x < CHUNK_SIZE ; x+=1{
        for y := 0; y < CHUNK_SIZE ; y+=1{
            for z := 0; z < CHUNK_SIZE ; z+=1{ 
                if chunk.blocks[x][y][z] == 0 do continue 

                if x == 0 || chunk.blocks[x-1][y][z] == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 0, 0}, {0, 1, 0, 0, 1}, {0, 0, 1, 1, 0}, {0, 1, 1, 1, 1})
                }
                if y == 0 || chunk.blocks[x][y-1][z] == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 0, 0}, {0, 0, 1, 0, 1}, {1, 0, 0, 1, 0}, {1, 0, 1, 1, 1})
                }
                if z == 0 || chunk.blocks[x][y][z-1] == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 1, 0}, {1, 0, 0, 0, 0}, {0, 1, 0, 1, 1}, {1, 1, 0, 0, 1})
                }

                if x == CHUNK_SIZE-1 || chunk.blocks[x+1][y][z] == 0{
                    append_quad(&vertices, {f32(x)+1, f32(y), f32(z), 1, 0}, {0, 0, 1, 0, 0}, {0, 1, 0, 1, 1}, {0, 1, 1, 0, 1})
                }
                if y == CHUNK_SIZE-1 || chunk.blocks[x][y+1][z] == 0{
                    append_quad(&vertices, {f32(x), f32(y)+1, f32(z), 0, 0}, {1, 0, 0, 0, 1}, {0, 0, 1, 1, 0}, {1, 0, 1, 1, 1})
                }
                if z == CHUNK_SIZE-1 || chunk.blocks[x][y][z+1] == 0{
                     append_quad(&vertices, {f32(x), f32(y), f32(z)+1, 0, 0}, {0, 1, 0, 0, 1}, {1, 0, 0, 1, 0}, {1, 1, 0, 1, 1})
                }
            }
        }
    }
    
    return vertices[:]
}

start :: proc"c"(core_interface : ^slate.core_interface){
    context = runtime.default_context()
    core = core_interface
    sdl2.Init(sdl2.INIT_EVERYTHING)

    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
    
    window_name := core.config_get_string("render/window/name", "Slate")
    window_width := core.config_get_int("render/window/width", 800)
    window_height := core.config_get_int("render/window/height", 800)

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

    ok : bool
    test_shader, ok = gl.load_shaders_file("mods/render/shaders/vert.glsl", "mods/render/shaders/frag.glsl")
    if !ok {
        a, b, c, d := gl.get_last_error_messages()
        core.log(.ERROR, "Could not compile shaders\n %s\n %s", a, c)
        core.quit(-1)
    }else{
        core.log(.INFO, "Shaders loaded")
    }
    gl.UseProgram(test_shader)
    test_shader_uniforms = gl.get_uniforms_from_program(test_shader)

    indices  := make([dynamic]u32, 0, 2048)
    for i :u32= 0; i < 2048; i += 4{
        append(&indices, i, i+1, i+2, i+2, i+1, i+3)
    }


    test_chunk = chunk_create()
    
    gl.GenBuffers(1, &quad_ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad_ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)
       // gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 5 * size_of(f32))
    // gl.EnableVertexAttribArray(2)


    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0)

    img :: #load("textures/renatoemperra.png", string)

	gl.GenTextures(1, &test_texture)
	gl.BindTexture(gl.TEXTURE_2D_ARRAY, test_texture)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

   
    datas :[]string= {
        img
    }

    stb.set_flip_vertically_on_load(1)

    gl.TexImage3D(gl.TEXTURE_2D_ARRAY, 0, gl.SRGB8_ALPHA8, 320, 320, i32(len(datas)), 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)

    width, height, channels: i32

	for tex, idx in datas {
		pixels := stb.load_from_memory(raw_data(tex), i32(len(tex)), &width, &height, &channels, 4)
		gl.TexSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, i32(idx), 320, 320, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
		stb.image_free(pixels)
	}
    gl.GenerateMipmap(gl.TEXTURE_2D_ARRAY)
    

    sdl2.SetRelativeMouseMode(true)
    main_camera = {{0, 0, -2}, {0, 0, 0}, -90, 0, 90}

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
        
        case .KEYDOWN:
            #partial switch(event.key.keysym.sym){
            case .w: main_camera.velocity.z = -0.1
            case .a: main_camera.velocity.x = -0.1
            case .s: main_camera.velocity.z = 0.1
            case .d: main_camera.velocity.x = 0.1

            case .SPACE: main_camera.velocity.y = 0.1
            case .c: main_camera.velocity.y =    -0.1
            
            case .z: main_camera.fov = 20
            }
        case .KEYUP:
            #partial switch(event.key.keysym.sym){
            case .w: main_camera.velocity.z = 0
            case .a: main_camera.velocity.x = 0
            case .s: main_camera.velocity.z = 0
            case .d: main_camera.velocity.x = 0
            
            case .SPACE: main_camera.velocity.y = 0
            case .c: main_camera.velocity.y = 0
            
            case .z: main_camera.fov = 90 

            case .F6: gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
                
            case .ESCAPE:
                sdl2.SetRelativeMouseMode(!sdl2.GetRelativeMouseMode())
            }
        case .MOUSEMOTION:
            if(sdl2.GetRelativeMouseMode()){
                main_camera.yaw += cast(f32)event.motion.xrel * 0.2
                main_camera.pitch -= cast(f32)event.motion.yrel * 0.2
                main_camera.pitch = math.clamp(main_camera.pitch, -89.9, 89.9)
            }
        }
    }
}

render :: proc"c"(core : ^slate.core_interface){
    
    gl.ClearColor(0.1, 0.1, 0.1, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
   
    t : f32 = cast(f32)sdl2.GetTicks()/1000.0


    projection := glm.mat4PerspectiveInfinite(main_camera.fov, 800/640, 0.01)

    view := camera_update(&main_camera, 1.0)

        // view := glm.identity(glm.mat4)
    model := glm.mat4Translate(glm.vec3{0.0, -2.5, -4.0})
    
    gl.UseProgram(test_shader)
    // gl.Uniform1f(test_shader_uniforms["t"].location, t)
    gl.UniformMatrix4fv(test_shader_uniforms["proj"].location, 1, gl.FALSE, &projection[0,0])
    gl.UniformMatrix4fv(test_shader_uniforms["view"].location, 1, gl.FALSE, &view[0,0])
    gl.UniformMatrix4fv(test_shader_uniforms["model"].location, 1, gl.FALSE, &model[0,0])



    gl.BindVertexArray(test_chunk.vao)
    gl.DrawElements(gl.TRIANGLES, 2048, gl.UNSIGNED_INT, nil)

    sdl2.GL_SwapWindow(window)
}

render_chunks :: proc"c"(core : ^slate.core_interface){

}
