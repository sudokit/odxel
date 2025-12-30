package utils

import ln "core:math/linalg"

ray_get_primary_dir :: proc(
	screen_pos: [2]i32,
	size: [2]i32,
	inv_view_proj_mat: ln.Matrix4f32,
	origin: [3]f32,
) -> (
	ray_pos, ray_dir: [3]f32,
) {
	ndc_x := 2.0 * (f32(screen_pos.x) + 0.5) / f32(size.x) - 1.0
	ndc_y := 1.0 - 2.0 * (f32(screen_pos.y) + 0.5) / f32(size.y)

	clip_near := [4]f32{ndc_x, ndc_y, -1.0, 1.0}

	world_hom := clip_near * inv_view_proj_mat
	world_near := world_hom.xyz / world_hom.w

	return origin, ln.normalize(world_near - origin)
}

// ray_intersect_aabb :: proc(origin, inv_dir, bb_min, bb_max: [3]f32) -> (f32, f32) {
// 	t0 := (bb_min - origin) * inv_dir
// 	t1 := (bb_max - origin) * inv_dir

// 	temp := t0
// 	t0 = ln.min(temp, t1); t1 = ln.max(temp, t1)

// 	tmin := max(max(t0.x, t0.y), t0.z)
// 	tmax := min(min(t1.x, t1.y), t1.z)

// 	// return [2]f32{tmin, tmax}
// 	return tmin, tmax
// }

