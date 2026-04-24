-- main.lua for the edgetest project. Loads three LDraw-
-- transpiled parts and draws their edges in four projections:
-- front, side, top, and an isometric wireframe.

-- Pull in the linear algebra library. It defines globals Vec
-- and Mat used by the drawing and transformation code below.
-- TOL is the numeric tolerance used by linalg for treating
-- near-zero values as zero.

TOL = 0.0005

dofile("linalg.lua")

local gfx = love.graphics

-- Quadrant centres on a 1024x600 display. Stored as plain
-- numeric coordinates rather than Vec instances: they are not
-- used in any matrix operation, only as offsets for rendering.

CENTER_TL_X, CENTER_TL_Y = 256, 150
CENTER_TR_X, CENTER_TR_Y = 768, 150
CENTER_BL_X, CENTER_BL_Y = 256, 450
CENTER_BR_X, CENTER_BR_Y = 768, 450

-- Global scale baked into the root matrix.

SCALE = 2

-- Shared empty function used for unimplemented DSL primitives
-- (line, tri, quad, outline, color_outline) and for sub-parts
-- whose transpiled chunks have not been loaded.

function empty_fn()
end

-- Build a scaled identity matrix: s*I with zero translation.

function make_scaled_identity(s)
  return Mat:new({
    Vec.d3(s, 0, 0),
    Vec.d3(0, s, 0),
    Vec.d3(0, 0, s)
  })
end

-- Stack of matrices. The bottom is a scaled identity that maps
-- LDU into screen units.

MATRIX_STACK = { make_scaled_identity(SCALE) }

