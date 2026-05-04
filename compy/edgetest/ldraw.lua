-- LDraw tree traversal runtime.

local M = Mat.unit(3)
local T = Vec.d3(0, 0, 0)
MAIN_COLOR = Main_Colour
EDGE_COLOR = Edge_Colour

local LDRAW_CALLBACKS = {
  "STEP",
  "CLEAR",
  "PAUSE",
  "SAVE",
  "WRITE",
  "PRINT",
  "LDRAW_ORG",
  "CATEGORY",
  "PREVIEW",
  "KEYWORD",
  "edge",
  "line",
  "tri",
  "quad",
  "outline",
  "color_outline"
}

-- A traversal pass supplies callbacks for tree operations.

local function set_ldraw_callbacks(callbacks)
  for i = 1, #LDRAW_CALLBACKS do
    local name = LDRAW_CALLBACKS[i]
    _G[name] = callbacks[name]
  end
end

-- LDraw edge colour follows the current main colour.

local function make_edge_color(q)
  return {
    value = q.edge,
    edge = q.edge
  }
end

local function require_sub(sub)
  assert(type(sub) == "function", "missing LDraw sub-tree")
end

-- Apply the current tree frame to a local point.

function apply_global(p)
  local g = p:tr(M)
  g:acc(T)
  return g
end

-- Invoke a sub-tree under an already composed frame.

local function call_frame(sub, q, newM, newT)
  local oldM, oldT = M, T
  local oldMain, oldEdge = MAIN_COLOR, EDGE_COLOR
  M, T = newM, newT
  MAIN_COLOR = q
  EDGE_COLOR = make_edge_color(q)
  sub()
  M, T = oldM, oldT
  MAIN_COLOR, EDGE_COLOR = oldMain, oldEdge
end

-- Translate in the parent coordinate system.

local function step_translation(oldM, oldT, x, y, z)
  local step = Vec.d3(x, y, z):tr(oldM)
  step:acc(oldT)
  return step
end

-- Compose a local transform into the current tree frame.

local function call_transform(sub, q, x, y, z, m)
  local oldM, oldT = M, T
  local newM = m:mul(oldM)
  local newT = step_translation(oldM, oldT, x, y, z)
  call_frame(sub, q, newM, newT)
end

-- Identity placement changes only translation and colour.

function placeN(sub, q, x, y, z)
  require_sub(sub)
  local newT = step_translation(M, T, x, y, z)
  call_frame(sub, q, M, newT)
end

-- Find the source column and sign for one transformed axis.

local function orthogonal_axis(i, j)
  local v = Vec.axis(j):orthogonal3(i)
  if v[1] then
    return 1, v[1]
  elseif v[2] then
    return 2, v[2]
  else
    return 3, v[3]
  end
end

-- Copy or negate one parent basis column.

local function orthogonal_column(m, i, j)
  local axis, sign = orthogonal_axis(i, j)
  local column = clone(m[axis])
  if sign < 0 then
    column:scale(-1)
  end
  return column
end

-- Compose an orthogonal local frame without matrix multiply.

local function orthogonal_mat(m, i)
  return Mat:new({
    orthogonal_column(m, i, 1),
    orthogonal_column(m, i, 2),
    orthogonal_column(m, i, 3)
  })
end

-- Generic orthogonal placement by linalg index.

function place(sub, q, x, y, z, i)
  require_sub(sub)
  local oldM, oldT = M, T
  local newM = orthogonal_mat(oldM, i)
  local newT = step_translation(oldM, oldT, x, y, z)
  call_frame(sub, q, newM, newT)
end

-- South is orthogonal transformation 5.

function placeS(sub, q, x, y, z)
  place(sub, q, x, y, z, 5)
end

-- West is orthogonal transformation 17.

function placeW(sub, q, x, y, z)
  place(sub, q, x, y, z, 17)
end

-- East is orthogonal transformation 20.

function placeE(sub, q, x, y, z)
  place(sub, q, x, y, z, 20)
end

-- Mirror across the east-west axis.

function mirrorEW(sub, q, x, y, z)
  place(sub, q, x, y, z, 1)
end

-- Mirror across the up-down axis.

function mirrorUD(sub, q, x, y, z)
  place(sub, q, x, y, z, 2)
end

-- Mirror across the north-south axis.

function mirrorNS(sub, q, x, y, z)
  place(sub, q, x, y, z, 4)
end

-- Build a diagonal scaling matrix.

local function stretch_mat(a, e, i)
  return Mat:new({
    Vec.d3(a, 0, 0),
    Vec.d3(0, e, 0),
    Vec.d3(0, 0, i)
  })
end

-- Compose a diagonal stretch into the traversal frame.

function stretch(sub, q, x, y, z, a, e, i)
  require_sub(sub)
  call_transform(sub, q, x, y, z, stretch_mat(a, e, i))
end

-- Build the compact twist rotation matrix.

local function make_twist_mat(a, c)
  return Mat:new({
    Vec.d3(a, 0, -c),
    Vec.d3(0, 1, 0),
    Vec.d3(c, 0, a)
  })
end

-- Compose a twist transform into the traversal frame.

function twist(sub, q, x, y, z, a, c)
  require_sub(sub)
  call_transform(sub, q, x, y, z, make_twist_mat(a, c))
end

-- Convert LDraw row-major coefficients to linalg columns.

local function make_ref_mat(a, b, c, d, e, f, g, h, i)
  return Mat:new({
    Vec.d3(a, d, g),
    Vec.d3(b, e, h),
    Vec.d3(c, f, i)
  })
end

-- Compose a general Type 1 reference matrix.

function ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  require_sub(sub)
  call_transform(sub, q, x, y, z,
    make_ref_mat(a, b, c, d, e, f, g, h, i))
end

-- Run one transpiled LDraw tree under a concrete traversal pass.

function traverse_ldraw(root, callbacks, q)
  require_sub(root)
  set_ldraw_callbacks(callbacks)
  local oldM, oldT = M, T
  local oldMain, oldEdge = MAIN_COLOR, EDGE_COLOR
  M = Mat.unit(3)
  T = Vec.d3(0, 0, 0)
  MAIN_COLOR = q or Main_Colour
  EDGE_COLOR = make_edge_color(MAIN_COLOR)
  root()
  M, T = oldM, oldT
  MAIN_COLOR, EDGE_COLOR = oldMain, oldEdge
end






