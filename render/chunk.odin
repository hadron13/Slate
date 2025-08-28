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
import "core:math/linalg"
import stb "vendor:stb/image"

import world_interface "../world/interface"
import "../slate"

chunk:: struct{
    vao, vbo  : u32,
    offset    : [3]i32,
    transform : glm.mat4,    
}

direction :: enum{
    NORTH,
    SOUTH,
    UP,
    DOWN,
    EAST,
    WEST
}


chunk_map : map[[3]i32]chunk
quad_ebo : u32


CHUNK_SIZE :: world_interface.CHUNK_SIZE

//vertex format: XYZ - UV - ID - AO
append_quad :: #force_inline proc(vertices : ^[dynamic]f32, a, b, c, d : [7]f32){ 
    append(vertices, a[0], a[1], a[2], a[3], a[4], a[5], a[6])
    append(vertices, b[0] + a[0], b[1] + a[1], b[2] + a[2], b[3], b[4], b[5], b[6])
    append(vertices, c[0] + a[0], c[1] + a[1], c[2] + a[2], c[3], c[4], c[5], c[6])
    append(vertices, d[0] + a[0], d[1] + a[1], d[2] + a[2], d[3], d[4], d[5], d[6])    
}

chunk_update_task :: proc"c"(core : ^slate.core_interface, data : rawptr){ 
    context = render_context
    task_data := cast(^struct{world : ^world_interface.world, pos: [3]i32, vertices: []f32}) data
    
    // core.log(.DEBUG, "meshing chunk [%i, %i, %i]", task_data.pos.x, task_data.pos.y, task_data.pos.z)
    chunk_send_data(task_data.world, task_data.pos, task_data.vertices)
    
    free(task_data)
}



ambient_occlusion :: proc"c"(pos, side1, side2, corner : [3]i32, chunks : [3][3][3]^world_interface.chunk) -> f32{
   
    side1_pos := pos + side1
    side2_pos := pos + side2
    corner_pos := pos + corner

    has_side1 := block_at(side1_pos, chunks) != 0
    has_side2 := block_at(side2_pos, chunks) != 0
    has_corner := block_at(corner_pos, chunks) != 0
    if(has_side1 && has_side2){
        return 0.25
    }

    return ((has_side1?1.0:0.0) + (has_side2?1.0:0.0) + (has_corner?1.0:0.0))/6.0
}

block_at :: #force_inline proc"contextless"(pos : [3]i32, chunks : [3][3][3]^world_interface.chunk) -> world_interface.block_id{
    #no_bounds_check{
        chunk_pos := (pos + CHUNK_SIZE)/CHUNK_SIZE
        block_pos := (pos + CHUNK_SIZE)%CHUNK_SIZE
        return chunks[chunk_pos.x][chunk_pos.y][chunk_pos.z].blocks[block_pos.x][block_pos.y][block_pos.z]
    }
}

empty_chunk : world_interface.chunk

