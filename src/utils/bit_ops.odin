package utils

import "base:intrinsics"

import "core:simd"
import "core:slice"

bits_pack64 :: proc(arr: [64]u8) -> u64 {
	return transmute(u64)simd.extract_msbs(simd.lanes_ne(simd.from_array(arr), simd.u8x64(0)))
}

bits_left_pack :: proc(res: ^[64]u8, mask: u64) {
	load_mask := transmute(bit_set[0 ..< 64])mask
	simd_mask: [64]u8
	for b in load_mask do simd_mask[b] = 0xFF

	rs: [64]u8
	simd.masked_compress_store(&rs, simd.from_array(res^), simd.from_array(simd_mask))
	res^ = rs
}

bits_popcnt_var64 :: proc(mask: u64, width: u32) -> u32 {
	// return cast(u32)simd.count_ones(mask & ((u64(1) << width) - 1))
	himask := u32(mask)
	count := u32(0)

	if width >= 32 {
		count = simd.count_ones(himask)
		himask = u32(mask >> 32)
	}
	m := u32(1) << (width & u32(31))
	count += simd.count_ones(himask & (m - u32(1)))

	return count
}

bits_test_half64 :: proc(value: u64, shift, mask: u32) -> bool {
	low := shift < 32 ? u32(value) : u32(value >> 32)
	return cast(bool)((low >> (shift & 31) & mask) != 0)
}

