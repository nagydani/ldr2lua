# LDraw to Lua Transpiler

First iteration. Converts LDraw part files (`.dat`/`.ldr`/`.mpd`)
into Lua chunks that run on the Compy platform and render wireframe
projections of LEGO-compatible parts.

## How it works

LDraw parts are transpiled ahead of time into Lua chunks that call
a small drawing DSL. At runtime the Compy project loads the chunks
and invokes the root chunk to draw the part.

A stack of 3x4 transformation matrices tracks the coordinate
system through sub-part references. `ref` composes a new matrix
on top of the stack, calls the sub-chunk, then pops.
`placeN`/`E`/`S`/`W` and `twist` are specialisations of `ref` for
common rotation shapes, emitted whenever the transformation matrix
matches.

The edgetest project renders part 4865a (1x2x1 panel) across four
projections: front (top-left), side (top-right), top (bottom-left),
isometric (bottom-right). Per the first-iteration specification,
only the `edge` drawing primitive is implemented. Other drawing
primitives (`line`, `tri`, `quad`, `outline`, `color_outline`)
resolve via a `_G` metatable to an empty function and will be
added in later iterations.

## Repository layout

    ldraw_transpile.lua     -- the transpiler
    compy/
      edgetest/             -- edgetest project for the Compy runtime
        main.lua            -- entry point
        vec.lua             -- 3D vector operations
        mat.lua             -- 3x4 matrix operations
    README.md
    .gitignore

LDraw library files (`.dat`/`.ldr`/`.mpd`) and transpiler output
(`compy/*/dat_*.lua`) are not tracked; see `.gitignore`.

## Building

The transpiler writes its output to whatever path is given on the
command line. To prepare the edgetest project, transpile the three
test parts from the LDraw library into `compy/edgetest/`:

    lua ldraw_transpile.lua parts/4865a.dat \
      compy/edgetest/dat_4865a.lua
    lua ldraw_transpile.lua parts/s/4865as01.dat \
      compy/edgetest/dat_4865as01.lua
    lua ldraw_transpile.lua parts/p/box5.dat \
      compy/edgetest/dat_box5.lua

The complete LDraw parts library is available at
<https://library.ldraw.org/library/updates/complete.zip>.

## Running

Open `compy/edgetest/` as a project in Compy; its `main.lua`
loads the three transpiled chunks and invokes the root. The
wireframe of the panel renders in all four quadrants.

## DSL reference

Transpiled chunks call these globals, all defined in `main.lua`
(or resolved via the `_G` metatable to `empty_fn` when not
implemented).

Drawing primitive:

- `edge(x1, y1, z1, x2, y2, z2)` — line with default colour 24.

Unimplemented in this iteration (resolved to no-op):
`line`, `tri`, `quad`, `outline`, `color_outline`.

Sub-part references:

- `ref(sub, q, tx, ty, tz, m1..m9)` — arbitrary 3x3 rotation
  plus translation.
- `placeN`/`E`/`S`/`W`(sub, q, tx, ty, tz)` — 90-degree
  rotations around the Y axis.
- `twist(sub, q, tx, ty, tz, a, c)` — Y-axis rotation by
  (cos a, sin c).

Meta commands (from Type 0 lines):

- `STEP`, `CLEAR`, `PAUSE`, `SAVE`, `WRITE`, `PRINT`. No-ops at
  runtime in this iteration.

## Specification coverage

Implemented from the LDraw file spec
(<https://www.ldraw.org/article/218.html>):

- Type 0: `STEP`/`CLEAR`/`PAUSE`/`SAVE`/`WRITE`/`PRINT` meta
  dispatch through parallel pattern/handler tables; all other
  lines become comments, word-wrapped at column 64 with a two-
  space continuation indent.
- Type 1: matrix shape dispatch for `placeN`/`E`/`S`/`W`,
  `twist`, and the general `ref` form. Reference prefix
  stripping (`s\`, `p\`) and name mangling
  (`name.ext` -> `ext_name`).
- Type 2: `edge` (colour 24) and `line` (explicit colour).
- Type 3: `tri`.
- Type 4: `quad`.
- Type 5: `outline` (colour 24) and `color_outline`.
- Blank line collapsing.
