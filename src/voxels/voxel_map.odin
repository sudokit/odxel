package voxels

import ln "core:math/linalg"

Voxel_Map :: struct {
	width, height, depth: i32,
	// voxels:               []u8, // 0 = empty, 0< = filled
	voxels:               map[u32]u8,
}

voxel_map_create :: proc(dims: [3]i32) -> (vmap: Voxel_Map) {
	// vmap.voxels = make([]u8, dims.x * dims.y * dims.z)
	vmap.voxels = make(map[u32]u8)
	vmap.width = dims.x; vmap.height = dims.y; vmap.depth = dims.z
	return vmap
}

voxel_map_destroy :: proc(vmap: ^Voxel_Map) {
	delete(vmap.voxels)
}

@(private = "file")
_hash :: proc(pos: [3]i32) -> u32 {
	return cast(u32)(pos.x * 73856093 ~ pos.y * 19349669 ~ pos.z * 83492791)
}

vmap_get :: proc(vmap: Voxel_Map, pos: [3]i32) -> u8 {
	p := ln.array_cast(pos, i32)
	if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= vmap.width || p.y >= vmap.height || p.z >= vmap.depth) do return 0
	// idx := p.x + p.y * vmap.width + p.z * vmap.width * vmap.height
	// if idx >= cast(i32)len(vmap.voxels) do return 0
	voxel, ok := vmap.voxels[_hash(pos)]
	return ok ? voxel : 0
}

vmap_set :: proc(vmap: ^Voxel_Map, pos: [3]i32, data: u8) {
	p := ln.array_cast(pos, i32)
	if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= vmap.width || p.y >= vmap.height || p.z >= vmap.depth) do return
	// idx := p.x + p.y * vmap.width + p.z * vmap.width * vmap.height
	// if idx >= cast(i32)len(vmap.voxels) do return
	vmap.voxels[_hash(pos)] = data
}

