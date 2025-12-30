package ui

import "core:fmt"
import ln "core:math/linalg"

import sdl "vendor:sdl3"

import im "shared:odin-imgui"
import im_sdlgpu "shared:odin-imgui/imgui_impl_sdlgpu3"

import "../gfx/ops"
import "../settings"
import "../utils"

UI :: struct {
	vp_size:   [2]u32,
	_old_size: [2]u32,
	resized:   bool,
}

ui_draw :: proc(ui: ^UI, data: struct {
		window:          ^sdl.Window,
		sampler_binding: ^sdl.GPUTextureSamplerBinding,
	}, ds: utils.Debug_Stats, settings: ^settings.Settings) {
	ui.resized = false

	dockspace_id := im.GetID("DockSpaceHost")
	vp := im.GetMainViewport()

	// build docking layout
	if im.DockBuilderGetNode(dockspace_id) == nil {
		im.DockBuilderAddNode(dockspace_id, {.NoUndocking})
		im.DockBuilderSetNodeSize(dockspace_id, vp.Size)

		dock_id_left := u32(0)
		dock_id_main := u32(dockspace_id)
		im.DockBuilderSplitNode(dock_id_main, .Left, 0.2, &dock_id_left, &dock_id_main)

		im.DockBuilderDockWindow("Viewport", dock_id_main)
		im.DockBuilderDockWindow("Settings", dock_id_left)

		im.DockBuilderFinish(dockspace_id)
	}
	im.DockSpaceOverViewport(dockspace_id, vp, {.PassthruCentralNode})


	window_class: im.WindowClass
	window_class.DockNodeFlagsOverrideSet = {.AutoHideTabBar}
	im.SetNextWindowClass(&window_class)
	{
		im.Begin("Settings")
		im.Separator()
		if im.Checkbox("V-Sync", &settings.vsync) {
			sdl.SetWindowSurfaceVSync(data.window, cast(i32)settings.vsync)
		}
		im.End()
	}

	{
		im.PushStyleVarImVec2(.WindowPadding, 0)
		im.Begin("Viewport")
		vp_size := im.GetContentRegionAvail()
		uvp_size := ln.array_cast(vp_size, u32)
		if uvp_size != ui._old_size {
			ui._old_size = uvp_size
			ui.vp_size = uvp_size
			ui.resized = true
		}
		im.Image(im_sdlgpu.texture_id(data.sampler_binding), vp_size)
		im.End()
		im.PopStyleVar(1)
	}

	if (im.BeginMainMenuBar()) {
		im.Text("fps: %.2f / dt: %.4f", ds.avg_fps, ds.avg_dt)
		im.EndMainMenuBar()
	}
}

