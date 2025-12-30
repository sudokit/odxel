package gfx

import sdl "vendor:sdl3"

// acquire_cmd_buf :: proc(r: Renderer) -> (^sdl.GPUCommandBuffer, bool) {
// 	cmd_buf := sdl.AcquireGPUCommandBuffer(r.gpu)
// 	return cmd_buf, cmd_buf != nil
// }

// submit_cmd_buf :: proc(cmd_buf: ^sdl.GPUCommandBuffer) -> bool {
// 	sdl.SubmitGPUCommandBuffer(cmd_buf) or_return
// 	return true
// }

// acquire_swapchain_texture :: proc(
// 	r: Renderer,
// 	cmd_buf: ^sdl.GPUCommandBuffer,
// ) -> (
// 	tex: ^sdl.GPUTexture,
// 	ok: bool,
// ) {
// ok = sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, r.win, &tex, nil, nil)
// 	return tex, ok && tex != nil
// }

