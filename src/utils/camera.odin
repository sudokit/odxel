package utils

import "core:fmt"
import m "core:math"
import ln "core:math/linalg"

// TODO: redo

Camera :: struct {
	position:          [3]f32,
	front:             [3]f32, // direction the camera is facing
	up:                [3]f32, // world up is usually [0,1,0]
	right:             [3]f32,
	yaw:               f32, // degrees, rotation around Y axis
	pitch:             f32, // degrees, rotation around X axis
	speed:             f32,
	mouse_sensitivity: f32,
	fov:               f32, // field of view in degrees
}

camera_init :: proc(pos := [3]f32{0, 0, 0}, target := [3]f32{}) -> (cam: Camera) {
	cam.position = pos
	cam.front = {0, 0, 1}
	cam.up = {0, 1, 0}
	cam.yaw = 0.0
	cam.pitch = 0.0
	cam.speed = 50
	cam.mouse_sensitivity = 0.1
	cam.fov = 90.0

	camera_update_vectors(&cam)
	return cam
}

camera_update_vectors :: proc(cam: ^Camera) {
	// Calculate front direction from yaw and pitch
	front: [3]f32
	front.x = m.cos(m.to_radians(cam.yaw)) * m.cos(m.to_radians(cam.pitch))
	front.y = m.sin(m.to_radians(cam.pitch))
	front.z = m.sin(m.to_radians(cam.yaw)) * m.cos(m.to_radians(cam.pitch))
	cam.front = ln.normalize(front)

	// Recompute right and up vectors
	cam.right = ln.normalize(ln.cross(cam.front, cam.up))
	cam.up = -ln.cross(cam.right, cam.front)
}

camera_process_mouse :: proc(cam: ^Camera, xoffset, yoffset: f32) {
	cam.yaw += xoffset * cam.mouse_sensitivity
	cam.pitch += yoffset * cam.mouse_sensitivity

	// Clamp pitch to avoid flipping
	if cam.pitch > 89.0 do cam.pitch = 89.0
	if cam.pitch < -89.0 do cam.pitch = -89.0

	camera_update_vectors(cam)
}

camera_process_keyboard :: proc(cam: ^Camera, direction: enum {
		Forward,
		Backward,
		Left,
		Right,
		Up,
		Down,
	}, delta_time: f32) {
	velocity := cam.speed * delta_time

	switch direction {
	case .Forward:
		cam.position -= cam.front * velocity
	case .Backward:
		cam.position += cam.front * velocity
	case .Left:
		cam.position += cam.right * velocity
	case .Right:
		cam.position -= cam.right * velocity
	case .Up:
		cam.position -= cam.up * velocity
	case .Down:
		cam.position += cam.up * velocity
	}
}

camera_get_view_matrix :: proc(cam: Camera) -> ln.Matrix4f32 {
	return ln.matrix4_look_at_f32(cam.position, cam.position + cam.front, cam.up, false)
}

camera_get_projection_matrix :: proc(cam: Camera, aspect_ratio: f32) -> ln.Matrix4f32 {
	return ln.matrix4_perspective_f32(
		m.to_radians(cam.fov),
		aspect_ratio,
		1e-3, // near
		1e3, // far
		false,
	)
}

