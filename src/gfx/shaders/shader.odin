package shaders

import "core:fmt"
import "core:log"
import "core:os/os2"
import "core:path/filepath"
import "core:reflect"
import "core:strings"

import sdl "vendor:sdl3"

Shader_Stage :: enum {
	Vertex,
	Fragment,
	Compute,
}

Shader :: struct {
	path:        string,
	stage:       Shader_Stage,
	entry_point: cstring,
	byte_code:   []byte,
	obj:         union #shared_nil {
		^sdl.GPUShader,
		^sdl.GPUComputePipeline,
	},
}

compile_from_file :: proc(
	path: string,
	stage: Shader_Stage,
	entry_point: cstring,
	inc_dir: string = "",
) -> (
	s: Shader = {},
	ok: bool,
) {
	s.path = path
	s.entry_point = entry_point
	s.stage = stage

	if !shader_compile(&s, inc_dir) do return {}, false

	return s, true
}

shader_destroy :: proc(s: ^Shader, gpu: ^sdl.GPUDevice) {
	if s.obj != nil {
		switch obj in s.obj {
		case ^sdl.GPUShader:
			sdl.ReleaseGPUShader(gpu, obj)
		case ^sdl.GPUComputePipeline:
			sdl.ReleaseGPUComputePipeline(gpu, obj)
		}
	}
	if len(s.byte_code) != 0 do delete(s.byte_code)
}

shader_compile :: proc(s: ^Shader, inc_dir: string) -> bool {
	log.infof("Compiling shader %s (%v / %s)", s.path, s.stage, s.entry_point)

	if err := os2.mkdir(".shader_out"); err != nil && err != .Exist do return false
	cmd := "/usr/bin/slangc -matrix-layout-column-major -I%s %s -target spirv -entry %s -stage %s -o %s"

	stage := strings.to_lower(reflect.enum_string(s.stage))

	buffer: [1024]u8
	path := fmt.tprintf(".shader_out/%s.spirv", filepath.base(s.path))
	fmt.bprintf(
		buffer[:],
		cmd,
		len(inc_dir) == 0 ? filepath.dir(s.path) : inc_dir,
		s.path,
		s.entry_point,
		stage,
		path,
	)
	log.debugf("Shader comp command: %s", string(buffer[:]))
	pstate, stdout, stderr, err := os2.process_exec(
		{command = strings.split(string(buffer[:]), " ")},
		context.temp_allocator,
	)
	if len(stderr) != 0 || err != nil || pstate.exit_code != 0 {
		log.errorf("%v", string(stderr))
		return false
	}

	code, e := os2.read_entire_file_from_path(path, context.allocator)
	if e != nil && err != .Exist do return false
	s.byte_code = code

	return true
}

shader_create :: proc(s: ^Shader, gpu: ^sdl.GPUDevice, num: struct {
		samplers:         u32,
		storage_textures: u32,
		storage_buffers:  u32,
		uniform_buffers:  u32,
	}) -> (^sdl.GPUShader, bool) {
	assert(
		s.stage != .Compute,
		"Can't create a compute shader. Need to call `shader_compute_pipeline` instead",
	)
	if len(s.byte_code) == 0 do return nil, false
	s.obj = sdl.CreateGPUShader(
		gpu,
		{
			code_size = len(s.byte_code),
			code = raw_data(s.byte_code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = cast(sdl.GPUShaderStage)s.stage,
			num_samplers = num.samplers,
			num_storage_textures = num.storage_textures,
			num_storage_buffers = num.storage_buffers,
			num_uniform_buffers = num.uniform_buffers,
		},
	)
	if s.obj == nil {
		return nil, false
	}
	return s.obj.(^sdl.GPUShader), true
}

shader_compute_pipeline :: proc(s: ^Shader, gpu: ^sdl.GPUDevice, num: struct {
		samplers:                   u32,
		readonly_storage_textures:  u32,
		readonly_storage_buffers:   u32,
		readwrite_storage_textures: u32,
		readwrite_storage_buffers:  u32,
		uniform_buffers:            u32,
		thread_count:               [3]u32,
	}) -> (^sdl.GPUComputePipeline, bool) {
	s.obj = sdl.CreateGPUComputePipeline(
		gpu,
		{
			code_size = len(s.byte_code),
			code = raw_data(s.byte_code),
			entrypoint = "main",
			format = {.SPIRV},
			num_samplers = num.samplers,
			num_readonly_storage_textures = num.readonly_storage_textures,
			num_readonly_storage_buffers = num.readonly_storage_buffers,
			num_readwrite_storage_textures = num.readwrite_storage_textures,
			num_readwrite_storage_buffers = num.readwrite_storage_buffers,
			num_uniform_buffers = num.uniform_buffers,
			threadcount_x = num.thread_count.x,
			threadcount_y = num.thread_count.y,
			threadcount_z = num.thread_count.z,
		},
	)

	if s.obj == nil {
		return nil, false
	}
	return s.obj.(^sdl.GPUComputePipeline), true
}

