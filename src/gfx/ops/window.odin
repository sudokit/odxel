package ops

import "base:runtime"

import "core:fmt"
import "core:log"

// TODO: adapt to sdl and sdlgpu

import sdl "vendor:sdl3"

Window :: struct {
	win:           ^sdl.Window,
	width, height: i32,
}

@(private = "file")
_window: Window
@(private = "file")
_initialized := false

get_window :: proc() -> ^sdl.Window {
	return _window.win
}

window_get_size :: proc() -> (i32, i32) {
	w, h: i32
	sdl.GetWindowSize(_window.win, &w, &h)
	return w, h
}

window_claim_for_gpu :: proc(gpu: ^sdl.GPUDevice) -> bool {
	if !sdl.ClaimWindowForGPUDevice(gpu, _window.win) {
		log.fatal("Failed to claim window for gpu")
		return false
	}
	return true
}

// window_get_should_close :: proc() -> bool {
// 	return cast(bool)glfw.WindowShouldClose(_window.win)
// }

// window_frame :: proc() {
// }

window_init :: proc(title: cstring, size: [2]i32) -> bool {
	if _initialized do return false

	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(
		proc "c" (
			userdata: rawptr,
			category: sdl.LogCategory,
			priority: sdl.LogPriority,
			message: cstring,
		) {
			context = runtime.default_context()
			fmt.printfln("[SDL] (%v->%v) %s", category, priority, message)
		},
		nil,
	)
	if !sdl.Init({.VIDEO}) {
		log.fatal("Failed to init sdl")
		return false
	}

	_window.width = size.x
	_window.height = size.y
	_window.win = sdl.CreateWindow(title, size.x, size.y, {.RESIZABLE})
	if _window.win == nil {
		log.fatal("Failed to create a sdl window")
		return false
	}

	return true
}

window_destroy :: proc() {
	if !_initialized do return

	sdl.DestroyWindow(_window.win)
	sdl.Quit()
}

// // callbacks
// @(private = "file")
// _framebuffer_resize :: proc "c" (window: glfw.WindowHandle, width: i32, height: i32) {
// 	_window.width = width
// 	_window.height = height
// }

