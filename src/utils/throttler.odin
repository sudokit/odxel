package utils

import "core:fmt"
import "core:time"

throttle :: proc(start: time.Tick, target_fps: i32 = 60) {
	if target_fps == 0 do return
	dtd := time.tick_diff(start, time.tick_now())
	target := time.Second / time.Duration(target_fps)
	if dtd < target {
		time.sleep(target - dtd)
	}
}

