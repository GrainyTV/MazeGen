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
4. Compile the project using Zig 0.16
```
zig build -Dtarget=x86_64-linux-gnu
```

## How to Use
When the application starts, it will default to an empty gray window. If you press `SPACE` the animation will start and the rendered frames will be saved to a folder in the working directory. If you are done you can terminate both the recording and the application using either the `ESC` or `Q` keys.
