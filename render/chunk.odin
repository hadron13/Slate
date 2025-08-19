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

chunk_map : map[[3]i32]chunk
quad_ebo : u32

chunk_create :: proc(position : [3]i32) { 
    world_chunk := world.get_chunk(world.get_world(""), position)
    if world_chunk == nil{
        return
    }

    chunk_map[position] = {}

    chunk := &chunk_map[position]

    chunk.offset = position
    chunk.transform = glm.mat4Translate(linalg.to_f32(position * CHUNK_SIZE))

 
    vertices:= chunk_mesh(&(world_chunk.blocks))


    gl.GenVertexArrays(1, &chunk.vao)
    gl.GenBuffers(1, &chunk.vbo)
    
    gl.BindVertexArray(chunk.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, chunk.vbo);
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(f32), raw_data(vertices), gl.STATIC_DRAW)

    if(quad_ebo == 0){
        indices  := make([dynamic]u32, 0, 98304)
        for i :u32= 0; i < 98304; i += 4{
            append(&indices, i, i+1, i+2, i+2, i+1, i+3)
        }
        gl.GenBuffers(1, &quad_ebo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad_ebo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)
    }


    
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 0)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 6 * size_of(f32), 3 * size_of(f32))
    gl.EnableVertexAttribArray(1)

    gl.BindVertexArray(0)

}


//vertex format: XYZ - UV
append_quad :: #force_inline proc(vertices : ^[dynamic]f32, a, b, c, d : [6]f32){
    
    append(vertices, a[0], a[1], a[2], a[3], a[4], a[5])
    append(vertices, b[0] + a[0], b[1] + a[1], b[2] + a[2], b[3], b[4], b[5])
    append(vertices, c[0] + a[0], c[1] + a[1], c[2] + a[2], c[3], c[4], c[5])
    append(vertices, d[0] + a[0], d[1] + a[1], d[2] + a[2], d[3], d[4], d[5])
    
    // append(indices, last_vert, last_vert+1, last_vert+2, last_vert+2, last_vert+1, last_vert+3)
}

CHUNK_SIZE :: 16

chunk_mesh :: proc(blocks: ^[CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]u32) -> []f32{
    vertices := make([dynamic]f32, 0, 2048 * 3)

    for x := 0; x < CHUNK_SIZE ; x+=1{
        for y := 0; y < CHUNK_SIZE ; y+=1{
            for z := 0; z < CHUNK_SIZE ; z+=1{ 
                if blocks[x][y][z] == 0 do continue 

                tex_id := cast(f32)blocks[x][y][z] -1

                if x == 0 || blocks[x-1][y][z] == 0{
                                          //  X       Y       Z     U  V 
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 0, 0, tex_id}, {0, 1, 0, 0, 1, tex_id}, {0, 0, 1, 1, 0, tex_id}, {0, 1, 1, 1, 1, tex_id})
                }
                if y == 0 || blocks[x][y-1][z] == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 0, 0, tex_id}, {0, 0, 1, 0, 1, tex_id}, {1, 0, 0, 1, 0, tex_id}, {1, 0, 1, 1, 1, tex_id})
                }
                if z == 0 || blocks[x][y][z-1] == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z), 1, 0, tex_id}, {1, 0, 0, 0, 0, tex_id}, {0, 1, 0, 1, 1, tex_id}, {1, 1, 0, 0, 1, tex_id})
                }

                if x == CHUNK_SIZE-1 || blocks[x+1][y][z] == 0{
                    append_quad(&vertices, {f32(x)+1, f32(y), f32(z), 1, 0, tex_id}, {0, 0, 1, 0, 0, tex_id}, {0, 1, 0, 1, 1, tex_id}, {0, 1, 1, 0, 1, tex_id})
                }
                if y == CHUNK_SIZE-1 || blocks[x][y+1][z] == 0{
                    append_quad(&vertices, {f32(x), f32(y)+1, f32(z), 0, 0, tex_id}, {1, 0, 0, 0, 1, tex_id}, {0, 0, 1, 1, 0, tex_id}, {1, 0, 1, 1, 1, tex_id})
                }
                if z == CHUNK_SIZE-1 || blocks[x][y][z+1] == 0{
                    append_quad(&vertices, {f32(x), f32(y), f32(z)+1, 0, 0, tex_id}, {0, 1, 0, 0, 1, tex_id}, {1, 0, 0, 1, 0, tex_id}, {1, 1, 0, 1, 1, tex_id})
                }
            }
        }
    }
    
    return vertices[:]
}

chunk_render:: proc"c"(chunk : ^chunk){
    // core.log(.DEBUG, "VAO: %i, %i, %i, %i", chunk.vao, chunk.offset.x, chunk.offset.y, chunk.offset.z)
    model := glm.mat4Translate({f32(chunk.offset.x*CHUNK_SIZE), f32(chunk.offset.y*CHUNK_SIZE), f32(chunk.offset.z*CHUNK_SIZE)})
    gl.UniformMatrix4fv(test_shader_uniforms["model"].location, 1, gl.FALSE, &model[0,0])

    gl.BindVertexArray(chunk.vao)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, quad_ebo)
    gl.DrawElements(gl.TRIANGLES, 98304, gl.UNSIGNED_INT, nil)

}





