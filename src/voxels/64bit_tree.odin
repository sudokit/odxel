package voxels

import "core:fmt"
import "core:math/bits"
import ln "core:math/linalg"
import "core:simd"

import "../utils"

Node64 :: struct #packed {
	using _:    bit_field u32 {
		is_leaf:   bool | 1,
		child_idx: u32  | 31,
	},
	child_mask: u64,
}

bit_tree64_construct :: proc(
	vmap: Voxel_Map,
	node_pool: ^[dynamic]Node64,
	leaf_data: ^[dynamic]u8,
	scale: i32, // log2 scale, even, >=2; leaf when ==2
	initial_pos: [3]i32, // voxel coord of corner (aligned to 1<<scale)
) -> (
	n: Node64 = {},
) {
	if scale == 2 {
		temp: [64]u8
		any := false
		for i in 0 ..< 64 {
			lx := (i32(i) >> 0) & 3
			ly := (i32(i) >> 4) & 3
			lz := (i32(i) >> 2) & 3

			p := initial_pos + {lx, ly, lz}
			temp[i] = vmap_get(vmap, p)
			if temp[i] != 0 do any = true
		}

		if !any {return n}

		n.is_leaf = true
		n.child_mask = utils.bits_pack64(temp)
		utils.bits_left_pack(&temp, n.child_mask)
		n.child_idx = cast(u32)len(leaf_data)
		append(leaf_data, ..temp[:simd.count_ones(n.child_mask)])
		return n
	}

	// i32ernal node
	child_scale := scale - 2
	children := make([dynamic]Node64); defer delete(children)

	for i in 0 ..< 64 {
		cx := (i32(i) >> 0) & 3
		cy := (i32(i) >> 4) & 3
		cz := (i32(i) >> 2) & 3

		child_offset := [3]i32 {
			cx << cast(u32)child_scale,
			cy << cast(u32)child_scale,
			cz << cast(u32)child_scale,
		}

		child := bit_tree64_construct(
			vmap,
			node_pool,
			leaf_data,
			child_scale,
			initial_pos + child_offset,
		)

		if child.child_mask != 0 {
			n.child_mask |= u64(1) << u64(i)
			n.is_leaf = false
			append(&children, child)
		}
	}

	n.child_idx = cast(u32)len(node_pool)
	append(node_pool, ..children[:])
	return n
}

