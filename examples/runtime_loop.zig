//! Simple runtime loop with optional FPS cap sweep.
//! Default: 160 FPS with per-frame '\r' logging.

const std = @import("std");

pub fn main() !void {
    const config = parseArgs() catch |err| {
        if (err == error.InvalidArgs) return;
        return err;
    };

    switch (config.mode) {
        .target => try runLoop(config.target_fps, config.seconds),
        .cap => try runCapSweep(config.seconds),
    }
}

const Mode = enum { target, cap };

const Config = struct {
    mode: Mode = .target,
    target_fps: u64 = 160,
    seconds: u64 = 5,
};

const Stats = struct {
    frames: u64,
    elapsed_ns: u64,
    late_frames: u64,
};

fn parseArgs() !Config {
    var config = Config{};

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--cap")) {
            config.mode = .cap;
        } else if (std.mem.eql(u8, arg, "--fps")) {
            if (i + 1 >= args.len) {
                printUsage();
                return error.InvalidArgs;
            }
            i += 1;
            config.target_fps = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--seconds")) {
            if (i + 1 >= args.len) {
                printUsage();
                return error.InvalidArgs;
            }
            i += 1;
            config.seconds = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return error.InvalidArgs;
        } else {
            printUsage();
            return error.InvalidArgs;
        }
    }

    return config;
}

fn printUsage() void {
    std.debug.print(
        "usage: runtime_loop [--fps N] [--seconds N] [--cap]\n",
        .{},
    );
}

fn runLoop(target_fps: u64, seconds: u64) !void {
    if (target_fps == 0 or target_fps > std.time.ns_per_s or seconds == 0) {
        return;
    }

    const target_frame_ns: u64 = std.time.ns_per_s / target_fps;
    const end_ns: u64 = seconds * std.time.ns_per_s;

    var timer = try std.time.Timer.start();
    var next_frame_ns: u64 = target_frame_ns;
    var last_frame_ns: u64 = timer.read();

    var frame: u64 = 0;
    while (true) {
        const now = timer.read();
        if (now >= end_ns) break;

        if (now < next_frame_ns) {
            std.Thread.sleep(next_frame_ns - now);
        }

        const frame_start = timer.read();
        if (frame_start >= end_ns) break;

        const delta_ns = frame_start - last_frame_ns;
        last_frame_ns = frame_start;
        next_frame_ns += target_frame_ns;

        const delta_ms = @as(f64, @floatFromInt(delta_ns)) /
            @as(f64, @floatFromInt(std.time.ns_per_ms));
        std.debug.print("\rframe {d} dt={d:.3}ms   ", .{ frame, delta_ms });
        frame += 1;
    }

    const elapsed_ns = timer.read();
    const fps = calcFps(frame, elapsed_ns);
    std.debug.print("\nactual fps={d:.1}\n", .{fps});
}

fn runCapSweep(seconds: u64) !void {
    if (seconds == 0) return;

    const targets = [_]u64{
        30, 60, 90, 120, 144, 160, 180, 200, 240, 300, 360, 480, 600, 720, 1000,
    };

    var best: u64 = 0;
    std.debug.print("Cap sweep: {d} seconds each\n", .{seconds});

    for (targets) |target| {
        const stats = try measureTarget(target, seconds);
        const fps = calcFps(stats.frames, stats.elapsed_ns);
        const miss_pct = if (stats.frames == 0)
            100.0
        else
            (@as(f64, @floatFromInt(stats.late_frames)) * 100.0) /
                @as(f64, @floatFromInt(stats.frames));

        std.debug.print(
            "target={d} actual={d:.1} miss={d:.1}%\n",
            .{ target, fps, miss_pct },
        );

        if (fps >= @as(f64, @floatFromInt(target)) * 0.98) {
            best = target;
        }
    }

    if (best == 0) {
        std.debug.print("cap < {d} fps\n", .{targets[0]});
    } else {
        std.debug.print("cap ~= {d} fps (>=98% target)\n", .{best});
    }
}

fn measureTarget(target_fps: u64, seconds: u64) !Stats {
    if (target_fps == 0 or target_fps > std.time.ns_per_s) {
        return Stats{ .frames = 0, .elapsed_ns = 0, .late_frames = 0 };
    }

    const target_frame_ns: u64 = std.time.ns_per_s / target_fps;
    const end_ns: u64 = seconds * std.time.ns_per_s;

    var timer = try std.time.Timer.start();
    var next_frame_ns: u64 = target_frame_ns;
    var frames: u64 = 0;
    var late_frames: u64 = 0;

    while (true) {
        const now = timer.read();
        if (now >= end_ns) break;

        if (now < next_frame_ns) {
            std.Thread.sleep(next_frame_ns - now);
        } else {
            late_frames += 1;
        }

        const frame_start = timer.read();
        if (frame_start >= end_ns) break;

        frames += 1;
        next_frame_ns += target_frame_ns;
    }

    const elapsed_ns = timer.read();
    return Stats{
        .frames = frames,
        .elapsed_ns = elapsed_ns,
        .late_frames = late_frames,
    };
}

fn calcFps(frames: u64, elapsed_ns: u64) f64 {
    if (elapsed_ns == 0) return 0;

    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) /
        @as(f64, @floatFromInt(std.time.ns_per_s));
    return @as(f64, @floatFromInt(frames)) / elapsed_s;
}
