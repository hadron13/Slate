#+private
package render

import "core:strings"
import "core:c"
import "base:runtime"
import "core:math"

import "core:os"
import "core:mem"
import "core:fmt"
import "core:time"
import "vendor:sdl2"
import "vendor:sdl2/image"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import "core:math/linalg"
import "core:math/noise"
import stb "vendor:stb/image" 
DISABLE_DOCKING :: #config(DISABLE_DOCKING, false)
import imgui "imgui"
import imgui_sdl2 "imgui/imgui_impl_sdl2"
import imgui_opengl "imgui/imgui_impl_opengl3"



MODULE :: #config(MOD, "Render")
import "../slate"
import world_interface "../world/interface"


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







@export
load :: proc"c"(core : ^slate.core_interface) -> slate.version{
    core.task_add_pool("render", 1)
    core.task_add_once("render/start", "render", start, nil, nil)
    core.task_add_repeated("render/input", "render", input, nil, {"render/start"})
    core.task_add_repeated("render/render", "render", render, nil, {"render/input"})

    return {0, 0, 1}
}

window : ^sdl2.Window
gl_context : sdl2.GLContext
core  : ^slate.core_interface
world : ^world_interface.world_interface
render_context : runtime.Context

test_texture :u32
test_shader : u32
test_shader_uniforms : map[string]gl.Uniform_Info
main_camera : camera

last_frame_time    : u64
current_frame_time : u64


when ODIN_DEBUG{
    track: mem.Tracking_Allocator
}

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




start :: proc"c"(core_interface : ^slate.core_interface, data: rawptr){
    context = runtime.default_context() 

    when ODIN_DEBUG{
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }


    render_context = context

    core = core_interface
    world = auto_cast(core.module_get_interface("world"))
    if world == nil{
        core.log(.ERROR, "world interface not found")
    }

    sdl2.Init(sdl2.INIT_EVERYTHING)

    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_MAJOR_VERSION, 3)
    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_MINOR_VERSION, 3)
    sdl2.GL_SetAttribute(sdl2.GLattr.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))

    sdl2.GL_SetAttribute(sdl2.GLattr.DEPTH_SIZE, 24)
    
    window_name := core.config_get_string("render/window/name", "Slate")
    window_width := core.config_get_int("render/window/width", 1200)
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

    if core.config_get_bool("render/vsync", true){
        if(sdl2.GL_SetSwapInterval(-1) == -1){
            sdl2.GL_SetSwapInterval(1)
        }
    }else{
        sdl2.GL_SetSwapInterval(0)
    }


    gl.load_up_to(3, 3, sdl2.gl_set_proc_address)


    core.log(.INFO, "loaded OpenGL version %s", gl.GetString(gl.VERSION))
    core.log(.INFO, "vendor: %s", gl.GetString(gl.VENDOR) )




    imgui.CHECKVERSION()
    imgui.CreateContext()

	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .NavEnableGamepad}
	when !DISABLE_DOCKING {
		io.ConfigFlags += {.DockingEnable}
		io.ConfigFlags += {.ViewportsEnable}

		style := imgui.GetStyle()
		style.WindowRounding = 0
		style.Colors[imgui.Col.WindowBg].w =1
	}

    imgui.StyleColorsDark()

	imgui_sdl2.InitForOpenGL(window, gl_context)
	imgui_opengl.Init(nil)


    core.on_quit(quit)


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


    gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BindVertexArray(0)


	gl.GenTextures(1, &test_texture)
	gl.BindTexture(gl.TEXTURE_2D_ARRAY, test_texture)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

   
    datas :[]string= {
        #load("textures/stone.png", string),
        #load("textures/snad.png", string),
        #load("textures/grass.png", string),
    }

    stb.set_flip_vertically_on_load(1)

    gl.TexImage3D(gl.TEXTURE_2D_ARRAY, 0, gl.RGBA, 64, 64, i32(len(datas)), 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)

    width, height, channels: i32 

	for tex, idx in datas {
		pixels := stb.load_from_memory(raw_data(tex), i32(len(tex)), &width, &height, &channels, 4)
		gl.TexSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, i32(idx), 64, 64, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
		stb.image_free(pixels)
	}
    gl.GenerateMipmap(gl.TEXTURE_2D_ARRAY)

	if sdl2.GL_ExtensionSupported("GL_EXT_texture_filter_anisotropic") {
		filter: f32
		gl.GetFloatv(gl.MAX_TEXTURE_MAX_ANISOTROPY, &filter)
		gl.TexParameterf(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAX_ANISOTROPY, filter)
	}
    

    // sdl2.SetRelativeMouseMode(true)
    main_camera = {{0, 32, 0}, {0, 0, 0}, -90, 0, 90}


    test_world := world.world_get("")
    
    WORLD_SIZE :: 16

    for x :i32= -WORLD_SIZE ; x < WORLD_SIZE; x+=1{
        for y :i32= 0; y < 12; y+=1{
            for z :i32= -WORLD_SIZE; z < WORLD_SIZE; z+=1{ 

                world.chunk_load(test_world, {x, y, z}, 
                    proc"c"(current_world : ^world_interface.world, position : [3]i32) { 
                        context = render_context
                        task_data := new(struct{world: ^world_interface.world, pos: [3]i32})
                        task_data.world = current_world
                        task_data.pos = position
                        task_name := fmt.aprintf("render/mesh_chunk[%i,%i,%i]", position.x, position.y, position.z)
                        core.task_add_once(task_name,
                                "render", chunk_mesh_task, task_data, nil)
                        delete(task_name)
                    }
                )

            }
        }
    }
}

