-- LDraw tree traversal runtime.

-- A do-nothing callback used by any pass that wants to silence
-- a particular DSL hook.

function ignore()
end

-- Execute filename in a private _G, return that _G as a table.
-- Parent globals visible through __index; functions in the
-- result are bound to the private env.

function loadtable(filename)
  local env = setmetatable({ }, { __index = _G })
  local chunk = assert(loadfile(filename))
  setfenv(chunk, env)
  chunk()
  local result = { }
  for k, v in pairs(env) do
    result[k] = v
    if type(v) == "function" then
      setfenv(v, env)
    end
  end
  return result
end

local M = Mat.unit(3)
local T = Vec.d3(0, 0, 0)
local GLOBAL_MT = { }

setmetatable(_G, GLOBAL_MT)

-- Apply matrix m and translation t to numeric coords.

function transform3(m, t, x, y, z)
  local m1, m2, m3 = m[1], m[2], m[3]
  local ax = (m1[1] or 0) * x + (m2[1] or 0) * y + (m3[1] or 0)
       * z
  local ay = (m1[2] or 0) * x + (m2[2] or 0) * y + (m3[2] or 0)
       * z
  local az = (m1[3] or 0) * x + (m2[3] or 0) * y + (m3[3] or 0)
       * z
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

-- Expose the current global frame matrix to other passes.

function global_matrix()
  return M
end

-- Invoke a sub-tree under an already composed frame.
-- The pass-defined call(sub) hook decides whether sub runs.

local function call_frame(sub, q, newM, newT)
  local oldM, oldT = M, T
  local oldMain, oldEdge = MAIN_COLOR, EDGE_COLOR
  M, T = newM, newT
  MAIN_COLOR = q
  EDGE_COLOR = q.edge
  local saved = enter_ref(sub, q, newM, newT)
  call(sub)
  leave_ref(saved)
  M, T = oldM, oldT
  MAIN_COLOR, EDGE_COLOR = oldMain, oldEdge
end

-- Translate in the parent coordinate system.

local function step_translation(m, t, x, y, z)
  local step = Vec.d3(x, y, z):tr(m)
  step:acc(t)
  return step
end

-- Compose a local transform into the current tree frame.

local function call_transform(sub, q, x, y, z, m)
  call_frame(sub, q, m:mul(M), step_translation(M, T, x, y, z))
end

-- Identity placement changes only translation and colour.

function placeN(sub, q, x, y, z)
  if sub then
    call_frame(sub, q, M, step_translation(M, T, x, y, z))
  end
end

-- Generic orthogonal placement by linalg index.

function place(sub, q, x, y, z, i)
  if sub then
    call_frame(
      sub,
      q,
      M:orthogonal3(i),
      step_translation(M, T, x, y, z)
    )
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

-- Compose a twist transform into the traversal frame.

function twist(sub, q, x, y, z, a, c)
  if sub then
    call_transform(sub, q, x, y, z, Mat:new({
      Vec.d3(a, 0, -c),
      Vec.d3(0, 1, 0),
      Vec.d3(c, 0, a)
    }))
  end
end

-- Compose a general Type 1 reference matrix.

function ref(sub, q, x, y, z, a, b, c, d, e, f, g, h, i)
  if sub then
    call_transform(sub, q, x, y, z, Mat:new({
      Vec.d3(a, d, g),
      Vec.d3(b, e, h),
      Vec.d3(c, f, i)
    }))
  end
end

-- Invoke a sub-tree with a pre-composed frame (used to redraw
-- a Part captured by picking).

function ref_frame(sub, q, m, t)
  if sub then
    call_frame(sub, q, m, t)
  end
end

-- Run one transpiled LDraw tree under a concrete traversal pass.

function traverse_ldraw(root, callbacks, q)
  if root then
    GLOBAL_MT.__index = callbacks
    M = Mat.unit(3)
    T = Vec.d3(0, 0, 0)
    MAIN_COLOR = q
    EDGE_COLOR = q.edge
    root()
  end
end
