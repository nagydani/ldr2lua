-- LDraw tree traversal runtime.

require("linalg")

local M = Mat.unit(3)
local T = Vec:new({ })
local GLOBAL_MT = { }

setmetatable(_G, GLOBAL_MT)

-- LDraw edge colour follows the current main colour.

local function make_edge_color(q)
  return {
    value = q.edge,
    edge = q.edge
  }
end

-- Expose the current frame as a row-major LDraw reference.

local function make_ldraw_ref(sub, q, m, t)
  return {
    ldraw = sub, color = q.value,
    x = t:c(1), y = t:c(2), z = t:c(3),
    a = m:e(1, 1), b = m:e(2, 1), c = m:e(3, 1),
    d = m:e(1, 2), e = m:e(2, 2), f = m:e(3, 2),
    g = m:e(1, 3), h = m:e(2, 3), i = m:e(3, 3)
  }
end

-- Reference hooks. enter_ref returns whatever leave_ref will
-- restore; the value rides on Lua's call stack via call_frame.

local function enter_ref(sub, q, m, t)
  local enter = GLOBAL_MT.__index.enter_ref
  if enter then
    return enter(make_ldraw_ref(sub, q, m, t))
  end
end

local function leave_ref(saved)
  local leave = GLOBAL_MT.__index.leave_ref
  if leave then
    leave(saved)
  end
end

local function restore_frame(m, t, main, edge)
  M, T = m, t
  MAIN_COLOR, EDGE_COLOR = main, edge
end

-- Apply matrix m and translation t to numeric coords.

function transform3(m, t, x, y, z)
  local m1, m2, m3 = m[1], m[2], m[3]
  local ax = (m1[1] or 0)*x + (m2[1] or 0)*y + (m3[1] or 0)*z
  local ay = (m1[2] or 0)*x + (m2[2] or 0)*y + (m3[2] or 0)*z
  local az = (m1[3] or 0)*x + (m2[3] or 0)*y + (m3[3] or 0)*z
  return ax + (t[1] or 0), ay + (t[2] or 0), az + (t[3] or 0)
end

-- Apply the current tree frame to numeric coords.

function apply_global3(x, y, z)
  return transform3(M, T, x, y, z)
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
  local saved = enter_ref(sub, q, newM, newT)
  sub()
  leave_ref(saved)
  restore_frame(oldM, oldT, oldMain, oldEdge)
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
  if sub then
    local newT = step_translation(M, T, x, y, z)
    call_frame(sub, q, M, newT)
  end
end

-- Generic orthogonal placement by linalg index.

function place(sub, q, x, y, z, i)
  if sub then
    local oldM, oldT = M, T
    local newM = oldM:orthogonal3(i)
    local newT = step_translation(oldM, oldT, x, y, z)
    call_frame(sub, q, newM, newT)
  end
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

-- Compose a diagonal stretch into the traversal frame.

function stretch(sub, q, x, y, z, a, e, i)
  if sub then
    call_transform(sub, q, x, y, z, Mat.diag(a, e, i))
  end
end

-- Build the compact twist rotation matrix.

local function make_twist_mat(a, c)
  return Mat:new({
    Vec.d3(a, 0, -c),
    Vec.axis(2),
    Vec.d3(c, 0, a)
  })
end

-- Compose a twist transform into the traversal frame.

function twist(sub, q, x, y, z, a, c)
  if sub then
    call_transform(sub, q, x, y, z, make_twist_mat(a, c))
  end
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
  if sub then
    call_transform(sub, q, x, y, z,
      make_ref_mat(a, b, c, d, e, f, g, h, i))
  end
end

-- Run one transpiled LDraw tree under a concrete traversal pass.

function traverse_ldraw(root, callbacks, q)
  if root then
    GLOBAL_MT.__index = callbacks
    M = Mat.unit(3)
    T = Vec:new({ })
    MAIN_COLOR = q
    EDGE_COLOR = make_edge_color(q)
    root()
  end
end
