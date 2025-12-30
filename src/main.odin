package main

import "core:fmt"
import "core:log"
import "core:math"
import ln "core:math/linalg"
import "core:time"

import sdl "vendor:sdl3"

import im "shared:odin-imgui"
import im_sdl "shared:odin-imgui/imgui_impl_sdl3"

import "./gfx"
import "./gfx/gui"
import "./gfx/ops"
import "./gfx/shaders"
import "./settings"
import "./ui"
import "./utils"
import "./voxels"

W_WIDTH :: 1280
W_HEIGHT :: 720

st: struct {
	renderer: gfx.Renderer,
	settings: settings.Settings,
	ui:       ui.UI,
}

run :: proc() -> bool {
	ops.window_init("leijjuva", {W_WIDTH, W_HEIGHT}) or_return; defer ops.window_destroy()

	st.renderer = gfx.renderer_create(
		ops.get_window(),
	) or_return; defer gfx.renderer_destroy(&st.renderer)

	gui.init(ops.get_window(), st.renderer.gpu) or_return; defer gui.destroy()

	// clear_color: [3]f32 = {0, 0.2, 0.4}

	vrt := shaders.compile_from_file(
		"./shaders/64bit_traverse.slang",
		.Compute,
		"ComputeMain",
	) or_return; defer shaders.shader_destroy(&vrt, st.renderer.gpu)
	vrt_comp := shaders.shader_compute_pipeline(
		&vrt,
		st.renderer.gpu,
		{thread_count = {8, 8, 1}, readwrite_storage_textures = 1, uniform_buffers = 1},
	) or_return

	uniform_data: struct {
		inv_proj_mat: ln.Matrix4f32,
		cam_pos:      [3]f32,
	} = {
		inv_proj_mat = ln.MATRIX4F32_IDENTITY,
		cam_pos      = 0.5,
	}

	start := time.tick_now()
	loop: for {
		ds := utils.ds_update(start, 30)
		start = time.tick_now()

		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			im_sdl.ProcessEvent(&ev)

			#partial switch ev.type {
			case .QUIT:
				break loop
			case .KEY_DOWN:
				if ev.key.scancode == .ESCAPE do break loop
			}
		}

		if st.ui.resized {
			gfx.renderer_resize(&st.renderer, st.ui.vp_size)
		}

		frame := gfx.frame_begin(&st.renderer) or_return

		// // clear texture to draw to white
		// color_target := sdl.GPUColorTargetInfo {
		// 	texture              = st.renderer.present.tex,
		// 	load_op              = .CLEAR,
		// 	store_op             = .STORE,
		// 	mip_level            = 0,
		// 	layer_or_depth_plane = 0,
		// 	cycle                = true,
		// 	clear_color          = {clear_color.r, clear_color.g, clear_color.b, 1},
		// }
		// // offscreen_clear_pass := gfx.frame_begin_render_pass(frame, &color_target)
		// offscreen_clear_pass := sdl.BeginGPURenderPass(frame.cmd_buf, &color_target, 1, nil)
		// sdl.EndGPURenderPass(offscreen_clear_pass)


		// begin compute pass and raytrace voxels to texture which gets passed to ui_draw
		render_tex_binding := sdl.GPUStorageTextureReadWriteBinding {
			texture = st.renderer.present.tex,
			cycle   = true,
		}
		comp_pass := sdl.BeginGPUComputePass(frame.cmd_buf, &render_tex_binding, 1, nil, 0)
		sdl.BindGPUComputePipeline(comp_pass, vrt_comp)
		sdl.PushGPUComputeUniformData(frame.cmd_buf, 0, &uniform_data, size_of(uniform_data))
		sdl.DispatchGPUCompute(
			comp_pass,
			cast(u32)(math.ceil(f32(st.ui.vp_size.x) / 8)),
			cast(u32)(math.ceil(f32(st.ui.vp_size.y) / 8)),
			1,
		)
		sdl.EndGPUComputePass(comp_pass)
		/*
			// Describe the writeable texture(s)
			SDL_GPUStorageTextureReadWriteBinding writeBinding = {0};
			writeBinding.texture = offscreenTexture;
			writeBinding.mip_level = 0;
			writeBinding.layer = 0;  // or depth plane
			writeBinding.cycle = true;  // Recommended if reusing every frame

			SDL_GPUComputePass *computePass = SDL_BeginGPUComputePass(
			    cmd,
			    &writeBinding,      // array of write bindings
			    1,                  // num bindings
			    NULL, 0             // optional readonly storage buffers if any
			);

			// Bind pipeline and any readonly resources
			SDL_BindGPUComputePipeline(computePass, computePipeline);

			// Bind readonly samplers if your compute shader reads from other textures
			// SDL_BindGPUComputeSamplers(computePass, ...);

			// Bind readonly storage textures/buffers if needed
			// SDL_BindGPUComputeStorageTextures(computePass, ...);  // for READ_BIT

			// Optional: push uniforms
			// SDL_PushGPUComputeUniformData(computePass, slot, data, size);

			// Dispatch
			SDL_DispatchGPUCompute(computePass, width / workgroupX, height / workgroupY, 1);

			SDL_EndGPUComputePass(computePass);
		*/


		gui.new_frame()
		ui.ui_draw(
			&st.ui,
			{window = ops.get_window(), sampler_binding = &st.renderer.present.binding},
			ds,
			&st.settings,
		)
		// im.Begin("Test")
		// im.ColorEdit3("Clear background", &clear_color)
		// im.End()

		draw_data := gui.prep(frame.cmd_buf)
		present_pass := gfx.frame_begin_present_pass(frame)
		gui.render(frame.sw_tex, draw_data, frame.cmd_buf, present_pass)
		gfx.frame_end_present_pass(frame, present_pass)

		gfx.frame_end(&st.renderer)

		utils.throttle(start, st.settings.vsync ? 0 : 500) // do suff here
	}

	return true

}

main :: proc() {
	context.logger = log.create_console_logger()
	if !run() do return
}

