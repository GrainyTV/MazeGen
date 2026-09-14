const std = @import("std");
const texture = @import("texture.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});
const Clock = std.Io.Clock;

const WINDOW_WIDTH = 636;
const WINDOW_HEIGHT = 132;
const CELL_SIZE = 12;

const BlockKind = enum {
    WALL,
    AVAILABLE_NEIGHBOR,
    PASSAGE,
};

const IVec2 = struct {
    x: i32,
    y: i32,
};

pub fn fatal(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
    std.debug.print("==> {s}\n", .{sdl.SDL_GetError()});
    std.process.exit(1);
}

pub fn registerValidNeighbors(comptime maxw: u32, comptime maxh: u32, pos: IVec2, fields: *[maxw][maxh]BlockKind, neighbors: *std.ArrayList(IVec2)) void {
    var x: i32 = undefined;
    var y: i32 = undefined;

    //| LEFT
    x = pos.x - 2;
    y = pos.y;

    if (x >= 0 and fields[@intCast(x)][@intCast(y)] == .WALL) {
        neighbors.appendAssumeCapacity(IVec2{ .x = x, .y = y });
        fields[@intCast(x)][@intCast(y)] = .AVAILABLE_NEIGHBOR;
    }

    //| RIGHT
    x = pos.x + 2;
    y = pos.y;

    if (x < maxw and fields[@intCast(x)][@intCast(y)] == .WALL) {
        neighbors.appendAssumeCapacity(IVec2{ .x = x, .y = y });
        fields[@intCast(x)][@intCast(y)] = .AVAILABLE_NEIGHBOR;
    }

    //| BOTTOM
    x = pos.x;
    y = pos.y - 2;

    if (y >= 0 and fields[@intCast(x)][@intCast(y)] == .WALL) {
        neighbors.appendAssumeCapacity(IVec2{ .x = x, .y = y });
        fields[@intCast(x)][@intCast(y)] = .AVAILABLE_NEIGHBOR;
    }

    //| TOP
    x = pos.x;
    y = pos.y + 2;

    if (y < maxh and fields[@intCast(x)][@intCast(y)] == .WALL) {
        neighbors.appendAssumeCapacity(IVec2{ .x = x, .y = y });
        fields[@intCast(x)][@intCast(y)] = .AVAILABLE_NEIGHBOR;
    }
}

pub fn rollConnectorPassage(comptime maxw: u32, comptime maxh: u32, pos: IVec2, rnd: *const std.Random, fields: *[maxw][maxh]BlockKind) IVec2 {
    var cnt: usize = 0;
    var buf: [4]IVec2 = undefined;

    var x: i32 = undefined;
    var y: i32 = undefined;

    x = pos.x - 2;
    y = pos.y;

    if (x >= 0 and fields[@intCast(x)][@intCast(y)] == .PASSAGE) {
        buf[cnt] = IVec2{ .x = x, .y = y };
        cnt += 1;
    }

    x = pos.x + 2;
    y = pos.y;

    if (x < maxw and fields[@intCast(x)][@intCast(y)] == .PASSAGE) {
        buf[cnt] = IVec2{ .x = x, .y = y };
        cnt += 1;
    }

    x = pos.x;
    y = pos.y - 2;

    if (y >= 0 and fields[@intCast(x)][@intCast(y)] == .PASSAGE) {
        buf[cnt] = IVec2{ .x = x, .y = y };
        cnt += 1;
    }

    x = pos.x;
    y = pos.y + 2;

    if (y < maxh and fields[@intCast(x)][@intCast(y)] == .PASSAGE) {
        buf[cnt] = IVec2{ .x = x, .y = y };
        cnt += 1;
    }

    std.debug.assert(cnt > 0); // Cannot connect if no passages are found, at least one is needed each time
    const idx = rnd.uintLessThan(usize, cnt);

    return .{
        .x = (pos.x + buf[idx].x) >> 1,
        .y = (pos.y + buf[idx].y) >> 1,
    };
}

pub fn renderMaze(renderer: ?*sdl.SDL_Renderer, brickTextureSdl: [*c]sdl.SDL_Texture, comptime maxw: u32, comptime maxh: u32, fields: *[maxw][maxh]BlockKind, active: IVec2) void {
    for (0..maxh) |y| {
        for (0..maxw) |x| {
            const tgt = sdl.SDL_FRect{ .x = @floatFromInt(x * CELL_SIZE), .y = @floatFromInt(y * CELL_SIZE), .w = CELL_SIZE, .h = CELL_SIZE };

            if (fields[x][y] == .WALL) {
                _ = sdl.SDL_RenderTexture(renderer, brickTextureSdl, null, @ptrCast(&tgt));
            } else if (fields[x][y] == .PASSAGE) {
                _ = sdl.SDL_SetRenderDrawColor(renderer, 167, 78, 72, 255);
                _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
            } else if (fields[x][y] == .AVAILABLE_NEIGHBOR) {
                _ = sdl.SDL_RenderTexture(renderer, brickTextureSdl, null, @ptrCast(&tgt));
                _ = sdl.SDL_SetRenderDrawColor(renderer, 213, 224, 56, 127);
                _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
            }

            if (x == active.x and y == active.y) {
                _ = sdl.SDL_SetRenderDrawColor(renderer, 134, 56, 224, 187);
                _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
            }
        }
    }
}

pub fn pauseExecution(io: std.Io) void {
    Clock.Duration.sleep(Clock.Duration{ .clock = .real, .raw = .fromMilliseconds(125) }, io) catch @panic("sleeperr");
}

pub fn generatePrimMazeAsync(io: std.Io, comptime maxw: u32, comptime maxh: u32, activePos: *IVec2, fields: *[maxw][maxh]BlockKind, allocator: *std.mem.Allocator) void {
    var neighbors = std.ArrayList(IVec2).initCapacity(allocator.*, maxw * maxh) catch @panic("oom");

    var xoshiro = std.Random.DefaultPrng.init(67);
    const rnd = xoshiro.random();

    for (0..maxh) |y| {
        for (0..maxw) |x| {
            fields[x][y] = .WALL;
        }
    }

    // 1.) All wall render
    pauseExecution(io);

    // 2.) Entrance render
    fields[0][maxh - 2] = .PASSAGE;
    pauseExecution(io);

    // 3.) Exit render
    fields[maxw - 1][1] = .PASSAGE;
    pauseExecution(io);

    var previousPos: IVec2 = undefined;
    activePos.* = IVec2{ .x = 1, .y = maxh - 2 };
    registerValidNeighbors(maxw, maxh, activePos.*, fields, &neighbors);

    // 4.) First field render
    pauseExecution(io);

    while (neighbors.items.len > 0) {
        const idx = rnd.uintLessThan(usize, neighbors.items.len);

        fields[@intCast(activePos.x)][@intCast(activePos.y)] = .PASSAGE;
        previousPos = activePos.*;
        activePos.* = neighbors.items[idx];

        const connectorPos = rollConnectorPassage(maxw, maxh, activePos.*, &rnd, fields);
        fields[@intCast(connectorPos.x)][@intCast(connectorPos.y)] = .PASSAGE;

        // 5.) Actual changes render
        pauseExecution(io);

        _ = neighbors.orderedRemove(idx);
        registerValidNeighbors(maxw, maxh, activePos.*, fields, &neighbors);
    }

    fields[@intCast(activePos.x)][@intCast(activePos.y)] = .PASSAGE; // last active position is stuck as neighbor

    // 6.) Final render
    activePos.* = .{ .x = -1, .y = -1 };
    pauseExecution(io);
}

pub fn main(args: std.process.Init) void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS)) {
        fatal("Failed to initialize SDL3\n", .{});
    }

    const window = sdl.SDL_CreateWindow("MazeGen", WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_VULKAN);

    if (window == null) {
        fatal("Failed to create window\n", .{});
    }

    const renderer = sdl.SDL_CreateRenderer(window, null);
    const toggleVsync = sdl.SDL_SetRenderVSync(renderer, 1);

    if (renderer == null or !toggleVsync) {
        fatal("Failed to create renderer or enable vsync\n", .{});
    }

    _ = sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND);

    const brickSurfaceSdl = sdl.SDL_LoadBMP_IO(sdl.SDL_IOFromConstMem(&texture.BrickDataBMP, texture.BrickDataBMP.len), true);
    defer sdl.SDL_DestroySurface(brickSurfaceSdl);

    const brickTextureSdl = sdl.SDL_CreateTextureFromSurface(renderer, brickSurfaceSdl);
    defer sdl.SDL_DestroyTexture(brickTextureSdl);

    if (brickTextureSdl == null) {
        fatal("Failed to create brick texture\n", .{});
    }

    const cellCountHorizontal = WINDOW_WIDTH / CELL_SIZE;
    const cellCountVertical = WINDOW_HEIGHT / CELL_SIZE;

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    var isRunning: bool = true;
    var currentEvent: sdl.SDL_Event = undefined;

    var fields: [cellCountHorizontal][cellCountVertical]BlockKind = undefined;
    var activePos: IVec2 = .{ .x = -1, .y = -1 };

    var animateThread: std.Thread = undefined;
    var animatingFields: bool = false;
    var frameCount: u32 = 0;

    while (isRunning) {
        while (sdl.SDL_PollEvent(&currentEvent)) {
            switch (currentEvent.type) {
                sdl.SDL_EVENT_KEY_DOWN => {
                    switch (currentEvent.key.key) {
                        sdl.SDLK_Q, sdl.SDLK_ESCAPE => isRunning = false,
                        sdl.SDLK_SPACE => {
                            std.Io.Dir.cwd().createDirPath(args.io, "frames") catch @panic("mkdirerr");
                            animateThread = std.Thread.spawn(
                                .{},
                                generatePrimMazeAsync,
                                .{ args.io, cellCountHorizontal, cellCountVertical, &activePos, &fields, &allocator },
                            ) catch @panic("threaderr");
                            animatingFields = true;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        _ = sdl.SDL_SetRenderDrawColor(renderer, 133, 133, 133, 255);
        _ = sdl.SDL_RenderClear(renderer);

        if (animatingFields) {
            renderMaze(renderer, brickTextureSdl, cellCountHorizontal, cellCountVertical, &fields, activePos);
        }

        _ = sdl.SDL_RenderPresent(renderer);

        if (animatingFields) {
            //| You can then use ffmpeg to merge the frames
            //| e.g. ffmpeg -framerate 144 -i frames/frame_%05d.bmp -default_delay 7 -ignore_loop false -loop 0 -lossless 1 maze.webp

            const frame = sdl.SDL_RenderReadPixels(renderer, null);
            defer sdl.SDL_DestroySurface(frame);

            const outPath: [:0]const u8 = std.fmt.allocPrintSentinel(allocator, "frames/frame_{d:0>5}.bmp", .{frameCount}, 0) catch @panic("oom");
            _ = sdl.SDL_SaveBMP(frame, outPath.ptr);

            frameCount += 1;
        }
    }
}
