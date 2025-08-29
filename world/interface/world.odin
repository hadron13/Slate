package interface

block_id  :: u32
block_pos :: [3]i32
chunk_pos :: [3]i32

CHUNK_SIZE :: 32


version :: struct{
    major : u16,
    minor : u16,
    patch : u16
}

chunk :: struct{
    position : chunk_pos,
    blocks   : [CHUNK_SIZE][CHUNK_SIZE][CHUNK_SIZE]block_id,
}

world :: struct{
    seed   : i64,
    chunks : map[chunk_pos]chunk
}


world_interface :: struct{
    size : u64,
    version : version,
    world_get : proc"c"(name  : string) -> ^world,
    chunk_load: proc"c"(world : ^world, position : chunk_pos, callback : proc"c"(world : ^world, position : chunk_pos)),
    chunk_unload: proc"c"(world : ^world, position : chunk_pos),
    chunk_get : proc"c"(world : ^world, position : chunk_pos) -> ^chunk,
    block_set : proc"c"(world : ^world, position : block_pos) -> block_id,
    block_get : proc"c"(world : ^world, position : block_pos, id: block_id),
    on_chunk_load     : proc"c"(callback : proc"c"(world : ^world, position : chunk_pos)),
    on_chunk_modified : proc"c"(callback : proc"c"(world : ^world, position : chunk_pos)),
    on_chunk_unload   : proc"c"(callback : proc"c"(world : ^world, position : chunk_pos)),
}

chunk_to_block :: proc"c"(position : chunk_pos) -> block_pos{
    return auto_cast position * CHUNK_SIZE
}

block_to_chunk :: proc"c"(position : block_pos) -> chunk_pos{
    return auto_cast position / CHUNK_SIZE
}
