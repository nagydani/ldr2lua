-- main.lua for the edgetest project. Loads three LDraw-

-- transpiled parts and draws their edges in four projections:

-- front, side, top, and an isometric wireframe.

-- Pull in the vector and matrix libraries. They define globals

-- used by the drawing and transformation code below.

dofile("vec.lua")
dofile("mat.lua")

local gfx = love.graphics

-- Quadrant centers on a 1024x600 display.

CENTER_TL = vec_new(256, 150, 0)
CENTER_TR = vec_new(768, 150, 0)
CENTER_BL = vec_new(256, 450, 0)
CENTER_BR = vec_new(768, 450, 0)

-- Global scale baked into the root matrix.

SCALE = 2

-- Shared empty function used for unimplemented DSL primitives

-- (line, tri, quad, outline, color_outline) and for sub-parts

-- whose transpiled chunks have not been loaded.

function empty_fn()
  
end

-- Stack of matrices. The bottom is a scaled identity that maps

-- LDU into screen units.

MATRIX_STACK = { mat_scaled_identity(SCALE) }

function top_matrix()
  return MATRIX_STACK[#MATRIX_STACK]
end

-- Push a local matrix composed with the current top; pop

-- removes whatever is on top.

function push_matrix(m)
  local composed = mat_compose(top_matrix(), m)
  table.insert(MATRIX_STACK, composed)
end

function pop_matrix()
  table.remove(MATRIX_STACK)
end

-- Transform a local point into global coordinates by applying

-- the current top of the matrix stack.

function apply_matrix(v)
  return mat_apply(top_matrix(), v)
end

-- Projection drawers. Each takes two 3D points already in

-- global coordinates and projects them onto a 2D plane, offset

-- by the centre of its quadrant.

-- Draw an orthogonal projection: screen (x, y) come from the

-- 3D point's ix and iy components, offset by centre. Shared by

-- all three axis-aligned projections.

function draw_edge_ortho(p1, p2, centre, ix, iy)
  local x1 = centre[1] + p1[ix]
  local y1 = centre[2] + p1[iy]
  local x2 = centre[1] + p2[ix]
  local y2 = centre[2] + p2[iy]
  gfx.line(x1, y1, x2, y2)
end

-- Factory for an orthogonal projection drawer with the given

-- centre and axis indices.

function make_ortho(centre, ix, iy)
  return function(p1, p2)
    draw_edge_ortho(p1, p2, centre, ix, iy)
  end
end

-- Isometric projection: x axis goes right, z axis goes left,

-- both axes also contribute half their length to y. This one

-- is not a simple ortho and has its own explicit formula.

function draw_edge_br(p1, p2)
  local x1 = CENTER_BR[1] + p1[1] - p1[3]
  local y1 = CENTER_BR[2] + p1[2] + 0.5 * (p1[1] + p1[3])
  local x2 = CENTER_BR[1] + p2[1] - p2[3]
  local y2 = CENTER_BR[2] + p2[2] + 0.5 * (p2[1] + p2[3])
  gfx.line(x1, y1, x2, y2)
end

-- Projection drawers keyed by quadrant. Front, side and top

-- are orthogonal and differ only in centre and axis indices;

-- isometric has its own dedicated function.

DRAW_EDGE = {
  make_ortho(CENTER_TL, 1, 2),
  make_ortho(CENTER_TR, 3, 2),
  make_ortho(CENTER_BL, 1, 3),
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
  draw_edge_all(vec_new(x1, y1, z1), vec_new(x2, y2, z2))
end

-- Invoke a sub-part with a matrix pushed onto the

-- transformation stack; pop after the call returns.

function invoke_sub(sub, m)
  push_matrix(m)
  sub()
  pop_matrix()
end

-- Transformation DSL. Each function builds a matrix and invokes

-- the sub-part under it.

function ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  local r1 = vec_new(a, b, c)
  local r2 = vec_new(d, e, f)
  local r3 = vec_new(g, h, i)
  local t = vec_new(x, y, z)
  invoke_sub(sub, mat_from_rot(r1, r2, r3, t))
end

-- Compass-direction placements: 90-degree rotations around Y.

-- Factory for compass-direction placements: returns a function
-- that forwards to ref with the given nine-element rotation.

function make_place(a, b, c, d, e, f, g, h, i)
  return function(sub, q, x, y, z)
    ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  end
end

placeN = make_place(1, 0, 0, 0, 1, 0, 0, 0, 1)
placeE = make_place(0, 0, 1, 0, 1, 0, -1, 0, 0)
placeS = make_place(-1, 0, 0, 0, 1, 0, 0, 0, -1)
placeW = make_place(0, 0, -1, 0, 1, 0, 1, 0, 0)

-- Twist: rotation around Y by (cos a, sin c). Other rows

-- are the identity along Y.

function twist(sub, q, x, y, z, a, c)
  ref(sub, q, x, y, z, a, 0, c, 0, 1, 0, -c, 0, a)
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