function top_matrix()
  return MATRIX_STACK[#MATRIX_STACK]
end

-- Push a local matrix composed with the current top; pop
-- removes whatever is on top. linalg's Mat:mul composes only
-- the 3x3 rotation part; the affine translation is combined
-- here: new_t = M_outer * t_inner + t_outer.

-- Extract the 3x3 rotation part of an affine matrix as a new
-- Mat without the m[4] translation slot set.

function rot_part(m)
  return Mat:new({ m[1], m[2], m[3] })
end

-- Compose translation vectors for an affine product: the inner
-- translation is rotated by the outer matrix, then the outer
-- translation is added.

function compose_t(t_inner, rot_outer, t_outer)
  local t = Vec:new()
  if t_inner then
    t = t_inner:tr(rot_outer)
  end
  if t_outer then
    t:acc(t_outer)
  end
  return t
end

function compose_matrix(inner, outer)
  local rot_outer = rot_part(outer)
  local result = rot_part(inner):mul(rot_outer)
  result[4] = compose_t(inner[4], rot_outer, outer[4])
  return result
end

function push_matrix(m)
  table.insert(MATRIX_STACK, compose_matrix(m, top_matrix()))
end

function pop_matrix()
  table.remove(MATRIX_STACK)
end

-- Transform a local point into global coordinates by applying
-- the current top of the matrix stack. linalg's Vec:tr applies
-- only the 3x3 rotation; the translation stored in m[4] must
-- be added explicitly.

function apply_matrix(v)
  local m = top_matrix()
  local result = v:tr(m)
  if m[4] then
    result:acc(m[4])
  end
  return result
end

-- Draw an orthogonal projection: screen (x, y) come from the
-- 3D point's ix and iy components, offset by (cx, cy). Shared
-- by all three axis-aligned projections.

function draw_edge_ortho(p1, p2, cx, cy, ix, iy)
  local x1 = cx + p1:c(ix)
  local y1 = cy + p1:c(iy)
  local x2 = cx + p2:c(ix)
  local y2 = cy + p2:c(iy)
  gfx.line(x1, y1, x2, y2)
end

-- Factory for an orthogonal projection drawer with the given
-- centre coordinates and axis indices.

function make_ortho(cx, cy, ix, iy)
  return function(p1, p2)
    draw_edge_ortho(p1, p2, cx, cy, ix, iy)
  end
end

-- Isometric projection: x axis goes right, z axis goes left,
-- both axes also contribute half their length to y. This one
-- is not a simple ortho and has its own explicit formula.

function draw_edge_br(p1, p2)
  local a1, b1, c1 = p1:c3()
  local a2, b2, c2 = p2:c3()
  local x1 = CENTER_BR_X + a1 - c1
  local y1 = CENTER_BR_Y + b1 + 0.5 * (a1 + c1)
  local x2 = CENTER_BR_X + a2 - c2
  local y2 = CENTER_BR_Y + b2 + 0.5 * (a2 + c2)
  gfx.line(x1, y1, x2, y2)
end

-- Projection drawers keyed by quadrant. Front, side and top
-- are orthogonal and differ only in centre and axis indices;
-- isometric has its own dedicated function.

DRAW_EDGE = {
  make_ortho(CENTER_TL_X, CENTER_TL_Y, 1, 2),
  make_ortho(CENTER_TR_X, CENTER_TR_Y, 3, 2),
  make_ortho(CENTER_BL_X, CENTER_BL_Y, 1, 3),
  draw_edge_br
}

-- Draw a 3D edge through all configured projections.

function draw_edge_all(p1, p2)
  local g1 = apply_matrix(p1)
  local g2 = apply_matrix(p2)
  for i = 1, #DRAW_EDGE do
    DRAW_EDGE[i](g1, g2)
  end
end

-- The only drawing primitive implemented per the task. Other
-- primitives (line, tri, quad, outline, color_outline) resolve
-- via the _G metatable below to empty_fn.

function edge(x1, y1, z1, x2, y2, z2)
  draw_edge_all(Vec.d3(x1, y1, z1), Vec.d3(x2, y2, z2))
end

-- Invoke a sub-part with a matrix pushed onto the
-- transformation stack; pop after the call returns.

function invoke_sub(sub, m)
  push_matrix(m)
  sub()
  pop_matrix()
end

-- General reference with an arbitrary 3x3 rotation matrix
-- passed as nine numbers in row-major order (per LDraw spec),
-- plus translation. Transposed into column-major form on the
-- way in, because Vec:tr(m) interprets m[i] as the image of
-- the i-th basis vector.

function ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  local m = Mat:new({
    Vec.d3(a, d, g),
    Vec.d3(b, e, h),
    Vec.d3(c, f, i)
  })
  m[4] = Vec.d3(x, y, z)
  invoke_sub(sub, m)
end

-- Build a rotation around the Y axis from a complex number
-- (c, s) = (cos, sin) paired with a translation vector.
-- Stored in column-major form: m[i] is the image of the i-th
-- basis vector. Rotation by angle θ takes X into (c, 0, -s)
-- and Z into (s, 0, c).

function make_rot_y(tx, ty, tz, c, s)
  local m = Mat:new({
    Vec.d3(c, 0, -s),
    Vec.d3(0, 1, 0),
    Vec.d3(s, 0, c)
  })
  m[4] = Vec.d3(tx, ty, tz)
  return m
end

-- Factory for compass-direction placement: returns a function
-- that builds a rotation around Y by (cos, sin) and invokes
-- the sub-part under it. The colour q is accepted for
-- uniformity with ref but ignored in this iteration.

function make_place(c, s)
  return function(sub, q, x, y, z)
    invoke_sub(sub, make_rot_y(x, y, z, c, s))
  end
end

placeN = make_place(1, 0)
placeE = make_place(0, 1)
placeS = make_place(-1, 0)
placeW = make_place(0, -1)

-- Twist: rotation around Y by (cos a, sin c).

function twist(sub, q, x, y, z, a, c)
  invoke_sub(sub, make_rot_y(x, y, z, a, c))
end

-- Install a catch-all metatable on _G so references to unloaded
-- sub-parts and unimplemented primitives resolve to empty_fn.

setmetatable(_G, {
  __index = function()
    return empty_fn
  end
})

-- Load transpiled chunks.

dat_4865as01 = loadfile("dat_4865as01.lua")
dat_box5 = loadfile("dat_box5.lua")
dat_4865a = loadfile("dat_4865a.lua")

gfx.setColor(0, 0, 0)
dat_4865a()
