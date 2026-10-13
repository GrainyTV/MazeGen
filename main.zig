const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});

const BrickDataBMP = @import("texture.zig").BrickDataBMP;
const Clock = std.Io.Clock;

const PAUSE_MS = 125;
const DEFAULT_SEED = 69420;
const DEFAULT_WIDTH = 33;
const DEFAULT_HEIGHT = 9;
const CELL_SIZE = 12;
const OUT_DIR = "frames/";

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

pub fn usage() void {
    std.debug.print(
        \\usage: ./MazeGen [OPTIONS]
        \\
        \\OPTIONS
        \\  -h, --help      shows this help message and terminates
        \\  --size <NxM>    specifies alternative maze size using formula 2*(N|M)+1, where N[2..76] and M[2..38]
        \\                  (Default: 16x4)
        \\  --seed <seed>   specifies unsigned 64 bit number to use with random generation
        \\                  (Default: 69420)
        \\  --save          enables saving animation frames to an output directory
        \\
    , .{});
}

pub fn usageError(comptime condition: []const u8, args: anytype) noreturn {
    std.debug.print("[ERROR] " ++ condition ++ "\n", args);
    usage();
    std.process.exit(1);
}

pub fn fatal(comptime condition: []const u8) noreturn {
    std.debug.print("[ERROR] {s}\n", .{condition});
    std.debug.print("==> {s}\n", .{sdl.SDL_GetError()});
    std.process.exit(1);
}

pub fn parseLengthValue(comptime T: type, str: []const u8) T {
    return std.fmt.parseUnsigned(T, str, 10) catch {
        usageError("`{s}` is NOT a usable integer value", .{str});
    };
}

pub fn registerValidNeighbor(maxw: u32, maxh: u32, fields: *[][]BlockKind, neighbors: *std.ArrayList(Neighbor), x: i32, y: i32) void {
    if (x >= 0 and y >= 0 and x < maxw and y < maxh) {
        const xu: usize = @intCast(x);
        const yu: usize = @intCast(y);

        if (fields.*[xu][yu] == .WALL) {
            neighbors.appendAssumeCapacity(.{ .pos = IVec2{ .x = x, .y = y }, .distance = 0 });
            fields.*[xu][yu] = .AVAILABLE_NEIGHBOR;
        }
    }
}

