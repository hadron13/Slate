#+private
package world

import "core:strings"
import "core:c"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:sync"
import "core:math/noise"

MODULE :: #config(MOD, "World")
import "../slate"


import "interface"

block_id :: u32
block_pos :: distinct [3]i32
chunk_pos :: distinct [3]i32

CHUNK_SIZE :: interface.CHUNK_SIZE

chunk :: struct{
    position : chunk_pos,
    blocks   : [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]block_id,
}

world :: struct{
    seed   : i64,
    lock   : sync.Mutex,
    chunks : map[chunk_pos]^chunk
}


core : ^slate.core_interface
world_context : runtime.Context
test_world : world 

world_get :: proc"c"(name  : string) -> ^world{
    return &test_world
}

chunk_to_block :: proc"c"(position : chunk_pos) -> block_pos{
    return auto_cast position * CHUNK_SIZE
}
 
block_to_chunk :: proc"c"(position : block_pos) -> chunk_pos{
    return auto_cast position / CHUNK_SIZE
}



chunk_load :: proc"c"(world : ^world, position : chunk_pos, callback : proc"c"(^world, chunk_pos)){ 
    context = world_context
    
    string_builder := strings.builder_make()
            
    task_data := new(struct{pos: chunk_pos, callback : proc"c"(^world, chunk_pos)})
    task_data.pos = position
    task_data.callback = callback 
    
    core.task_add_once(fmt.aprintf("world/generate_chunk[%i,%i,%i]", position.x, position.y, position.z),
            "main", chunk_generator_task, task_data, nil)
     
    // generated_chunk := chunk_generate(test_world.seed, position)
    // sync.lock(&test_world.lock)
    // test_world.chunks[position] = generated_chunk
    // sync.unlock(&test_world.lock)
    
    // callback(world, position)
}

chunk_generator_task :: proc"c"(core : ^slate.core_interface, data : rawptr){
    context = world_context

    task_data := cast(^struct{pos: chunk_pos, callback : proc"c"(^world, chunk_pos)}) data
    // core.log(.DEBUG, "generating chunk [%i, %i, %i]", task_data.pos.x, task_data.pos.y, task_data.pos.z)  

    generated_chunk := chunk_generate(test_world.seed, task_data.pos)
    sync.lock(&test_world.lock)
    test_world.chunks[task_data.pos] = generated_chunk
    sync.unlock(&test_world.lock)

    task_data.callback(&test_world, task_data.pos)

    free(data)
}

chunk_get :: proc"c"(world : ^world, position : chunk_pos) -> ^chunk{
    context = world_context
    sync.guard(&world.lock)
    chunk, present := world.chunks[position]

    return present? chunk : nil
}

block_get :: proc"c"(world : ^world, position : block_pos) -> block_id{
    chunk := chunk_get(world, block_to_chunk(position))
    return chunk.blocks[position.x][position.y][position.z]
}

block_set :: proc"c"(world : ^world, position : block_pos, id: block_id){
    chunk := chunk_get(world, block_to_chunk(position))
    chunk.blocks[position.x][position.y][position.z] = id
}

world_interface : interface.world_interface

@export
load :: proc"c"(core_interface : ^slate.core_interface) -> slate.version{
    core = core_interface
    context = runtime.default_context()
    world_context = context

    world_interface = {
        size_of(interface.world_interface),
        {0, 0, 1},
        auto_cast world_get,
        auto_cast chunk_load,
        nil,
        auto_cast chunk_get,
        auto_cast block_get,
        auto_cast block_set 
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



compound_noise :: proc(seed: i64, octaves: i32, x, y : f64) -> f32{
    
    value : f32 = 0 
    frequency : f32 = 1

    for i :i32= 0; i < octaves;i += 1{
        frequency *= 2
        value += noise.noise_2d(seed, {x * f64(frequency) , y * f64(frequency)}) / frequency
    }

    return value
}

chunk_generate :: proc"c"(seed : i64, position : chunk_pos) -> ^chunk{

    context = runtime.default_context()

    block_position := chunk_to_block(position)
    chunk := new(chunk)
    for x :i32= 0; x < CHUNK_SIZE ; x+=1{
        for z :i32= 0; z < CHUNK_SIZE ; z+=1{

            world_x := x + block_position.x 
            world_z := z + block_position.z
            
            height := compound_noise(seed, 12, f64(world_x)/4096, f64(world_z)/4096)
            height = 1 - math.abs(height)
            height *= height
            height *= 128

            for y :i32= 0; y < CHUNK_SIZE ; y+=1{ 
                world_y := y + block_position.y
                if(world_y < i32(height)){
                    chunk.blocks[x][y][z] = (height < 24)?2:(height < 48)?3:1
                } 
            }
        }
    }
    return chunk
}


