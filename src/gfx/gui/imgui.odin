package gui

import "core:log"

import sdl "vendor:sdl3"

import im "shared:odin-imgui"
import im_sdl "shared:odin-imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:odin-imgui/imgui_impl_sdlgpu3"

init :: proc(w: ^sdl.Window, gpu: ^sdl.GPUDevice) -> bool {
	im.CreateContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard}
	io.ConfigFlags += {.DockingEnable}

	style := im.GetStyle()
	style.WindowRounding = 4
	style.Colors[im.Col.WindowBg].w = 1

	im.StyleColorsDark()

	if !im_sdl.InitForSDLGPU(w) {
		log.fatal("Failed to init imgui for sdlgpu")
	}
	if !im_sdlgpu.Init(
		&{Device = gpu, ColorTargetFormat = sdl.GetGPUSwapchainTextureFormat(gpu, w)},
	) {
		log.fatal("Failed to init in sdlgpu")
	}

	return true
}

destroy :: proc() {
	im_sdl.Shutdown()
	im_sdlgpu.Shutdown()
	im.DestroyContext()
}

new_frame :: proc() {
	im_sdl.NewFrame()
	im_sdlgpu.NewFrame()
	im.NewFrame()
}

prep :: proc(cmd_buf: ^sdl.GPUCommandBuffer) -> ^im.DrawData {
	im.Render()
	im_draw_data := im.GetDrawData()
	if im_draw_data == nil do log.error("imgui draw data was nil")
	im_sdlgpu.PrepareDrawData(im_draw_data, cmd_buf)
	return im_draw_data

}

/// Does a whole pass
render :: proc(
	sw: ^sdl.GPUTexture,
	draw_data: ^im.DrawData,
	cmd_buf: ^sdl.GPUCommandBuffer,
	render_pass: ^sdl.GPURenderPass,
) {
	im_sdlgpu.RenderDrawData(draw_data, cmd_buf, render_pass)
}