chunk_mesh :: proc"c"(current_world : ^world_interface.world, position : [3]i32) -> []f32{ 
    context = render_context

    chunks : [3][3][3]^world_interface.chunk

    chunks[1][1][1] = world.chunk_get(current_world, position)
    if chunks[1][1][1] == nil{
        return nil
    }

    for x :i32= 0; x < 3; x+=1{ 
        for y :i32= 0; y < 3; y+=1{    
            for z :i32= 0; z < 3; z+=1{
                chunks[x][y][z] = world.chunk_get(current_world, {position.x+x-1, position.y+y-1, position.z+z-1})
                if(chunks[x][y][z] == nil){
                    chunks[x][y][z] = &empty_chunk
                }
            }
        }
    }

    vertices := make([dynamic]f32, 0, 2048 * 3)
    blocks := &(chunks[1][1][1].blocks)

    for x :i32= 0; x < CHUNK_SIZE ; x+=1{
        for y :i32= 0; y < CHUNK_SIZE ; y+=1{
            for z :i32= 0; z < CHUNK_SIZE ; z+=1{ 
                if blocks[x][y][z] == 0 do continue 

                tex_id := cast(f32)blocks[x][y][z] -1

                if block_at({x-1, y, z}, chunks) == 0{
                                          //X  Y  Z                 U  V    ID    ambient occlusion
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 0, 0, tex_id, ambient_occlusion({x,y,z}, {-1,-1,0}, {-1,0,-1}, {-1,-1,-1}, chunks)}, 
                                           {0, 1, 0,                0, 1, tex_id, ambient_occlusion({x,y,z}, {-1, 1,0}, {-1,0,-1}, {-1, 1,-1}, chunks)},
                                           {0, 0, 1,                1, 0, tex_id, ambient_occlusion({x,y,z}, {-1,-1,0}, {-1,0, 1}, {-1,-1, 1}, chunks)},
                                           {0, 1, 1,                1, 1, tex_id, ambient_occlusion({x,y,z}, {-1, 1,0}, {-1,0, 1}, {-1, 1, 1}, chunks)})
                }
                if block_at({x, y-1, z}, chunks) == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 0, 0, tex_id, ambient_occlusion({x,y,z}, {-1,-1, 0}, {0,-1,-1}, {-1,-1,-1}, chunks)},
                                           {0, 0, 1,                0, 1, tex_id, ambient_occlusion({x,y,z}, { 0,-1, 1}, {-1,-1,0}, {-1,-1, 1}, chunks)}, 
                                           {1, 0, 0,                1, 0, tex_id, ambient_occlusion({x,y,z}, { 1,-1, 0}, {0,-1,-1}, { 1,-1,-1}, chunks)}, 
                                           {1, 0, 1,                1, 1, tex_id, ambient_occlusion({x,y,z}, { 1,-1, 0}, {0,-1, 1}, { 1,-1, 1}, chunks)})
                }
                if block_at({x, y, z-1}, chunks) == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 1, 0, tex_id, ambient_occlusion({x,y,z}, {-1, 0,-1}, {0,-1,-1}, {-1,-1,-1}, chunks)}, 
                                           {1, 0, 0,                0, 0, tex_id, ambient_occlusion({x,y,z}, { 1, 0,-1}, {0,-1,-1}, { 1,-1,-1}, chunks)}, 
                                           {0, 1, 0,                1, 1, tex_id, ambient_occlusion({x,y,z}, { 0, 1,-1}, {-1,0,-1}, {-1, 1,-1}, chunks)}, 
                                           {1, 1, 0,                0, 1, tex_id, ambient_occlusion({x,y,z}, { 1, 0,-1}, {0, 1,-1}, { 1, 1,-1}, chunks)})
                }

                if block_at({x+1, y, z}, chunks) == 0{
                    append_quad(&vertices, {f32(x)+1, f32(y), f32(z), 1, 0, tex_id, ambient_occlusion({x,y,z}, {1,-1,0}, {1,0,-1}, {1,-1,-1}, chunks)},
                                           {0, 0, 1,                  0, 0, tex_id, ambient_occlusion({x,y,z}, {1,-1,0}, {1,0, 1}, {1,-1, 1}, chunks)}, 
                                           {0, 1, 0,                  1, 1, tex_id, ambient_occlusion({x,y,z}, {1, 1,0}, {1,0,-1}, {1, 1,-1}, chunks)}, 
                                           {0, 1, 1,                  0, 1, tex_id, ambient_occlusion({x,y,z}, {1, 1,0}, {1,0, 1}, {1, 1, 1}, chunks)})
                }
                if block_at({x, y+1, z}, chunks) == 0{
                    append_quad(&vertices, {f32(x), f32(y)+1, f32(z), 0, 0, tex_id, ambient_occlusion({x,y,z}, {-1,1, 0}, {0,1,-1}, {-1,1,-1}, chunks)},
                                           {1, 0, 0,                  0, 1, tex_id, ambient_occlusion({x,y,z}, { 1,1, 0}, {0,1,-1}, { 1,1,-1}, chunks)}, 
                                           {0, 0, 1,                  1, 0, tex_id, ambient_occlusion({x,y,z}, {-1,1, 0}, {0,1, 1}, {-1,1, 1}, chunks)}, 
                                           {1, 0, 1,                  1, 1, tex_id, ambient_occlusion({x,y,z}, { 1,1, 0}, {0,1, 1}, { 1,1, 1}, chunks)})
                }
                if block_at({x, y, z+1}, chunks) == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z)+1, 0, 0, tex_id, ambient_occlusion({x,y,z}, {-1, 0,1}, {0,-1,1}, {-1,-1,1}, chunks)},
                                           {0, 1, 0,                  0, 1, tex_id, ambient_occlusion({x,y,z}, {-1, 0,1}, {0, 1,1}, {-1, 1,1}, chunks)}, 
                                           {1, 0, 0,                  1, 0, tex_id, ambient_occlusion({x,y,z}, { 1, 0,1}, {0,-1,1}, { 1,-1,1}, chunks)}, 
                                           {1, 1, 0,                  1, 1, tex_id, ambient_occlusion({x,y,z}, { 1, 0,1}, {0, 1,1}, { 1, 1,1}, chunks)})
                }
            }
        }
    }

    return vertices[:]
}

chunk_send_data :: proc"c"(current_world : ^world_interface.world, position : [3]i32, vertices : []f32){
    context = render_context
    chunk_map[position] = {}

    chunk := &chunk_map[position]

    chunk.offset = position
    chunk.transform = glm.mat4Translate(linalg.to_f32(position * CHUNK_SIZE))
    
    gl.GenVertexArrays(1, &chunk.vao)
    gl.GenBuffers(1, &chunk.vbo)
    
    gl.BindVertexArray(chunk.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, chunk.vbo);
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(f32), raw_data(vertices), gl.STATIC_DRAW)
    
    delete(vertices)

    if(quad_ebo == 0){
        EBO_SIZE :: CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE * 6 * 6
        indices  := make([dynamic]u32, 0, EBO_SIZE)
        for i :u32= 0; i < EBO_SIZE; i += 4{
            append(&indices, i, i+1, i+2, i+2, i+1, i+3)
        }
        gl.GenBuffers(1, &quad_ebo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad_ebo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

        delete(indices)
    }
    
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 7 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 7 * size_of(f32), 3 * size_of(f32))
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(2, 1, gl.FLOAT, gl.FALSE, 7 * size_of(f32), 6 * size_of(f32))
    gl.EnableVertexAttribArray(2)

    gl.BindVertexArray(0)
}



chunk_render:: proc"c"(chunk : ^chunk){
    // core.log(.DEBUG, "VAO: %i, %i, %i, %i", chunk.vao, chunk.offset.x, chunk.offset.y, chunk.offset.z)
    model := glm.mat4Translate({f32(chunk.offset.x*CHUNK_SIZE), f32(chunk.offset.y*CHUNK_SIZE), f32(chunk.offset.z*CHUNK_SIZE)})
    gl.UniformMatrix4fv(test_shader_uniforms["model"].location, 1, gl.FALSE, &model[0,0])

    gl.BindVertexArray(chunk.vao)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad_ebo)
    gl.DrawElements(gl.TRIANGLES, 98304, gl.UNSIGNED_INT, nil)

}





