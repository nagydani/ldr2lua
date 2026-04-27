-- main.lua for the edgetest project. Loads the transpiled
-- pyramid model and renders it in four projections: front,
-- side, top, and isometric. Geometry is processed once per
-- projection by re-invoking ldr_pyramid with a different
-- pluggable project(x, y, z) function each time.

-- Pull in the linear algebra library through require so it
-- caches and is loaded once. TOL must be set first because
-- linalg uses it during initialisation.

TOL = 0.0005

require "linalg"

local gfx = love.graphics

-- Global transformation: M is the 3x3 rotation/orientation
-- matrix, T is the 3d translation. A point v in local space
-- is mapped to global space as M*v + T. ref-style functions
-- save these into locals, update them for the sub-tree, and
-- restore on return. There is no matrix stack.

M = Mat.unit(3)
T = Vec.d3(0, 0, 0)

-- Shared no-op used by the _G fallback metatable for any DSL
-- function that is not implemented in this iteration.

function empty_fn()
  
end

-- Apply M and T to a local 3d point, returning the global
-- point as a Vec.

function apply_global(p)
  local g = p:tr(M)
  g:acc(T)
  return g
end

-- Drawing primitives. They consult the current pluggable
-- project(x, y, z) function to obtain 2d screen coordinates.

function edge(x1, y1, z1, x2, y2, z2)
  local g1 = apply_global(Vec.d3(x1, y1, z1))
  local g2 = apply_global(Vec.d3(x2, y2, z2))
  local sx1, sy1 = project(g1:c3())
  local sx2, sy2 = project(g2:c3())
  gfx.line(sx1, sy1, sx2, sy2)
end

-- Conditional line: draw the segment p1-p2 only if the
-- projections of p3 and p4 lie on the same side of the line
-- through the projections of p1 and p2. Sign agreement of
-- two cross products gives the answer.

function same_side(ax, ay, bx, by, cx, cy, dx, dy)
  local vx, vy = bx - ax, by - ay
  local s1 = vx * (cy - ay) - vy * (cx - ax)
  local s2 = vx * (dy - ay) - vy * (dx - ax)
  return 0 <= s1 * s2
end

function outline(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4)
  local g1 = apply_global(Vec.d3(x1, y1, z1))
  local g2 = apply_global(Vec.d3(x2, y2, z2))
  local g3 = apply_global(Vec.d3(x3, y3, z3))
  local g4 = apply_global(Vec.d3(x4, y4, z4))
  local sx1, sy1 = project(g1:c3())
  local sx2, sy2 = project(g2:c3())
  local sx3, sy3 = project(g3:c3())
  local sx4, sy4 = project(g4:c3())
  if same_side(sx1, sy1, sx2, sy2, sx3, sy3, sx4, sy4) then
    gfx.line(sx1, sy1, sx2, sy2)
  end
end

-- Sub-tree invocation. Save M and T into locals, update for
-- the sub-tree, call sub, and restore on return. This is the
-- explicit save/restore replacement for the matrix stack.

-- Common save/restore wrapper used by every reference-style
-- DSL function. The updater builds the new M and T given the
-- previous ones; this function takes care of save/call/restore.

function with_frame(updater, sub)
  local oldM = M
  local oldT = T
  updater(oldM, oldT)
  sub()
  M = oldM
  T = oldT
end

-- Compute the new T given the previous M and T plus a local
-- translation (tx, ty, tz). The local translation is rotated
-- into global space by the previous M and added to the
-- previous T.

function step_translation(oldM, oldT, tx, ty, tz)
  local local_t = Vec.d3(tx, ty, tz)
  local global_step = local_t:tr(oldM)
  global_step:acc(oldT)
  return global_step
end

-- placeN: identity rotation, only translation changes. M is
-- left untouched; T is updated.

function placeN(sub, q, x, y, z)
  with_frame(function(oldM, oldT)
    T = step_translation(oldM, oldT, x, y, z)
  end, sub)
end

-- Apply an orthogonal transformation by index from the
-- orthogonal_base table. Updates both M and T for the
-- sub-tree. Shared by the named compass and mirror placements
-- and by the general place(... i).

function apply_orthogonal(sub, x, y, z, i)
  with_frame(function(oldM, oldT)
    local o = Mat.unit(3):orthogonal3(i)
    M = o:mul(oldM)
    T = step_translation(oldM, oldT, x, y, z)
  end, sub)
end

-- Factory for compass-direction and mirror placements that
-- correspond to a fixed orthogonal_base index.

function make_orthogonal_place(i)
  return function(sub, q, x, y, z)
    apply_orthogonal(sub, x, y, z, i)
  end
end

placeS = make_orthogonal_place(5)
placeW = make_orthogonal_place(17)
placeE = make_orthogonal_place(20)
mirrorEW = make_orthogonal_place(1)
mirrorUD = make_orthogonal_place(2)
mirrorNS = make_orthogonal_place(4)

