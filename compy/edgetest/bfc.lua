-- BFC (back face culling) state and operations.
-- State separates per-file (reset at subfile entry) and
-- accumulated (propagated through the subfile boundary). Spec:
-- https://www.ldraw.org/article/415.html

-- Per-file: reset on subfile entry.

local certified = nil
local winding = 1
local local_cull = true

-- Accumulated: propagated through subfile boundary.

local accum_cull = true
local accum_invert = false

-- Meta-handlers. BFC CW/CCW fold accum_invert into winding at
-- meta time, per the spec's CW/CCW pseudo-code.

local function set_winding(w)
  winding = accum_invert and -w or w
end

function BFC_CERTIFY(w)
  if certified == nil then
    certified = true
  end
  set_winding(w)
end

function BFC_NOCERTIFY()
  if certified then
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

-- Wrap a Type 1 dispatch in BFC INVERTNEXT semantics: flip
-- accum_invert for the duration of the wrapped call.

function BFC_INVERT(f)
  return function(...)
    accum_invert = not accum_invert
    f(...)
    accum_invert = not accum_invert
  end
end

-- Signed 3x3 determinant of a Mat. Replace body with the
-- linalg-backed version once it lands.

function signed_det3(m)
  local a, b, c = m:e(1, 1), m:e(2, 1), m:e(3, 1)
  local d, e, f = m:e(1, 2), m:e(2, 2), m:e(3, 2)
  local g, h, i = m:e(1, 3), m:e(2, 3), m:e(3, 3)
  return (a * (e * i - f * h) - b * (d * i - f * g)) + c * 
    (d * h - e * g)
end

-- Reset file-local state for a fresh subfile context.

local function reset_local()
  certified = nil
  winding = 1
  local_cull = true
end

-- Snapshot state, propagate AccumCull (with parts-exception),
-- reset per-file state for the sub.

function bfc_enter(is_part)
  local saved = {
    certified = certified,
    winding = winding,
    local_cull = local_cull,
    accum_cull = accum_cull,
    accum_invert = accum_invert
  }
  accum_cull = is_part or bfc_culling()
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
  accum_cull = true
  accum_invert = false
end

-- True iff a tri/quad in this file should be tested for
-- back-face culling.

function bfc_culling()
  return certified and accum_cull and local_cull
end

-- Current winding sign; the picking pass combines this with
-- sv and sign(det(M)) to decide front/back.

function bfc_winding()
  return winding
end

-- Signed volume of (p2-p1, p3-p1, p4-p1). Sign tells which
-- side of the triangle plane p4 sits on.

function signed_volume3(p1, p2, p3, p4)
  local p1x, p1y, p1z = p1:c3()
  local ax, ay, az = p2:c3()
  local bx, by, bz = p3:c3()
  local cx, cy, cz = p4:c3()
  ax, ay, az = ax - p1x, ay - p1y, az - p1z
  bx, by, bz = bx - p1x, by - p1y, bz - p1z
  cx, cy, cz = cx - p1x, cy - p1y, cz - p1z
  return (ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx))
       + az * (bx * cy - by * cx)
end
