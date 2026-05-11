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

local function noop()
end

local function cross(a, b)
  local ax, ay, az = a:c3()
  local bx, by, bz = b:c3()
  return Vec.d3(ay * bz - az * by, az * bx - ax * bz,
    ax * by - ay * bx)
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
  if u < 0 or 1 < u then return nil end
  local qvec = cross(tvec, e1)
  local v = ray.dir:dot(qvec) * inv
  if v < 0 or 1 < u + v then return nil end
  local l = e2:dot(qvec) * inv
  if TOL < l then return l end
end

local function ray_triangle_l(ray, p1, p2, p3)
  local e1 = diff(p2, p1)
  local e2 = diff(p3, p1)
  local pvec = cross(ray.dir, e2)
  local det = e1:dot(pvec)
  if math.abs(det) < TOL then return nil end
  return ray_triangle_bary(ray, p1, e1, e2, pvec, 1 / det)
end

local function global_point(x, y, z)
  return apply_global(Vec.d3(x, y, z))
end

-- True if (p1, p2, p3) faces the ray origin per winding sign
-- and matrix-reversal sign of the current global frame.

local function is_front_face(ray, p1, p2, p3)
  local ox, oy, oz = ray.origin:c3()
  local p1x, p1y, p1z = p1:c3()
  local p2x, p2y, p2z = p2:c3()
  local p3x, p3y, p3z = p3:c3()
  local sv = signed_volume3(p1x, p1y, p1z, p2x, p2y, p2z,
    p3x, p3y, p3z, ox, oy, oz)
  return sv * bfc_winding() * signed_det3(global_matrix()) > 0
end

-- Store the nearest positive surface hit seen so far.

local function keep_hit(ctx, l)
  if ctx.part and l and l < ctx.l then
    ctx.hit, ctx.l = ctx.part, l
  end
end

-- Test one triangle; skip if culling discards its back side.

local function check_tri(ctx, p1, p2, p3)
  local ray = ctx.ray
  if bfc_culling() and not is_front_face(ray, p1, p2, p3) then
    return
  end
  keep_hit(ctx, ray_triangle_l(ray, p1, p2, p3))
end

local function find_tri(ctx, x1, y1, z1, x2, y2, z2, x3, y3, z3)
  check_tri(ctx, global_point(x1, y1, z1),
    global_point(x2, y2, z2), global_point(x3, y3, z3))
end

local function find_quad(ctx, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  local p1, p2 = global_point(x1, y1, z1), global_point(x2, y2, z2)
  local p3, p4 = global_point(x3, y3, z3), global_point(x4, y4, z4)
  check_tri(ctx, p1, p2, p3)
  check_tri(ctx, p1, p3, p4)
end

-- Build a row-major LDraw reference from raw frame args.

local function make_ldraw_ref(sub, m, t)
  return {
    ldraw = sub,
    x = t:c(1), y = t:c(2), z = t:c(3),
    a = m:e(1, 1), b = m:e(2, 1), c = m:e(3, 1),
    d = m:e(1, 2), e = m:e(2, 2), f = m:e(3, 2),
    g = m:e(1, 3), h = m:e(2, 3), i = m:e(3, 3)
  }
end

-- Squared sphere radius keyed by Part chunk function. Filled
-- by probe_part during startup; on_enter reads it to detect
-- entry into a pickable Part subtree.

local RADIUS = { }

-- Snapshot ctx.part and BFC state on enter; restored on leave
-- via Lua's call stack. RADIUS[sub] presence marks sub as a
-- Part, so its frame ref becomes the pickable region.

local function on_enter(ctx, sub, m, t)
  local saved = { part = ctx.part, bfc = bfc_enter() }
  if RADIUS[sub] then
    ctx.part = make_ldraw_ref(sub, m, t)
  end
  return saved
end

local function on_leave(ctx, saved)
  ctx.part = saved.part
  bfc_leave(saved.bfc)
end

local function base_callbacks()
  local callbacks = { }
  for _, name in pairs(PASS_NAMES) do
    callbacks[name] = noop
  end
  return callbacks
end

-- Accumulate squared distance of one vertex from origin.

local function probe_vertex(ctx, x, y, z)
  local gx, gy, gz = apply_global3(x, y, z)
  local r2 = gx*gx + gy*gy + gz*gz
  if r2 > ctx.max_r2 then ctx.max_r2 = r2 end
end

local function probe_tri(ctx, _, x1, y1, z1,
    x2, y2, z2, x3, y3, z3)
  probe_vertex(ctx, x1, y1, z1)
  probe_vertex(ctx, x2, y2, z2)
  probe_vertex(ctx, x3, y3, z3)
end

local function probe_quad(ctx, _, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  probe_vertex(ctx, x1, y1, z1)
  probe_vertex(ctx, x2, y2, z2)
  probe_vertex(ctx, x3, y3, z3)
  probe_vertex(ctx, x4, y4, z4)
end

-- Probe pass: collect max squared vertex radius across the
-- chunk's triangles and quads.

local function probe_callbacks(ctx)
  local callbacks = base_callbacks()
  callbacks.enter_ref = noop
  callbacks.leave_ref = noop
  callbacks.call = function(sub) sub() end
  callbacks.tri = function(...) probe_tri(ctx, ...) end
  callbacks.quad = function(...) probe_quad(ctx, ...) end
  return callbacks
end

-- Probe pass: walk the chunk and write its squared bounding
-- sphere radius to RADIUS[chunk]. Caller passes only chunks
-- that should be pickable Parts.

function probe_part(chunk)
  local ctx = { max_r2 = 0 }
  traverse_ldraw(chunk, probe_callbacks(ctx), Yellow)
  RADIUS[chunk] = ctx.max_r2
end

-- Ray-sphere test against a sphere at the current frame origin.

local function ray_sphere(ctx, r2)
  local ox, oy, oz = ctx.ray.origin:c3()
  local dx, dy, dz = ctx.ray.dir:c3()
  local cx, cy, cz = apply_global3(0, 0, 0)
  local ocx, ocy, ocz = ox-cx, oy-cy, oz-cz
  local b = ocx*dx + ocy*dy + ocz*dz
  local c = ocx*ocx + ocy*ocy + ocz*ocz - r2
  local dd = dx*dx + dy*dy + dz*dz
  return b*b - dd*c >= 0
end

-- Skip the subtree of a Part if its sphere is missed.

local function check_call(ctx, sub)
  local r2 = RADIUS[sub]
  if r2 and not ray_sphere(ctx, r2) then return end
  sub()
end

-- Picking is a traversal pass that only consumes Part, tri, and quad.

local function find_callbacks(ctx)
  local callbacks = base_callbacks()
  callbacks.enter_ref = function(sub, q, m, t)
    return on_enter(ctx, sub, m, t)
  end
  callbacks.leave_ref = function(s) on_leave(ctx, s) end
  callbacks.call = function(sub) check_call(ctx, sub) end
  callbacks.tri = function(_, ...) find_tri(ctx, ...) end
  callbacks.quad = function(_, ...) find_quad(ctx, ...) end
  return callbacks
end

local function make_context(origin, dir)
  return {
    ray = { origin = origin, dir = dir },
    l = math.huge
  }
end

function find_part(model, origin, dir)
  local ctx = make_context(origin, dir)
  bfc_reset()
  traverse_ldraw(model, find_callbacks(ctx), Yellow)
  if ctx.hit then
    return ctx.hit, ctx.l
  end
end


 

