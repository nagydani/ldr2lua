-- main.lua

-- Application: load three LDraw-transpiled parts

-- and draw three principal projections plus an

-- isometric wireframe.

local gfx = love.graphics

-- Quadrant centers on a 1024x600 display.

CENTER_TL_X = 256
CENTER_TL_Y = 150
CENTER_TR_X = 768
CENTER_TR_Y = 150
CENTER_BL_X = 256
CENTER_BL_Y = 450
CENTER_BR_X = 768
CENTER_BR_Y = 450

-- Global scale baked into the root matrix.

SCALE = 2

-- Shared empty function used for META no-ops.

function empty_fn()
  
end

-- Build a scale-times-identity matrix with zero

-- translation; seeds the bottom of MATRIX_STACK.

function init_matrix()
  local m = { }
  m[1], m[2], m[3] = SCALE, 0, 0
  m[4], m[5], m[6] = 0, SCALE, 0
  m[7], m[8], m[9] = 0, 0, SCALE
  m[10], m[11], m[12] = 0, 0, 0
  return m
end

-- Stack of 3x4 transformation matrices.

MATRIX_STACK = { init_matrix() }

function top_matrix()
  return MATRIX_STACK[#MATRIX_STACK]
end

-- Apply the current top matrix to local (x, y, z)

-- and return the global (u, v, w) as three values.

function apply_matrix(x, y, z)
  local m = top_matrix()
  local u = m[1] * x + m[2] * y + m[3] * z + m[10]
  local v = m[4] * x + m[5] * y + m[6] * z + m[11]
  local w = m[7] * x + m[8] * y + m[9] * z + m[12]
  return u, v, w
end

-- Compose two 3x4 matrices: result = m1 * m2.

function compose_rotation(m1, m2, result)
  for row = 0, 2 do
    for col = 0, 2 do
      local sum = 0
      for k = 0, 2 do
        sum = sum + m1[1 + row * 3 + k] * m2[1 + k * 3 + col]
      end
      result[1 + row * 3 + col] = sum
    end
  end
end

function compose_translation(m1, m2, result)
  for row = 0, 2 do
    local b = 1 + row * 3
    local s1 = m1[b] * m2[10]
    local s2 = m1[b + 1] * m2[11]
    local s3 = m1[b + 2] * m2[12]
    result[10 + row] = s1 + s2 + s3 + m1[10 + row]
  end
end

function compose_matrices(m1, m2)
  local result = { }
  compose_rotation(m1, m2, result)
  compose_translation(m1, m2, result)
  return result
end

function push_matrix(m)
  local composed = compose_matrices(top_matrix(), m)
  table.insert(MATRIX_STACK, composed)
end

function pop_matrix()
  table.remove(MATRIX_STACK)
end

-- Projection drawers. Each takes flat coordinates

-- from the transformed point (no table allocations).

function draw_edge_tl(u1, v1, u2, v2)
  local x1 = CENTER_TL_X + u1
  local y1 = CENTER_TL_Y + v1
  local x2 = CENTER_TL_X + u2
  local y2 = CENTER_TL_Y + v2
  gfx.line(x1, y1, x2, y2)
end

function draw_edge_tr(w1, v1, w2, v2)
  local x1 = CENTER_TR_X + w1
  local y1 = CENTER_TR_Y + v1
  local x2 = CENTER_TR_X + w2
  local y2 = CENTER_TR_Y + v2
  gfx.line(x1, y1, x2, y2)
end

function draw_edge_bl(u1, w1, u2, w2)
  local x1 = CENTER_BL_X + u1
  local y1 = CENTER_BL_Y + w1
  local x2 = CENTER_BL_X + u2
  local y2 = CENTER_BL_Y + w2
  gfx.line(x1, y1, x2, y2)
end

function draw_edge_br(u1, v1, w1, u2, v2, w2)
  local x1 = CENTER_BR_X + u1 - w1
  local y1 = CENTER_BR_Y + v1 + 0.5 * (u1 + w1)
  local x2 = CENTER_BR_X + u2 - w2
  local y2 = CENTER_BR_Y + v2 + 0.5 * (u2 + w2)
  gfx.line(x1, y1, x2, y2)
end

-- Draw a 3D edge through all four projections.

function draw_edge_all(x1, y1, z1, x2, y2, z2)
  local u1, v1, w1 = apply_matrix(x1, y1, z1)
  local u2, v2, w2 = apply_matrix(x2, y2, z2)
  draw_edge_tl(u1, v1, u2, v2)
  draw_edge_tr(w1, v1, w2, v2)
  draw_edge_bl(u1, w1, u2, w2)
  draw_edge_br(u1, v1, w1, u2, v2, w2)
end

-- DSL functions as globals. They take flat coords

-- and forward to draw_edge_all with no allocations.

function edge(x1, y1, z1, x2, y2, z2)
  draw_edge_all(x1, y1, z1, x2, y2, z2)
end

function line(q, x1, y1, z1, x2, y2, z2)
  draw_edge_all(x1, y1, z1, x2, y2, z2)
end

function tri(q, x1, y1, z1, x2, y2, z2, x3, y3, z3)
  draw_edge_all(x1, y1, z1, x2, y2, z2)
  draw_edge_all(x2, y2, z2, x3, y3, z3)
  draw_edge_all(x3, y3, z3, x1, y1, z1)
end

function quad(q, x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4)
  draw_edge_all(x1, y1, z1, x2, y2, z2)
  draw_edge_all(x2, y2, z2, x3, y3, z3)
  draw_edge_all(x3, y3, z3, x4, y4, z4)
  draw_edge_all(x4, y4, z4, x1, y1, z1)
end

function outline(x1, y1, z1, x2, y2, z2, ...)
  draw_edge_all(x1, y1, z1, x2, y2, z2)
end

function color_outline(q, x1, y1, z1, x2, y2, z2, ...)
  draw_edge_all(x1, y1, z1, x2, y2, z2)
end

-- Invoke a sub-part with a matrix pushed onto the

-- transformation stack; pop after the call returns.

function invoke_sub(sub, matrix)
  push_matrix(matrix)
  sub()
  pop_matrix()
end

-- Build a 3x4 matrix from a 9-element rotation

-- table and a translation (tx, ty, tz).

function make_matrix(rot, tx, ty, tz)
  local m = { }
  m[1], m[2], m[3] = rot[1], rot[2], rot[3]
  m[4], m[5], m[6] = rot[4], rot[5], rot[6]
  m[7], m[8], m[9] = rot[7], rot[8], rot[9]
  m[10], m[11], m[12] = tx, ty, tz
  return m
end

-- Build a 9-element rotation table from flat values.

function build_rot(r1, r2, r3, r4, r5, r6, r7, r8, r9)
  local r = { }
  r[1], r[2], r[3] = r1, r2, r3
  r[4], r[5], r[6] = r4, r5, r6
  r[7], r[8], r[9] = r7, r8, r9
  return r
end

-- ref: full sub-file reference with arbitrary matrix.

function ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  local rot = build_rot(a, b, c, d, e, f, g, h, i)
  invoke_sub(sub, make_matrix(rot, x, y, z))
end

-- placeN/E/S/W: identity/rotated compass placement.

function placeN(sub, q, x, y, z)
  local rot = build_rot(1, 0, 0, 0, 1, 0, 0, 0, 1)
  invoke_sub(sub, make_matrix(rot, x, y, z))
end

function placeE(sub, q, x, y, z)
  local rot = build_rot(0, 0, 1, 0, 1, 0, -1, 0, 0)
  invoke_sub(sub, make_matrix(rot, x, y, z))
end

function placeS(sub, q, x, y, z)
  local rot = build_rot(-1, 0, 0, 0, 1, 0, 0, 0, -1)
  invoke_sub(sub, make_matrix(rot, x, y, z))
end

function placeW(sub, q, x, y, z)
  local rot = build_rot(0, 0, -1, 0, 1, 0, 1, 0, 0)
  invoke_sub(sub, make_matrix(rot, x, y, z))
end

-- twist: rotation around Y by cosine a and sine c.

function twist(sub, q, x, y, z, a, c)
  local rot = build_rot(a, 0, c, 0, 1, 0, -c, 0, a)
  invoke_sub(sub, make_matrix(rot, x, y, z))
end

-- Install a catch-all metatable on _G so references

-- to unloaded sub-parts resolve to empty_fn.

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
