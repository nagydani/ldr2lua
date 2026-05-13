-- Ray picking pass for transpiled LDraw trees.

local PASS_NAMES = {
  "STEP",
  "CLEAR",
  "PAUSE",
  "SAVE",
  "WRITE",
  "PRINT",
  "CATEGORY",
  "LDRAW_ORG",
  "PREVIEW",
  "KEYWORD",
  "edge",
  "line",
  "outline",
  "color_outline"
}

-- Module-level traversal contexts; find_part and probe_part
-- set these before invoking traverse_ldraw. Picking and probe
-- passes are single-shot and don't nest.

local find_ctx
local probe_ctx

local function cross(a, b)
  local ax, ay, az = a:c3()
  local bx, by, bz = b:c3()
  return Vec.d3(
    ay * bz - az * by,
    az * bx - ax * bz,
    ax * by - ay * bx
  )
end

local function diff(a, b)
  local d = clone(a)
  d:acc(b, -1)
  return d
end

-- Moller-Trumbore barycentric test; only positive l is a hit.

local function ray_triangle_bary(ray, p1, e1, e2, pvec, inv)
  local tvec = diff(ray.origin, p1)
  local u = tvec:dot(pvec) * inv
  if u < 0 or 1 < u then return end
  local qvec = cross(tvec, e1)
  local v = ray.dir:dot(qvec) * inv
  if v < 0 or 1 < u + v then return end
  local l = e2:dot(qvec) * inv
  if TOL <= l then return l end
end

local function ray_triangle_l(ray, p1, p2, p3)
  local e1 = diff(p2, p1)
  local e2 = diff(p3, p1)
  local pvec = cross(ray.dir, e2)
  local det = e1:dot(pvec)
  if TOL <= math.abs(det) then
    return ray_triangle_bary(ray, p1, e1, e2, pvec, 1 / det)
  end
end

local function global_point(x, y, z)
  return apply_global(Vec.d3(x, y, z))
end

-- True if (p1, p2, p3) faces the ray origin per winding sign
-- and matrix-reversal sign of the current global frame.

local function is_front_face(ray, p1, p2, p3)
  local sv = signed_volume3(p1, p2, p3, ray.origin)
  return 0 < sv * bfc_winding() * signed_det3(global_matrix())
end

-- Store the nearest positive surface hit seen so far.

local function keep_hit(l)
  if find_ctx.part and l and l < find_ctx.l then
    find_ctx.hit, find_ctx.l = find_ctx.part, l
  end
end

-- Test one triangle; skip if culling discards its back side.

local function check_tri(p1, p2, p3)
  local ray = find_ctx.ray
  if bfc_culling() and not is_front_face(ray, p1, p2, p3) then
    return
  end
  keep_hit(ray_triangle_l(ray, p1, p2, p3))
end

local function find_tri(_, x1, y1, z1, x2, y2, z2, x3, y3, z3)
  check_tri(global_point(x1, y1, z1),
    global_point(x2, y2, z2), global_point(x3, y3, z3))
end

local function find_quad(_, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  local p1 = global_point(x1, y1, z1)
  local p2 = global_point(x2, y2, z2)
  local p3 = global_point(x3, y3, z3)
  local p4 = global_point(x4, y4, z4)
  check_tri(p1, p2, p3)
  check_tri(p1, p3, p4)
end

-- Build a Part frame snapshot from raw enter_ref args.

local function make_ldraw_ref(sub, m, t)
  return {
    ldraw = sub,
    m = m,
    t = t
  }
end

-- Squared sphere radius keyed by Part chunk function;
-- written by probe_part, read by on_enter.

local RADIUS = { }

-- Save ctx.part and BFC state on enter, restored by on_leave.
-- RADIUS[sub] presence marks sub as a Part.

local function on_enter(sub, q, m, t)
  local is_part = RADIUS[sub] ~= nil
  local saved = {
    part = find_ctx.part,
    bfc = bfc_enter(is_part)
  }
  if is_part then
    find_ctx.part = make_ldraw_ref(sub, m, t)
  end
  return saved
end

local function on_leave(saved)
  find_ctx.part = saved.part
  bfc_leave(saved.bfc)
end

local function base_callbacks()
  local callbacks = { }
  for _, name in pairs(PASS_NAMES) do
    callbacks[name] = ignore
  end
  return callbacks
end

-- Accumulate squared distance of one vertex from origin.

local function probe_vertex(x, y, z)
  local gx, gy, gz = apply_global3(x, y, z)
  local r2 = gx * gx + gy * gy + gz * gz
  if probe_ctx.max_r2 < r2 then
    probe_ctx.max_r2 = r2
  end
end

local function probe_tri(_, x1, y1, z1, x2, y2, z2, x3, y3, z3)
  probe_vertex(x1, y1, z1)
  probe_vertex(x2, y2, z2)
  probe_vertex(x3, y3, z3)
end

local function probe_quad(_, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  probe_vertex(x1, y1, z1)
  probe_vertex(x2, y2, z2)
  probe_vertex(x3, y3, z3)
  probe_vertex(x4, y4, z4)
end

-- Probe pass: collect max squared vertex radius across the
-- chunk's triangles and quads.

local PROBE_CALLBACKS = base_callbacks()
PROBE_CALLBACKS.enter_ref = ignore
PROBE_CALLBACKS.leave_ref = ignore
PROBE_CALLBACKS.call = function(sub) sub() end
PROBE_CALLBACKS.tri = probe_tri
PROBE_CALLBACKS.quad = probe_quad

-- Walk chunk, write its squared bounding-sphere radius into
-- RADIUS[chunk]. Caller passes only pickable Parts.

function probe_part(chunk)
  probe_ctx = { max_r2 = 0 }
  traverse_ldraw(chunk, PROBE_CALLBACKS, Yellow)
  RADIUS[chunk] = probe_ctx.max_r2
end

-- Ray-sphere test against a sphere at the current frame origin.

local function ray_sphere(r2)
  local ox, oy, oz = find_ctx.ray.origin:c3()
  local dx, dy, dz = find_ctx.ray.dir:c3()
  local cx, cy, cz = apply_global3(0, 0, 0)
  local ocx, ocy, ocz = ox - cx, oy - cy, oz - cz
  local b = ocx * dx + ocy * dy + ocz * dz
  local c = ocx * ocx + ocy * ocy + ocz * ocz - r2
  local dd = dx * dx + dy * dy + dz * dz
  return 0 <= b * b - dd * c
end

-- Skip the subtree of a Part if its sphere is missed.

local function check_call(sub)
  local r2 = RADIUS[sub]
  if r2 and not ray_sphere(r2) then
    return
  end
  sub()
end

-- Picking pass: consumes Part, tri, and quad only.

local FIND_CALLBACKS = base_callbacks()
FIND_CALLBACKS.enter_ref = on_enter
FIND_CALLBACKS.leave_ref = on_leave
FIND_CALLBACKS.call = check_call
FIND_CALLBACKS.tri = find_tri
FIND_CALLBACKS.quad = find_quad

function find_part(model, origin, dir)
  find_ctx = {
    ray = { origin = origin, dir = dir },
    l = math.huge
  }
  bfc_reset()
  traverse_ldraw(model, FIND_CALLBACKS, Yellow)
  if find_ctx.hit then
    return find_ctx.hit, find_ctx.l
  end
end
