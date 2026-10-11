const std = @import("std");
const texture = @import("texture.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});
const Clock = std.Io.Clock;

const WINDOW_WIDTH = 396;
const WINDOW_HEIGHT = 108;
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

const Neighbor = struct {
    pos: IVec2,
    distance: u32,
};

pub fn fatal(comptime condition: []const u8) noreturn {
    std.debug.print("[ERROR] {s}\n", .{condition});
    std.debug.print("==> {s}\n", .{sdl.SDL_GetError()});
    std.process.exit(1);
}

pub fn registerValidNeighbor(comptime maxw: u32, comptime maxh: u32, fields: *[maxw][maxh]BlockKind, neighbors: *std.ArrayList(Neighbor), x: i32, y: i32) void {
    if (x >= 0 and y >= 0 and x < maxw and y < maxh) {
        const xu: usize = @intCast(x);
        const yu: usize = @intCast(y);

        if (fields[xu][yu] == .WALL) {
            neighbors.appendAssumeCapacity(.{ .pos = IVec2{ .x = x, .y = y }, .distance = 0 });
            fields[xu][yu] = .AVAILABLE_NEIGHBOR;
        }
    }
}

pub fn registerValidNeighbors(comptime maxw: u32, comptime maxh: u32, pos: IVec2, fields: *[maxw][maxh]BlockKind, neighbors: *std.ArrayList(Neighbor)) void {
    registerValidNeighbor(maxw, maxh, fields, neighbors, pos.x - 2, pos.y);
    registerValidNeighbor(maxw, maxh, fields, neighbors, pos.x + 2, pos.y);
    registerValidNeighbor(maxw, maxh, fields, neighbors, pos.x, pos.y - 2);
    registerValidNeighbor(maxw, maxh, fields, neighbors, pos.x, pos.y + 2);
}

pub fn applyDistancesReturnImmediateNeighbors(active: IVec2, neighbors: *std.ArrayList(Neighbor)) usize {
    var cnt: usize = 0;

    for (0..neighbors.items.len) |i| {
        const distance = @abs(active.x - neighbors.items[i].pos.x) + @abs(active.y - neighbors.items[i].pos.y);
        neighbors.items[i].distance = distance;

        if (distance == 2) {
            cnt += 1;
        }
    }

    return cnt;
}

pub fn sortNeighborsByDistance(neighbors: *std.ArrayList(Neighbor)) void {
    for (0..neighbors.items.len) |i| {
        for ((i + 1)..neighbors.items.len) |j| {
            if (neighbors.items[i].distance > neighbors.items[j].distance) {
                const tmp = neighbors.items[i];
                neighbors.items[i] = neighbors.items[j];
                neighbors.items[j] = tmp;
            }
        }
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
    const YELLOW_MARKER = sdl.SDL_Color{ .r = 213, .g = 224, .b = 56, .a = 127 };
    const PURPLE_MARKER = sdl.SDL_Color{ .r = 134, .g = 56, .b = 224, .a = 187 };
    const BROWN_PASSAGE = sdl.SDL_Color{ .r = 167, .g = 78, .b = 72, .a = 255 };

    for (0..maxh) |y| {
        for (0..maxw) |x| {
            const tgt = sdl.SDL_FRect{ .x = @floatFromInt(x * CELL_SIZE), .y = @floatFromInt(y * CELL_SIZE), .w = CELL_SIZE, .h = CELL_SIZE };

            if (fields[x][y] == .PASSAGE) {
                _ = sdl.SDL_SetRenderDrawColor(renderer, BROWN_PASSAGE.r, BROWN_PASSAGE.g, BROWN_PASSAGE.b, BROWN_PASSAGE.a);
                _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
            } else {
                _ = sdl.SDL_RenderTexture(renderer, brickTextureSdl, null, @ptrCast(&tgt));

                if (x == active.x and y == active.y) {
                    _ = sdl.SDL_SetRenderDrawColor(renderer, PURPLE_MARKER.r, PURPLE_MARKER.g, PURPLE_MARKER.b, PURPLE_MARKER.a);
                    _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
                } else if (fields[x][y] == .AVAILABLE_NEIGHBOR) {
                    _ = sdl.SDL_SetRenderDrawColor(renderer, YELLOW_MARKER.r, YELLOW_MARKER.g, YELLOW_MARKER.b, YELLOW_MARKER.a);
                    _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
                }
            }
        }
    }
}

pub fn pauseExecutionExplicit(io: std.Io, ms: i64) void {
    Clock.Duration.sleep(Clock.Duration{ .clock = .real, .raw = .fromMilliseconds(ms) }, io) catch @panic("sleeperr");
}

pub fn pauseExecution(io: std.Io) void {
    pauseExecutionExplicit(io, 125);
}

pub fn generatePrimMazeAsync(io: std.Io, comptime maxw: u32, comptime maxh: u32, activePos: *IVec2, fields: *[maxw][maxh]BlockKind, allocator: *std.mem.Allocator, animate: *bool) void {
    var neighbors = std.ArrayList(Neighbor).initCapacity(allocator.*, maxw * maxh) catch @panic("oom");

    var xoshiro = std.Random.DefaultPrng.init(69420);
    const rnd = xoshiro.random();

    for (0..maxh) |y| {
        for (0..maxw) |x| {
            fields[x][y] = .WALL;
        }
    }

    animate.* = true;

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
        const nextToCount = applyDistancesReturnImmediateNeighbors(activePos.*, &neighbors);

        if (nextToCount > 0) {
            //| If there are available neighbors right next to our position (in Manhattan distance)
            //| we choose from those.
            //| Otherwise we may pick any available neighbor.
            sortNeighborsByDistance(&neighbors);
        }

        const idx = if (nextToCount > 0) rnd.uintLessThan(usize, nextToCount) else rnd.uintLessThan(usize, neighbors.items.len);

        fields[@intCast(activePos.x)][@intCast(activePos.y)] = .PASSAGE;
        previousPos = activePos.*;
        activePos.* = neighbors.items[idx].pos;

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

    // 7.) Extra delay at the end
    pauseExecutionExplicit(io, 2000);
    animate.* = false;
}

pub fn main(args: std.process.Init) void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS)) {
        fatal("Failed to initialize SDL3");
    }

    const window = sdl.SDL_CreateWindow("MazeGen", WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_VULKAN);

    if (window == null) {
        fatal("Failed to create SDL3 window");
    }

    const renderer = sdl.SDL_CreateRenderer(window, null);
    const toggleVsync = sdl.SDL_SetRenderVSync(renderer, 1);

    if (renderer == null) {
        fatal("Failed to create SDL3 renderer");
    }

    if (!toggleVsync) {
        fatal("Failed to enable vsync");
    }

    _ = sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND);

    const brickSurfaceSdl = sdl.SDL_LoadBMP_IO(sdl.SDL_IOFromConstMem(&texture.BrickDataBMP, texture.BrickDataBMP.len), true);
    defer sdl.SDL_DestroySurface(brickSurfaceSdl);

    const brickTextureSdl = sdl.SDL_CreateTextureFromSurface(renderer, brickSurfaceSdl);
    defer sdl.SDL_DestroyTexture(brickTextureSdl);

    if (brickTextureSdl == null) {
        fatal("Failed to create brick texture");
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
    var enableMazeRender: bool = false;
    var frameCount: u32 = 0;

    while (isRunning) {
        while (sdl.SDL_PollEvent(&currentEvent)) {
            if (currentEvent.type == sdl.SDL_EVENT_KEY_DOWN) {
                switch (currentEvent.key.key) {
                    sdl.SDLK_Q, sdl.SDLK_ESCAPE => {
                        isRunning = false;
                    },
                    sdl.SDLK_SPACE => {
                        if (!enableMazeRender) {
                            enableMazeRender = true;

                            std.Io.Dir.cwd().createDirPath(args.io, "frames") catch @panic("mkdirerr");

                            animateThread = std.Thread.spawn(
                                .{},
                                generatePrimMazeAsync,
                                .{ args.io, cellCountHorizontal, cellCountVertical, &activePos, &fields, &allocator, &animatingFields },
                            ) catch @panic("threaderr");
                        }
                    },
                    else => {},
                }
            }
        }

        _ = sdl.SDL_SetRenderDrawColor(renderer, 133, 133, 133, 255);
        _ = sdl.SDL_RenderClear(renderer);

        if (enableMazeRender) {
            renderMaze(renderer, brickTextureSdl, cellCountHorizontal, cellCountVertical, &fields, activePos);

            if (animatingFields) {
                //| You can use something like ffmpeg to merge the frames
                //| FPS is refresh rate when vsync is ON
                //| Delay is 1000ms / FPS, e.g. 7 (≈1000ms/144fps)
                //| ---
                //| ffmpeg -framerate 144 -i frames/frame_%05d.bmp -default_delay 7 -ignore_loop false -loop 0 -lossless 1 maze.webp

                const frame = sdl.SDL_RenderReadPixels(renderer, null);
                defer sdl.SDL_DestroySurface(frame);

                const outPath: [:0]const u8 = std.fmt.allocPrintSentinel(allocator, "frames/frame_{d:0>5}.bmp", .{frameCount}, 0) catch @panic("oom");
                _ = sdl.SDL_SaveBMP(frame, outPath.ptr);

                frameCount += 1;
            }
        }

        _ = sdl.SDL_RenderPresent(renderer);
    }
}
