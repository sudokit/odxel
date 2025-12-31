package utils

import "core:fmt"
import "core:time"

Debug_Stats :: struct {
	avg_fps, avg_dt: f32,
	dt, fps:         f32,
}

ds_update :: proc "contextless" (start: time.Tick, $F: i32) -> Debug_Stats {
	@(static) dt_history, fps_history: [F]f32
	@(static) dt_index, fps_index: i32

	dtd := time.tick_diff(start, time.tick_now())
	dt := time.duration_seconds(dtd)
	// dt over last 30 frames.
	dt_history[dt_index % len(dt_history)] = cast(f32)dt
	dt_index += 1

	fps_history[fps_index % len(fps_history)] = 1 / (cast(f32)dt)
	fps_index += 1

	cdt, fps: f32
	iter := soa_zip(dt = dt_history[:], fps = fps_history[:])
	for s in iter {
		cdt += s.dt
		fps += s.fps
	}

	return {
		avg_fps = fps / f32(len(fps_history)),
		avg_dt = cdt / f32(len(dt_history)),
		dt = cast(f32)dt,
		fps = 1 / cast(f32)dt,
	}
}

