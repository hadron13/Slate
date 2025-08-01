package interface

block_id  :: u32
block_pos :: [3]i32
chunk_pos :: [3]i32

CHUNK_SIZE :: 16


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
    get_world : proc"c"(name  : string) -> ^world,
    get_chunk : proc"c"(world : ^world, position : chunk_pos) -> ^chunk,
    get_block : proc"c"(world : ^world, position : block_pos) -> block_id,
    set_block : proc"c"(world : ^world, position : block_pos, id: block_id),
}