input :: proc"c"(core : ^slate.core_interface, data: rawptr){ 
    event: sdl2.Event
    for ;sdl2.PollEvent(&event);{
        #partial switch(event.type){
        case .QUIT:
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
        case .WINDOWEVENT:
            #partial switch(event.window.event){
                case .RESIZED:
                    width, height : c.int
                    sdl2.GetWindowSize(window, &width, &height)
                    gl.Viewport(0, 0, width, height)

            }   
        }

        imgui_sdl2.ProcessEvent(&event)
    }
    last_frame_time = sdl2.GetPerformanceCounter()
}


testAabb :: proc"contextless"(MPV: glm.mat4, min, max: glm.vec3) -> bool{
	nxX := MPV[0][3] + MPV[0][0]; nxY := MPV[1][3] + MPV[1][0]; nxZ := MPV[2][3] + MPV[2][0]; nxW := MPV[3][3] + MPV[3][0]
	pxX := MPV[0][3] - MPV[0][0]; pxY := MPV[1][3] - MPV[1][0]; pxZ := MPV[2][3] - MPV[2][0]; pxW := MPV[3][3] - MPV[3][0]
	nyX := MPV[0][3] + MPV[0][1]; nyY := MPV[1][3] + MPV[1][1]; nyZ := MPV[2][3] + MPV[2][1]; nyW := MPV[3][3] + MPV[3][1]
	pyX := MPV[0][3] - MPV[0][1]; pyY := MPV[1][3] - MPV[1][1]; pyZ := MPV[2][3] - MPV[2][1]; pyW := MPV[3][3] - MPV[3][1]
	nzX := MPV[0][3] + MPV[0][2]; nzY := MPV[1][3] + MPV[1][2]; nzZ := MPV[2][3] + MPV[2][2]; nzW := MPV[3][3] + MPV[3][2]
	pzX := MPV[0][3] - MPV[0][2]; pzY := MPV[1][3] - MPV[1][2]; pzZ := MPV[2][3] - MPV[2][2]; pzW := MPV[3][3] - MPV[3][2]
	
	return nxX * (nxX < 0 ? min[0] : max[0]) + nxY * (nxY < 0 ? min[1] : max[1]) + nxZ * (nxZ < 0 ? min[2] : max[2]) >= -nxW &&
		pxX * (pxX < 0 ? min[0] : max[0]) + pxY * (pxY < 0 ? min[1] : max[1]) + pxZ * (pxZ < 0 ? min[2] : max[2]) >= -pxW &&
		nyX * (nyX < 0 ? min[0] : max[0]) + nyY * (nyY < 0 ? min[1] : max[1]) + nyZ * (nyZ < 0 ? min[2] : max[2]) >= -nyW &&
		pyX * (pyX < 0 ? min[0] : max[0]) + pyY * (pyY < 0 ? min[1] : max[1]) + pyZ * (pyZ < 0 ? min[2] : max[2]) >= -pyW &&
		nzX * (nzX < 0 ? min[0] : max[0]) + nzY * (nzY < 0 ? min[1] : max[1]) + nzZ * (nzZ < 0 ? min[2] : max[2]) >= -nzW &&
		pzX * (pzX < 0 ? min[0] : max[0]) + pzY * (pzY < 0 ? min[1] : max[1]) + pzZ * (pzZ < 0 ? min[2] : max[2]) >= -pzW;
}

 
render :: proc"c"(core : ^slate.core_interface, data: rawptr){
    last_frame_time = current_frame_time 
    current_frame_time = sdl2.GetPerformanceCounter()
    
    delta_t := f64(current_frame_time - last_frame_time)/f64(sdl2.GetPerformanceFrequency())

    
    imgui_opengl.NewFrame()
    imgui_sdl2.NewFrame()
    imgui.NewFrame()

    // imgui.ShowDemoWindow(nil)
    @static 
    camera_speed :f32= 1.0

    if imgui.Begin("Debug Window") {
        imgui.Text("FPS: %f", 1/delta_t)
        imgui.Text("Frame Time: %fms", delta_t*1000.0)
        imgui.SliderFloat("FOV", &main_camera.fov, 5.0, 179.0)
        imgui.SliderFloat("Speed", &camera_speed, 0.1, 10.0)

        @static vsync : bool 
        vsync = core.config_get_bool("render/vsync", true)

        if imgui.Checkbox("V-sync", &vsync){
            if vsync {
                if(sdl2.GL_SetSwapInterval(-1) == -1){
                    sdl2.GL_SetSwapInterval(1)
                }
            }else{
                sdl2.GL_SetSwapInterval(0)
            }
            core.config_set({"render/vsync", vsync})
        }
    }
    imgui.End()

    imgui.Render()



    gl.ClearColor(0.04, 0.76, 0.94, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
   

    width, height : c.int
    sdl2.GetWindowSize(window, &width, &height)
    projection := glm.mat4PerspectiveInfinite(main_camera.fov * math.RAD_PER_DEG, f32(width)/f32(height), 0.01)
    view := camera_update(&main_camera, f32(delta_t) * camera_speed * 60)
    model := glm.identity(glm.mat4)
    
    gl.UseProgram(test_shader)
    gl.UniformMatrix4fv(test_shader_uniforms["proj"].location, 1, gl.FALSE, &projection[0,0])
    gl.UniformMatrix4fv(test_shader_uniforms["view"].location, 1, gl.FALSE, &view[0,0])
    gl.UniformMatrix4fv(test_shader_uniforms["model"].location, 1, gl.FALSE, &model[0,0])
   
    proj_view := projection * view
    for key, &chunk in chunk_map{
        minC := CHUNK_SIZE * glm.vec3{f32(key.x), f32(key.y), f32(key.z)}
		maxC := minC + CHUNK_SIZE
        middle := minC + CHUNK_SIZE/2


        if glm.distance(main_camera.position, middle) < 512 && testAabb(proj_view, minC, maxC) {
            chunk_render(&chunk) 
        }
    } 
    
    imgui_opengl.RenderDrawData(imgui.GetDrawData())

    when !DISABLE_DOCKING {
        backup_current_window := sdl2.GL_GetCurrentWindow()
        backup_current_context := sdl2.GL_GetCurrentContext()
        imgui.UpdatePlatformWindows()
        imgui.RenderPlatformWindowsDefault()
        sdl2.GL_MakeCurrent(backup_current_window, backup_current_context);
    }


    sdl2.GL_SwapWindow(window)
}

render_chunks :: proc"c"(core : ^slate.core_interface){

}

quit :: proc"c"(status : int){
    core.log(.INFO, "shutting down renderer")

    context = render_context

    for pos, &chunk in chunk_map{
        gl.DeleteBuffers(1, &chunk.vbo)
        gl.DeleteVertexArrays(1, &chunk.vao)
    }
    delete(chunk_map)
    gl.DeleteBuffers(1, &quad_ebo)
    
    for key, value in test_shader_uniforms{
        delete(key)
    }
    delete(test_shader_uniforms)

    imgui_opengl.Shutdown()
    imgui_sdl2.Shutdown()
    imgui.DestroyContext()
    sdl2.GL_DeleteContext(gl_context)
    sdl2.DestroyWindow(window)
    sdl2.Quit()

    
    when ODIN_DEBUG{
        for _, leak in track.allocation_map {
            core.log(.DEBUG,"%v leaked %m\n", leak.location, leak.size)
        }
    }

}
