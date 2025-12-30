package gfx

import "core:log"

import sdl "vendor:sdl3"

import "./ops"

Renderer :: struct {
	win:     ^sdl.Window,
	gpu:     ^sdl.GPUDevice,

	// per frame stuff
	_frame:  Frame,
	// render texture
	present: struct {
		tex:         ^sdl.GPUTexture,
		tex_sampler: ^sdl.GPUSampler,
		binding:     sdl.GPUTextureSamplerBinding,
	},
}

renderer_create :: proc(win: ^sdl.Window) -> (r: Renderer = {}, ok: bool) {
	r.win = win
	// device
	r.gpu = sdl.CreateGPUDevice({.SPIRV}, ODIN_DEBUG, nil)
	if r.gpu == nil {
		log.fatal("Failed to create a gpu device")
		return {}, false
	}
	ops.window_claim_for_gpu(r.gpu)

	x, y: i32
	sdl.GetWindowSize(win, &x, &y)
	// render texture
	r.present.tex = sdl.CreateGPUTexture(
		r.gpu,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER, .COMPUTE_STORAGE_WRITE, .COLOR_TARGET},
			layer_count_or_depth = 1,
			num_levels = 1,
			width = u32(x),
			height = u32(y),
			sample_count = ._1,
		},
	)
	if r.present.tex == nil {
		log.fatal("Failed to create a present texture")
		return {}, false
	}

	// sampler
	r.present.tex_sampler = sdl.CreateGPUSampler(
		r.gpu,
		{
			mag_filter = .NEAREST,
			min_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
			mip_lod_bias = 0.0,
			max_anisotropy = 1.0,
			compare_op = .NEVER,
			enable_anisotropy = false,
			enable_compare = false,
		},
	)
	if r.present.tex_sampler == nil {
		log.fatal("Failed to create a present texture sampler")
		return {}, false
	}

	r.present.binding = {
		texture = r.present.tex,
		sampler = r.present.tex_sampler,
	}

	return r, true
}

renderer_destroy :: proc(r: ^Renderer) {
	if r.present.tex != nil do sdl.ReleaseGPUTexture(r.gpu, r.present.tex)
	sdl.ReleaseGPUSampler(r.gpu, r.present.tex_sampler)
	sdl.DestroyGPUDevice(r.gpu)
}

renderer_resize :: proc(r: ^Renderer, new_size: [2]u32) {
	log.debugf("Renderer resized: %v", new_size)
	if r.present.tex != nil do sdl.ReleaseGPUTexture(r.gpu, r.present.tex)
	r.present.tex = sdl.CreateGPUTexture(
		r.gpu,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER, .COMPUTE_STORAGE_WRITE, .COLOR_TARGET},
			layer_count_or_depth = 1,
			num_levels = 1,
			width = new_size.x,
			height = new_size.y,
			sample_count = ._1,
		},
	)
	r.present.binding.texture = r.present.tex
}

