package gfx

import "core:fmt"

import sdl "vendor:sdl3"

Frame :: struct {
	sw_tex:       ^sdl.GPUTexture,
	cmd_buf:      ^sdl.GPUCommandBuffer,
	color_target: sdl.GPUColorTargetInfo,
	in_progress:  bool,
}

frame_begin :: proc(r: ^Renderer) -> (^Frame, bool) {
	if r._frame.in_progress do return {}, false // already started

	ok: bool
	// acquire cmd buf
	r._frame.cmd_buf = sdl.AcquireGPUCommandBuffer(r.gpu)
	ok = r._frame.cmd_buf != nil

	// acquire swapchain tex
	ok = sdl.WaitAndAcquireGPUSwapchainTexture(r._frame.cmd_buf, r.win, &r._frame.sw_tex, nil, nil)

	r._frame.in_progress = true
	return ok ? &r._frame : nil, ok
}

frame_end :: proc(r: ^Renderer) -> bool {
	if !r._frame.in_progress do return false // never started
	defer {
		r._frame.sw_tex = nil
		r._frame.cmd_buf = nil
		r._frame.in_progress = false
	}

	// submit command buffer
	sdl.SubmitGPUCommandBuffer(r._frame.cmd_buf) or_return
	return true
}

// display pass
frame_begin_present_pass :: proc(
	frame: ^Frame,
	clear_color: sdl.FColor = 0,
) -> ^sdl.GPURenderPass {
	if !frame.in_progress do return nil
	present_target := sdl.GPUColorTargetInfo {
		texture     = frame.sw_tex,
		load_op     = .CLEAR,
		store_op    = .STORE,
		cycle       = true,
		clear_color = clear_color,
	}

	return sdl.BeginGPURenderPass(frame.cmd_buf, &present_target, 1, nil)
}

frame_end_present_pass :: proc(frame: ^Frame, pass: ^sdl.GPURenderPass) {
	if !frame.in_progress || pass == nil do return
	sdl.EndGPURenderPass(pass)
}

// render pass
frame_begin_render_pass :: proc(
	frame: ^Frame,
	color_target_info: ^sdl.GPUColorTargetInfo,
) -> ^sdl.GPURenderPass {
	return sdl.BeginGPURenderPass(frame.cmd_buf, color_target_info, 1, nil)
}

// compute pass

