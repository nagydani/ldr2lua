-- LDraw tree traversal runtime.

local M = Mat.unit(3)
local T = Vec.d3(0, 0, 0)
local ENTER_REF
local LEAVE_REF

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
  ENTER_REF = callbacks.enter_ref
  LEAVE_REF = callbacks.leave_ref
end

-- Nested traversal passes temporarily replace DSL callbacks.

local function save_ldraw_callbacks()
  local saved = { enter_ref = ENTER_REF, leave_ref = LEAVE_REF }
  for i = 1, #LDRAW_CALLBACKS do
    local name = LDRAW_CALLBACKS[i]
    saved[name] = _G[name]
  end
  return saved
end

-- Restore the callback environment seen by the caller.

local function restore_ldraw_callbacks(saved)
  for i = 1, #LDRAW_CALLBACKS do
    local name = LDRAW_CALLBACKS[i]
    _G[name] = saved[name]
  end
  ENTER_REF = saved.enter_ref
  LEAVE_REF = saved.leave_ref
end

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

-- Reference hooks let passes track tree ancestry.

local function enter_ref(sub, q, m, t)
  if ENTER_REF or LEAVE_REF then
    local ldraw_ref = make_ldraw_ref(sub, q, m, t)
    if ENTER_REF then ENTER_REF(ldraw_ref) end
    return ldraw_ref
  end
end

local function leave_ref(ldraw_ref)
  if LEAVE_REF then
    LEAVE_REF(ldraw_ref)
  end
end

local function restore_frame(m, t, main, edge)
  M, T = m, t
  MAIN_COLOR, EDGE_COLOR = main, edge
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
  local ldraw_ref = enter_ref(sub, q, newM, newT)
  sub()
  leave_ref(ldraw_ref)
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
  if not sub then return end
  local newT = step_translation(M, T, x, y, z)
  call_frame(sub, q, M, newT)
end

-- Generic orthogonal placement by linalg index.

function place(sub, q, x, y, z, i)
  if not sub then return end
  local oldM, oldT = M, T
  local newM = oldM:orthogonal3(i)
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
  if not sub then return end
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
  if not sub then return end
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
  if not sub then return end
  call_transform(sub, q, x, y, z,
    make_ref_mat(a, b, c, d, e, f, g, h, i))
end

-- Run one transpiled LDraw tree under a concrete traversal pass.

function traverse_ldraw(root, callbacks, q)
  if not root then return end
  local oldCallbacks = save_ldraw_callbacks()
  set_ldraw_callbacks(callbacks)
  local oldM, oldT = M, T
  local oldMain, oldEdge = MAIN_COLOR, EDGE_COLOR
  M = Mat.unit(3)
  T = Vec.d3(0, 0, 0)
  MAIN_COLOR = q
  EDGE_COLOR = make_edge_color(MAIN_COLOR)
  root()
  restore_frame(oldM, oldT, oldMain, oldEdge)
  restore_ldraw_callbacks(oldCallbacks)
end