-- General orthogonal placement with a runtime-supplied index
-- from the orthogonal_base table.

function place(sub, q, x, y, z, i)
  apply_orthogonal(sub, x, y, z, i)
end

-- Diagonal stretch: scale the local axes by (a, e, i) before
-- composing into the parent frame.

function stretch(sub, q, x, y, z, a, e, i)
  with_frame(function(oldM, oldT)
    local s = Mat:new({
      Vec.d3(a, 0, 0),
      Vec.d3(0, e, 0),
      Vec.d3(0, 0, i)
    })
    M = s:mul(oldM)
    T = step_translation(oldM, oldT, x, y, z)
  end, sub)
end

-- Twist: rotation around Y by (cos a, sin c). Build the
-- rotation matrix from a column-major layout: m[i] is the
-- image of the i-th basis vector.

function make_twist_mat(a, c)
  return Mat:new({
    Vec.d3(a, 0, -c),
    Vec.d3(0, 1, 0),
    Vec.d3(c, 0, a)
  })
end

function twist(sub, q, x, y, z, a, c)
  with_frame(function(oldM, oldT)
    M = make_twist_mat(a, c):mul(oldM)
    T = step_translation(oldM, oldT, x, y, z)
  end, sub)
end

-- General reference: arbitrary 3x3 rotation matrix from nine
-- numbers in row-major LDraw order, transposed to column-
-- major as linalg expects (m[i] is the image of basis i).

function make_ref_mat(a, b, c, d, e, f, g, h, i)
  return Mat:new({
    Vec.d3(a, d, g),
    Vec.d3(b, e, h),
    Vec.d3(c, f, i)
  })
end

function ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  with_frame(function(oldM, oldT)
    M = make_ref_mat(a, b, c, d, e, f, g, h, i):mul(oldM)
    T = step_translation(oldM, oldT, x, y, z)
  end, sub)
end

-- Install a catch-all metatable on _G so references to DSL
-- primitives and meta commands that are not implemented in this
-- iteration (line, tri, quad, color_outline, STEP, CLEAR,
-- LDRAW_ORG, KEYWORD, etc.) resolve to empty_fn.

setmetatable(_G, {
  __index = function()
    return empty_fn
  end
})

-- Pluggable projection. Each draw-time function must define
-- this global before invoking the model. The projection takes
-- a 3d point and returns 2d screen coordinates.

-- Quadrant centres on the 1024x600 display.

CENTER_TL_X, CENTER_TL_Y = 256, 150
CENTER_TR_X, CENTER_TR_Y = 768, 150
CENTER_BL_X, CENTER_BL_Y = 256, 450
CENTER_BR_X, CENTER_BR_Y = 768, 450

-- Global scale that maps LDU into screen units.

SCALE = 1

function project_front(x, y, z)
  return CENTER_TL_X + SCALE * x, CENTER_TL_Y + SCALE * y
end

function project_side(x, y, z)
  return CENTER_TR_X + SCALE * z, CENTER_TR_Y + SCALE * y
end

function project_top(x, y, z)
  return CENTER_BL_X + SCALE * x, CENTER_BL_Y + SCALE * z
end

function project_iso(x, y, z)
  local sx = CENTER_BR_X + SCALE * (x - z)
  local sy = CENTER_BR_Y + SCALE * (y + 0.5 * (x + z))
  return sx, sy
end

PROJECTIONS = {
  project_front,
  project_side,
  project_top,
  project_iso
}

-- Reset the global frame to the identity orientation and zero
-- translation. Called between projection passes.

function reset_frame()
  M = Mat.unit(3)
  T = Vec.d3(0, 0, 0)
end

-- Load all transpiled sub-part chunks. Each dat_*.lua file in
-- the project directory becomes a global function with the
-- same name (sans extension). The pyramid model references
-- them by name through ref / placeN / etc., so they must be
-- loaded before the model is invoked.

DAT_FILES = {
  "dat_3001",
  "dat_3001s01",
  "dat_3003",
  "dat_3003s01",
  "dat_3003s02",
  "dat_4_4cyli",
  "dat_4_4disc",
  "dat_4_4edge",
  "dat_4_4ring3",
  "dat_box3u2p",
  "dat_box5",
  "dat_stud",
  "dat_stud4",
  "dat_stug_2x2"
}

for i = 1, #DAT_FILES do
  local name = DAT_FILES[i]
  _G[name] = loadfile(name .. ".lua")
end

-- Load the transpiled pyramid model.

ldr_pyramid = loadfile("ldr_pyramid.lua")

gfx.setColor(0, 0, 0)

for i = 1, #PROJECTIONS do
  reset_frame()
  project = PROJECTIONS[i]
  ldr_pyramid()
end

