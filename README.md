# LDraw to Lua Transpiler

First iteration. Converts LDraw part files (`.dat`/`.ldr`/`.mpd`)
into Lua chunks that run on the Compy platform and render wireframe
projections of LEGO-compatible parts.

## How it works

LDraw parts are transpiled ahead of time into Lua chunks that call a
small drawing DSL (`edge`, `line`, `tri`, `quad`, `outline`,
`color_outline`, `ref`, `placeN`/`E`/`S`/`W`, `twist`). At runtime
`main.lua` loads the chunks and invokes the root chunk to draw the
part.

A 3x4 matrix stack tracks transformations through sub-part
references. `ref` composes a new matrix on top of the stack, calls
the sub-chunk, then pops. `placeN`/`E`/`S`/`W` and `twist` are
specializations of `ref` for common rotation shapes, emitted when
the transformation matrix matches.

The test scene renders one part (4865a — 1x2x1 panel) across four
projections: front (top-left), side (top-right), top (bottom-left),
isometric (bottom-right).

## Files

- `ldraw_transpile.lua` — the transpiler. Standalone Lua 5.1 script,
  runs outside Compy.
- `main.lua` — the Compy-side runtime. Defines DSL functions, loads
  transpiled chunks, invokes the root chunk.
- `dat_4865a.lua`, `dat_4865as01.lua`, `dat_box5.lua` — transpiled
  parts from the LDraw library.

## Building

Run the transpiler once per source file:

    lua ldraw_transpile.lua input.dat output.lua

For the test scene:

    lua ldraw_transpile.lua parts/4865a.dat      dat_4865a.lua
    lua ldraw_transpile.lua parts/s/4865as01.dat dat_4865as01.lua
    lua ldraw_transpile.lua parts/p/box5.dat     dat_box5.lua

The complete LDraw parts library is available at
<https://library.ldraw.org/library/updates/complete.zip>.

## Running

Place `main.lua` and the three `dat_*.lua` files in the Compy
project directory, then in the Compy REPL:

    dofile("main.lua")

The screen shows the wireframe of the panel in all four projections.

## DSL reference

Transpiled chunks call these globals, all defined in `main.lua`.

Drawing primitives:

- `edge(x1, y1, z1, x2, y2, z2)` — line with default colour 24.
- `line(q, x1, y1, z1, x2, y2, z2)` — line with explicit colour `q`.
- `tri(q, x1, y1, z1, x2, y2, z2, x3, y3, z3)` — triangle outline.
- `quad(q, x1..z1, x2..z2, x3..z3, x4..z4)` — quadrilateral.
- `outline(...)` / `color_outline(q, ...)` — optional edges.

Sub-part references:

- `ref(sub, q, tx, ty, tz, m1..m9)` — arbitrary 3x3 rotation +
  translation.
- `placeN`/`E`/`S`/`W`(sub, q, tx, ty, tz)` — compass rotations
  around the Y axis.
- `twist(sub, q, tx, ty, tz, a, c)` — Y-axis rotation by (cos a,
  sin c).

Meta commands (from Type 0 lines):

- `STEP`, `CLEAR`, `PAUSE`, `SAVE`, `WRITE`, `PRINT`. In the first
  iteration these are runtime no-ops; the machinery is in place for
  later iterations.

## Specification coverage

Implemented from the LDraw file spec
(<https://www.ldraw.org/article/218.html>):

- Type 0: `STEP`/`CLEAR`/`PAUSE`/`SAVE`/`WRITE`/`PRINT` handlers,
  everything else transpiled as a comment. Word-wrapped at column 64
  with two-space continuation indent.
- Type 1: matrix dispatch for `placeN`/`E`/`S`/`W`/`twist`/`ref`,
  reference prefix stripping (`s\`, `p\`, etc.), name mangling
  (`name.ext` → `ext_name`).
- Type 2: `edge`/`line` by colour.
- Type 3: `tri`.
- Type 4: `quad`.
- Type 5: `outline`/`color_outline` by colour.
- Blank line collapsing.
