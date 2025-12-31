package main

import "core:fmt"
import "core:log"
import "core:math"
import ln "core:math/linalg"
import "core:math/noise"
import "core:math/rand"
import "core:mem"
import "core:time"

import sdl "vendor:sdl3"

import im "shared:odin-imgui"
import im_sdl "shared:odin-imgui/imgui_impl_sdl3"
import vox "shared:odin-vox"

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
SCALE :: 6

st: struct {
	renderer: gfx.Renderer,
	settings: settings.Settings,
	ui:       ui.UI,
	vmap:     voxels.Voxel_Map,
	cam:      utils.Camera,
}

run :: proc() -> bool {
	// clear_color: [3]f32 = {0, 0.2, 0.4}
	st.vmap = voxels.voxel_map_create({128, 128, 128}); defer voxels.voxel_map_destroy(&st.vmap)
	// for x in 2 ..< 6 {
	// 	for z in 2 ..< 6 {
	// 		for y in 2 ..< 6 {
	// 			voxels.vmap_set(&st.vmap, {cast(i32)x, cast(i32)y, cast(i32)z}, 1)
	// 		}
	// 	}
	// }
	voxels.vmap_set(&st.vmap, 0, 1)
	for x in 0 ..< 128 {
		for z in 0 ..< 128 {
			for y in 0 ..< 128 {
				// get 3d noise
				// if above threshold, set voxel
				v := noise.noise_3d_improve_xz(1, {f64(x), f64(y), f64(z)} * 0.08)
				if v > 0.2 {
					voxels.vmap_set(&st.vmap, {i32(x), i32(y), i32(z)}, 1)
				}
			}
		}
	}

	nodes := make([dynamic]voxels.Node64, 1); defer delete(nodes)
	leaf_data := make([dynamic]u8); defer delete(leaf_data)
	assign_at(&nodes, 0, voxels.bit_tree64_construct(st.vmap, &nodes, &leaf_data, SCALE, 0))
	ops.window_init("leijjuva", {W_WIDTH, W_HEIGHT}) or_return; defer ops.window_destroy()

	st.renderer = gfx.renderer_create(
		ops.get_window(),
	) or_return; defer gfx.renderer_destroy(&st.renderer)

	gui.init(ops.get_window(), st.renderer.gpu) or_return; defer gui.destroy()

	vrt := shaders.compile_from_file(
		"./shaders/64bit_traverse.slang",
		.Compute,
		"ComputeMain",
	) or_return; defer shaders.shader_destroy(&vrt, st.renderer.gpu)
	vrt_comp := shaders.shader_compute_pipeline(
		&vrt,
		st.renderer.gpu,
		{
			thread_count = {8, 8, 1},
			readwrite_storage_textures = 1,
			uniform_buffers = 1,
			readonly_storage_buffers = 1,
		},
	) or_return

	// need to copy vertex stuff to gpu (need to add abstraction later)
	nodes_size := cast(u32)(size_of(nodes[0]) * len(nodes))
	node_buffer := sdl.CreateGPUBuffer(
		st.renderer.gpu,
		{usage = {.COMPUTE_STORAGE_READ}, size = nodes_size},
	); defer sdl.ReleaseGPUBuffer(st.renderer.gpu, node_buffer)

	transfer_buf := sdl.CreateGPUTransferBuffer(
		st.renderer.gpu,
		{usage = .UPLOAD, size = nodes_size},
	)

	transfer_mem := sdl.MapGPUTransferBuffer(st.renderer.gpu, transfer_buf, false)
	assert(transfer_mem != nil)
	mem.copy(transfer_mem, raw_data(nodes[:]), cast(int)nodes_size)
	sdl.UnmapGPUTransferBuffer(st.renderer.gpu, transfer_buf)

	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(st.renderer.gpu)

	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer_buf},
		{buffer = node_buffer, size = nodes_size},
		false,
	)
	sdl.ReleaseGPUTransferBuffer(st.renderer.gpu, transfer_buf)

	sdl.EndGPUCopyPass(copy_pass)

	assert(sdl.SubmitGPUCommandBuffer(copy_cmd_buf))

	st.cam = utils.camera_init()

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

			case .MOUSE_MOTION:
			// xrel := f32(ev.motion.xrel)
			// yrel := f32(ev.motion.yrel)
			// utils.camera_process_mouse(&st.cam, xrel, yrel)
			}
		}

		kb_state := sdl.GetKeyboardState(nil)
		if kb_state[sdl.Scancode.W] do utils.camera_process_keyboard(&st.cam, .Forward, ds.dt)
		if kb_state[sdl.Scancode.S] do utils.camera_process_keyboard(&st.cam, .Backward, ds.dt)
		if kb_state[sdl.Scancode.A] do utils.camera_process_keyboard(&st.cam, .Left, ds.dt)
		if kb_state[sdl.Scancode.D] do utils.camera_process_keyboard(&st.cam, .Right, ds.dt)
		if kb_state[sdl.Scancode.SPACE] do utils.camera_process_keyboard(&st.cam, .Up, ds.dt)
		if kb_state[sdl.Scancode.LCTRL] do utils.camera_process_keyboard(&st.cam, .Down, ds.dt)

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

		sdl.BindGPUComputeStorageBuffers(comp_pass, 0, &node_buffer, 1)

		// view := utils.camera_get_view_matrix(st.cam)
		view_rot := ln.to_matrix4f32(
			ln.quaternion_look_at(st.cam.position, st.cam.position + st.cam.front, st.cam.up),
		)
		proj := utils.camera_get_projection_matrix(
			st.cam,
			f32(st.ui.vp_size.x) / f32(st.ui.vp_size.y),
		)
		vp := proj * view_rot
		uniform_data: struct {
			inv_proj_mat: ln.Matrix4f32, // 64
			cam_pos:      [3]f32, // 3*4=12
			_:            f32, // pad with 4 bytes
			world_origin: [3]i32,
			_:            f32, // pad with 4 bytes
			tree_scale:   u32,
		} = {
			inv_proj_mat = ln.inverse(vp),
			cam_pos      = st.cam.position,
			tree_scale   = SCALE,
			world_origin = 0,
		}
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
		im.Begin("Test")
		im.Text(fmt.ctprintf("camera at: %v", st.cam.position))
		im.End()

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

