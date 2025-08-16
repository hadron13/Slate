#+private
package world

import "core:strings"
import "core:c"
import "base:runtime"
import "core:math"
import "core:math/noise"

MODULE :: #config(MOD, "World")
import "../slate"


import "interface"

block_id :: u32
block_pos :: distinct [3]i32
chunk_pos :: distinct [3]i32

CHUNK_SIZE :: 16

chunk :: struct{
    position : chunk_pos,
    blocks   : [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]block_id,
}

world :: struct{
    seed   : i64,
    chunks : map[chunk_pos]chunk
}


core : ^slate.core_interface
test_world : world 

get_world :: proc"c"(name  : string) -> ^world{
    return &test_world
}

chunk_to_block :: proc"c"(position : chunk_pos) -> block_pos{
    return auto_cast position * CHUNK_SIZE
}

block_to_chunk :: proc"c"(position : block_pos) -> chunk_pos{
    return auto_cast position / CHUNK_SIZE
}


get_chunk :: proc"c"(world : ^world, position : chunk_pos) -> ^chunk{
    chunk, present := &world.chunks[position]
    if present do return chunk
    
    return nil
}

get_block :: proc"c"(world : ^world, position : block_pos) -> block_id{
    chunk := get_chunk(world, block_to_chunk(position))
    return chunk.blocks[position.x][position.y][position.z]
}

set_block :: proc"c"(world : ^world, position : block_pos, id: block_id){
    chunk := get_chunk(world, block_to_chunk(position))
    chunk.blocks[position.x][position.y][position.z] = id
}

world_interface : interface.world_interface

@export
load :: proc"c"(core_interface : ^slate.core_interface) -> slate.version{
    core = core_interface
    context = runtime.default_context()

    world_interface = {
        size_of(interface.world_interface),
        {0, 0, 1},
        auto_cast get_world,
        auto_cast get_chunk,
        auto_cast get_block,
        auto_cast set_block
    }

    core.task_add_once("world/generate", "main", generate, nil, nil)
    core.module_set_interface("world", auto_cast(&world_interface))
    return {0, 0, 1}
}

generate :: proc"c"(core : ^slate.core_interface, data : rawptr){
    test_world.seed = 1234
    
    for x :i32= -8; x < 8; x+=1{
        for z :i32= -8; z < 8; z+=1{
            test_world.chunks[{x, 0, z}] = chunk_generate(test_world.seed, {x, 0, z})
        }
    }
}

chunk_generate :: proc"c"(seed : i64, position : chunk_pos) -> chunk{

    context = runtime.default_context()

    chunk : chunk
    for x := 0; x < CHUNK_SIZE ; x+=1{
        for z := 0; z < CHUNK_SIZE ; z+=1{
            height := noise.noise_2d(seed, {f64(x+int(position.x)*CHUNK_SIZE)/16, f64(z+int(position.z)*CHUNK_SIZE)/16})
            for y := 0; y < CHUNK_SIZE ; y+=1{
                if(y < int(height * 3) + 4){
                    chunk.blocks[x][y][z] = (height  > 0.5)?1:2
                } 
            }
        }
    }
    return chunk
}


