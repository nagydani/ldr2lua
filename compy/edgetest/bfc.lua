-- BFC (back face culling) state and operations.
-- State separates per-file (reset at subfile entry),
-- per-action (consumed by next subfile call), and accumulated
-- (propagated through the subfile boundary).
-- Per-file: reset on subfile entry.

local certified = nil
local winding = 1
local local_cull = true

-- Per-action: consumed by the next subfile reference.

local invert_next = false

-- Accumulated: propagated through subfile boundary.

local accum_cull = true
local accum_invert = false

-- Meta-handlers. BFC CW/CCW fold accum_invert into winding at
-- meta time, per the spec's CW/CCW pseudo-code.

local function set_winding(w)
  winding = accum_invert and -w or w
end

function BFC_CERTIFY(w)
  if certified ~= false then certified = true end
  set_winding(w)
end

function BFC_NOCERTIFY()
  if certified == true then
    error("BFC NOCERTIFY after CERTIFY")
  end
  certified = false
end

function BFC(w)
  set_winding(w)
end

function BFC_CLIP(w)
  local_cull = true
  if w then set_winding(w) end
end

function BFC_NOCLIP()
  local_cull = false
end

-- Wrap a Type 1 dispatch in BFC INVERTNEXT semantics: the
-- flag is consumed by bfc_enter on the resulting call.

function BFC_INVERT(f)
  return function(...)
    invert_next = true
    f(...)
  end
end

-- Signed 3x3 determinant of a Mat. Replace body with the
-- linalg-backed version once it lands.

function signed_det3(m)
  local a, b, c = m:e(1, 1), m:e(2, 1), m:e(3, 1)
  local d, e, f = m:e(1, 2), m:e(2, 2), m:e(3, 2)
  local g, h, i = m:e(1, 3), m:e(2, 3), m:e(3, 3)
  return a * (e * i - f * h)
    - b * (d * i - f * g)
    + c * (d * h - e * g)
end

-- Reset file-local state for a fresh subfile context.

local function reset_local()
  certified = nil
  winding = 1
  local_cull = true
end

-- Snapshot, fold invert_next into accum_invert, propagate
-- AccumCull per spec, reset file-local state for the sub.

function bfc_enter()
  local saved = {
    certified = certified,
    winding = winding,
    local_cull = local_cull,
    accum_cull = accum_cull,
    accum_invert = accum_invert
  }
  accum_invert = accum_invert ~= invert_next
  invert_next = false
  accum_cull = bfc_culling()
  reset_local()
  return saved
end

function bfc_leave(saved)
  certified = saved.certified
  winding = saved.winding
  local_cull = saved.local_cull
  accum_cull = saved.accum_cull
  accum_invert = saved.accum_invert
end

-- Reset to root defaults at the start of a traversal pass.

function bfc_reset()
  reset_local()
  invert_next = false
  accum_cull = true
  accum_invert = false
end

-- True iff a tri/quad in this file should be tested for
-- back-face culling.

function bfc_culling()
  return accum_cull and local_cull and certified == true
end

-- Current winding sign; the picking pass combines this with
-- sv and sign(det(M)) to decide front/back.

function bfc_winding()
  return winding
end

-- Signed volume of (p2-p1, p3-p1, p4-p1). Sign tells which
-- side of the triangle plane p4 sits on.

function signed_volume3(p1x, p1y, p1z, p2x, p2y, p2z,
    p3x, p3y, p3z, p4x, p4y, p4z)
  local ax, ay, az = p2x-p1x, p2y-p1y, p2z-p1z
  local bx, by, bz = p3x-p1x, p3y-p1y, p3z-p1z
  local cx, cy, cz = p4x-p1x, p4y-p1y, p4z-p1z
  return ax*(by*cz - bz*cy)
    - ay*(bx*cz - bz*cx)
    + az*(bx*cy - by*cx)
end
