-- BFC (back face culling) state and operations.
-- Per-file scope state and a single accumulated flag are
-- module-local; sub-tree entry snapshots them through Lua's
-- call stack, just like M and T in ldraw.lua.

-- Per-file state.

local certified = nil   -- nil = unknown; true / false set
local winding = 1       -- 1 = CCW, -1 = CW
local local_cull = true

-- Accumulated through the subfile-reference branch.

local accum_cull = true
local outer_sign = 1    -- which det sign means outward face

-- DSL meta-handlers. They mutate the file-local state.

function BFC_CERTIFY(w)
  certified = true
  winding = w
end

function BFC_NOCERTIFY()
  certified = false
end

function BFC(w)
  winding = w
end

function BFC_CLIP(w)
  local_cull = true
  if w then winding = w end
end

function BFC_NOCLIP()
  local_cull = false
end

-- INVERTNEXT wraps a Type 1 dispatch. Flips outer_sign for the
-- duration of the wrapped call.

function BFC_INVERT(f)
  return function(...)
    outer_sign = -outer_sign
    f(...)
    outer_sign = -outer_sign
  end
end

-- Compute sign of a 3x3 matrix determinant. Linalg version
-- pending; replace this body when the new function lands.

local function signed_det3(m)
  local m11, m21, m31 = m:e(1, 1), m:e(2, 1), m:e(3, 1)
  local m12, m22, m32 = m:e(1, 2), m:e(2, 2), m:e(3, 2)
  local m13, m23, m33 = m:e(1, 3), m:e(2, 3), m:e(3, 3)
  return m11*(m22*m33 - m23*m32)
    - m12*(m21*m33 - m23*m31)
    + m13*(m21*m32 - m22*m31)
end

-- Reset file-local state to defaults at sub-tree entry.

local function reset_local()
  certified = nil
  winding = 1
  local_cull = true
end

-- Snapshot, accumulate cull and matrix-reversal sign, reset
-- file-local state for the sub-tree.

function bfc_enter(m)
  local saved = {
    certified = certified,
    winding = winding,
    local_cull = local_cull,
    accum_cull = accum_cull,
    outer_sign = outer_sign
  }
  accum_cull = accum_cull and local_cull
  if signed_det3(m) < 0 then
    outer_sign = -outer_sign
  end
  reset_local()
  return saved
end

-- Restore the snapshot taken by the matching bfc_enter.

function bfc_leave(saved)
  certified = saved.certified
  winding = saved.winding
  local_cull = saved.local_cull
  accum_cull = saved.accum_cull
  outer_sign = saved.outer_sign
end

-- Reset to root defaults at the start of a traversal pass.

function bfc_reset()
  reset_local()
  accum_cull = true
  outer_sign = 1
end

-- Return true if culling currently applies to triangle/quad.

function bfc_culling()
  return accum_cull and local_cull and certified == true
end

-- Signed volume of (p2-p1, p3-p1, p4-p1); sign tells side of
-- the triangle the ray origin sits on (passed as p4).

function signed_volume3(p1x, p1y, p1z, p2x, p2y, p2z,
    p3x, p3y, p3z, p4x, p4y, p4z)
  local ax, ay, az = p2x-p1x, p2y-p1y, p2z-p1z
  local bx, by, bz = p3x-p1x, p3y-p1y, p3z-p1z
  local cx, cy, cz = p4x-p1x, p4y-p1y, p4z-p1z
  return ax*(by*cz - bz*cy)
    - ay*(bx*cz - bz*cx)
    + az*(bx*cy - by*cx)
end

-- Effective winding sign: file winding times outer-face sign.

function bfc_effective_winding()
  return winding * outer_sign
end