pub fn registerValidNeighbors(maxw: u32, maxh: u32, pos: IVec2, fields: *[][]BlockKind, neighbors: *std.ArrayList(Neighbor)) void {
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

pub fn isConnectionUsable(maxw: u32, maxh: u32, fields: *[][]BlockKind, buffer: *[4]IVec2, count: usize, x: i32, y: i32) u1 {
    if (x >= 0 and y >= 0 and x < maxw and y < maxh) {
        const xu: usize = @intCast(x);
        const yu: usize = @intCast(y);

        if (fields.*[xu][yu] == .PASSAGE) {
            buffer[count] = IVec2{ .x = x, .y = y };
            return 1;
        }
    }

    return 0;
}

pub fn selectConnection(maxw: u32, maxh: u32, pos: IVec2, rnd: *const std.Random, fields: *[][]BlockKind) IVec2 {
    var buffer: [4]IVec2 = undefined;
    var cnt: usize = 0;

    cnt += isConnectionUsable(maxw, maxh, fields, &buffer, cnt, pos.x - 2, pos.y);
    cnt += isConnectionUsable(maxw, maxh, fields, &buffer, cnt, pos.x + 2, pos.y);
    cnt += isConnectionUsable(maxw, maxh, fields, &buffer, cnt, pos.x, pos.y - 2);
    cnt += isConnectionUsable(maxw, maxh, fields, &buffer, cnt, pos.x, pos.y + 2);

    //| Cannot connect if no passages are found
    //| AT LEAST one is needed each time!
    //| ---
    std.debug.assert(cnt > 0);
    const idx = rnd.uintLessThan(usize, cnt);

    return .{
        .x = (pos.x + buffer[idx].x) >> 1,
        .y = (pos.y + buffer[idx].y) >> 1,
    };
}

pub fn renderMaze(renderer: ?*sdl.SDL_Renderer, brickTextureSdl: [*c]sdl.SDL_Texture, maxw: u32, maxh: u32, fields: *[][]BlockKind, active: IVec2) void {
    const YELLOW_MARKER = sdl.SDL_Color{ .r = 213, .g = 224, .b = 56, .a = 127 };
    const PURPLE_MARKER = sdl.SDL_Color{ .r = 134, .g = 56, .b = 224, .a = 187 };
    const BROWN_PASSAGE = sdl.SDL_Color{ .r = 167, .g = 78, .b = 72, .a = 255 };

    for (0..maxh) |y| {
        for (0..maxw) |x| {
            const tgt = sdl.SDL_FRect{ .x = @floatFromInt(x * CELL_SIZE), .y = @floatFromInt(y * CELL_SIZE), .w = CELL_SIZE, .h = CELL_SIZE };

            if (fields.*[x][y] == .PASSAGE) {
                _ = sdl.SDL_SetRenderDrawColor(renderer, BROWN_PASSAGE.r, BROWN_PASSAGE.g, BROWN_PASSAGE.b, BROWN_PASSAGE.a);
                _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
            } else {
                _ = sdl.SDL_RenderTexture(renderer, brickTextureSdl, null, @ptrCast(&tgt));

                if (x == active.x and y == active.y) {
                    _ = sdl.SDL_SetRenderDrawColor(renderer, PURPLE_MARKER.r, PURPLE_MARKER.g, PURPLE_MARKER.b, PURPLE_MARKER.a);
                    _ = sdl.SDL_RenderFillRect(renderer, @ptrCast(&tgt));
                } else if (fields.*[x][y] == .AVAILABLE_NEIGHBOR) {
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
    pauseExecutionExplicit(io, PAUSE_MS);
}

pub fn generatePrimMazeAsync(io: std.Io, maxw: u32, maxh: u32, activePos: *IVec2, fields: *[][]BlockKind, rnd: *const std.Random, allocator: *std.mem.Allocator, animate: *bool) void {
    var neighbors = std.ArrayList(Neighbor).initCapacity(allocator.*, maxw * maxh) catch @panic("oom");

    for (0..maxh) |y| {
        for (0..maxw) |x| {
            fields.*[x][y] = .WALL;
        }
    }

    animate.* = true;

    //| All wall render
    //| ---
    pauseExecution(io);

    //| Entrance render
    //| ---
    fields.*[0][maxh - 2] = .PASSAGE;
    pauseExecution(io);

    //| Exit render
    //| ---
    fields.*[maxw - 1][1] = .PASSAGE;
    pauseExecution(io);

    var previousPos: IVec2 = undefined;
    activePos.* = IVec2{ .x = 1, .y = @intCast(maxh - 2) };
    registerValidNeighbors(maxw, maxh, activePos.*, fields, &neighbors);

    //| First field render
    //| ---
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

        fields.*[@intCast(activePos.x)][@intCast(activePos.y)] = .PASSAGE;
        previousPos = activePos.*;
        activePos.* = neighbors.items[idx].pos;

        const connectorPos = selectConnection(maxw, maxh, activePos.*, rnd, fields);
        fields.*[@intCast(connectorPos.x)][@intCast(connectorPos.y)] = .PASSAGE;

        //| Actual changes render
        //| ---
        pauseExecution(io);

        _ = neighbors.orderedRemove(idx);
        registerValidNeighbors(maxw, maxh, activePos.*, fields, &neighbors);
    }

    fields.*[@intCast(activePos.x)][@intCast(activePos.y)] = .PASSAGE; // last active position is stuck as neighbor

    //| Final render
    //| ---
    activePos.* = .{ .x = -1, .y = -1 };
    pauseExecution(io);

    //| Extra delay at the end
    //| ---
    pauseExecutionExplicit(io, 2000);
    animate.* = false;
}

pub fn main(args: std.process.Init) void {
    var cellCountHorizontal: u32 = DEFAULT_WIDTH;
    var cellCountVertical: u32 = DEFAULT_HEIGHT;
    var seed: u64 = DEFAULT_SEED;
    var saveFrames = false;

    var flags: u8 = 0;

    var argiterator = args.minimal.args.iterate();
    defer argiterator.deinit();

    while (argiterator.next()) |argZeroed| {
        const arg = std.mem.span(argZeroed.ptr);
        const expectSize = (flags & 0b1) != 0;
        const expectSeed = (flags & 0b10) != 0;

        if (expectSize) {
            const ws, const hs = std.mem.cut(u8, arg, "x") orelse usageError("Invalid --size parameter encountered `{s}`", .{arg});

            const wi = parseLengthValue(u32, ws);
            const hi = parseLengthValue(u32, hs);

            cellCountHorizontal = std.math.clamp(2 * wi + 1, @as(u32, 5), @as(u32, 153));
            cellCountVertical = std.math.clamp(2 * hi + 1, @as(u32, 5), @as(u32, 77));

            flags ^= 0b1;
            continue;
        } else if (expectSeed) {
            seed = parseLengthValue(u64, arg);

            flags ^= 0b10;
            continue;
        }

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            usage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--save")) {
            saveFrames = true;
        } else if (std.mem.eql(u8, arg, "--size")) {
            flags |= 0b1;
        } else if (std.mem.eql(u8, arg, "--seed")) {
            flags |= 0b10;
        }
    }

    if (flags != 0) {
        if (flags & 0b1 != 0) {
            usageError("No parameter was passed to --size flag", .{});
        } else if (flags & 0b10 != 0) {
            usageError("No parameter was passed to --seed flag", .{});
        }
    }

    if (saveFrames) {
        const cwd = std.Io.Dir.cwd();
        cwd.deleteTree(args.io, OUT_DIR) catch @panic("rmtreerr");
        cwd.createDirPath(args.io, OUT_DIR) catch @panic("mkdirerr");
    }

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS)) {
        fatal("Failed to initialize SDL3");
    }

    const windowWidth = cellCountHorizontal * CELL_SIZE;
    const windowHeight = cellCountVertical * CELL_SIZE;
    const window = sdl.SDL_CreateWindow("MazeGen", @intCast(windowWidth), @intCast(windowHeight), sdl.SDL_WINDOW_VULKAN);

    if (window == null) {
        fatal("Failed to create SDL3 window");
    }

    const renderer = sdl.SDL_CreateRenderer(window, null);

    if (renderer == null) {
        fatal("Failed to create SDL3 renderer");
    }

    const toggleVsync = sdl.SDL_SetRenderVSync(renderer, 1);
    const toggleBlending = sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND);

    if (!toggleVsync) {
        fatal("Failed to enable vsync");
    }

    if (!toggleBlending) {
        fatal("Failed to enable blending");
    }

    const brickSurfaceSdl = sdl.SDL_LoadBMP_IO(sdl.SDL_IOFromConstMem(&BrickDataBMP, BrickDataBMP.len), true);
    defer sdl.SDL_DestroySurface(brickSurfaceSdl);

    const brickTextureSdl = sdl.SDL_CreateTextureFromSurface(renderer, brickSurfaceSdl);
    defer sdl.SDL_DestroyTexture(brickTextureSdl);

    if (brickTextureSdl == null) {
        fatal("Failed to create brick texture");
    }

    var xoshiro = std.Random.DefaultPrng.init(seed);
    const rnd = xoshiro.random();

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    var isRunning: bool = true;
    var currentEvent: sdl.SDL_Event = undefined;
    var fields: [][]BlockKind = undefined;

    fields = allocator.alloc([]BlockKind, cellCountHorizontal) catch @panic("oom");

    for (0..fields.len) |i| {
        fields[i] = allocator.alloc(BlockKind, cellCountVertical) catch @panic("oom");
    }

    var activePos: IVec2 = .{ .x = -1, .y = -1 };
    var animatingFields: bool = false;
    var enableMazeRender: bool = false;
    var animateThread: std.Thread = undefined;
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

                            animateThread = std.Thread.spawn(
                                .{},
                                generatePrimMazeAsync,
                                .{ args.io, cellCountHorizontal, cellCountVertical, &activePos, &fields, &rnd, &allocator, &animatingFields },
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

            if (saveFrames and animatingFields) {
                //| You can use something like ffmpeg to merge the frames
                //| FPS is refresh rate when vsync is ON
                //| Delay is 1000ms / FPS, e.g. 7 (≈1000ms/144fps)
                //| ---
                //| ffmpeg -framerate 144 -i frames/frame_%05d.bmp -default_delay 7 -ignore_loop false -loop 0 -lossless 1 maze.webp

                const frame = sdl.SDL_RenderReadPixels(renderer, null);
                defer sdl.SDL_DestroySurface(frame);

                const outPath: [:0]const u8 = std.fmt.allocPrintSentinel(allocator, OUT_DIR ++ "frame_{d:0>5}.bmp", .{frameCount}, 0) catch @panic("oom");
                _ = sdl.SDL_SaveBMP(frame, outPath.ptr);

                frameCount += 1;
            }
        }

        _ = sdl.SDL_RenderPresent(renderer);
    }
}
