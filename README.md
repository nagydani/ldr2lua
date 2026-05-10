# LDraw to Lua Transpiler

Converts LDraw files into Lua chunks for the Compy edgetest
runtime. Picking accelerated with per-Part bounding spheres and
optional back-face culling.

## Layout

    ldraw_transpile.lua
    orthogonal_bases.lua
    transpiler/
      util.lua
      emit.lua
      types.lua
      colors.lua
      base64.lua
      mpd.lua
      ldraw_color_id.lua
    compy/
      edgetest/
        main.lua
        linalg.lua
        ldraw.lua
        bfc.lua
        picking.lua
        ldraw_colors.lua

Generated model chunks are not tracked. Regenerate them from a
local LDraw library before running the Compy project.

## Transpiler

Run:

    lua ldraw_transpile.lua input.ldr output.lua

The transpiler handles Type 0 colour/category/keyword and BFC
metas, Type 1 matrix dispatch, Types 2-5 drawing calls,
identifier mangling, MPD `FILE`/`NOFILE` blocks, and MPD
`!DATA` base64 payloads.

Colour indices are resolved through
`transpiler/ldraw_color_id.lua`. Generated chunks use colour
symbols such as `Blue`, `MAIN_COLOR`, and `EDGE_COLOR` instead
of numeric LDraw colour codes. Unknown colour codes stop the
transpiler with an error.

`LDConfig.ldr` colour definitions are committed as
`compy/edgetest/ldraw_colors.lua`. Runtime code requires this
file before loading `ldraw.lua`.

BFC metas transpile to runtime calls. `0 BFC CERTIFY CCW`
becomes `BFC_CERTIFY(1)`; `0 BFC CW` becomes `BFC(-1)`; and so
on for `BFC_NOCERTIFY`, `BFC_CLIP`, `BFC_NOCLIP`. The
`INVERTNEXT` meta wraps the next Type 1 dispatch in
`BFC_INVERT(...)`. Both spec orderings of `CW CLIP` /
`CLIP CW` are accepted.

## Runtime

`compy/edgetest/ldraw.lua` owns LDraw tree traversal. It
carries the current transformation matrix `M`, displacement
vector `T`, `MAIN_COLOR`, and `EDGE_COLOR` through sub-tree
calls. Each pass installs its own callbacks for the DSL names
plus three traversal hooks: `enter_ref(sub, q, m, t)`,
`leave_ref(saved)`, and `call(sub)`. The `call` hook decides
whether to descend into the sub-tree.

The drawing surface is controlled by a perspective projection
centered on the screen:

    local dz = D / z
    return CENTER_X + x * dz, CENTER_Y + y * dz

Only `edge` and `outline` draw in this iteration. `line`,
`tri`, `quad`, colour outlines, and remaining metas are
no-ops.

`compy/edgetest/picking.lua` casts a ray against the model and
returns the nearest Part hit. It computes a squared bounding
sphere radius for every Part chunk at load time and uses
`call(sub)` to skip a Part whose sphere does not intersect the
ray. Within a Part, BFC discards back-facing tri/quad before
the barycentric test, when the Part's BFC state is certified
and clipping is on.

`compy/edgetest/bfc.lua` holds the BFC state: per-file
`certified`, `winding`, `local_cull`; accumulated
`accum_cull`, `outer_sign`. `bfc_enter` snapshots the state
and flips `outer_sign` when the matrix has negative
determinant; `bfc_leave` restores. `BFC_INVERT(f)` flips
`outer_sign` for the duration of the wrapped call.

## Test Model

The edgetest project uses the pyramid model and its required
parts/primitives from a local LDraw library. Regenerate the
chunks under `compy/edgetest/` before copying the project to
Compy.
