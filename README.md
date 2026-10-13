# MazeGen

Fancy maze generation animation based on [Prim's modified algorithm](https://en.wikipedia.org/wiki/Maze_generation_algorithm#Modified_version) using SDL3.

## Showcase

![mazegen-animation](assets/maze.apng)

## How to Build

Make sure your system has SDL3 installed. On Arch Linux you can install it like this:

```
pacman -S sdl3
```

1. Clone the repository to your machine
   
   ```
   git clone https://github.com/GrainyTV/MazeGen.git
   ```

2. Navigate to the folder
   
   ```
   cd MazeGen
   ```

3. Compile the project using Zig 0.16
   
   ```
   zig build -Dtarget=x86_64-linux-gnu
   ```

## How to Use

By default the application will start with an empty gray window.

<kbd>Space</kbd> starts the animation

<kbd>Esc</kbd> or <kbd>Q</kbd> terminates the application

You can also specify a couple of flags to modify the default behavior.

```
usage: ./MazeGen [OPTIONS]

OPTIONS
  -h, --help      shows this help message and terminates
  --size <NxM>    specifies alternative maze size using formula 2*(N|M)+1, where N[2..76] and M[2..38]
                  (Default: 16x4)
  --seed <seed>   specifies unsigned 64 bit number to use with random generation
                  (Default: 69420)
  --save          enables saving animation frames to an output directory
```
