-- Ray picking pass for transpiled LDraw trees.

local PASS_NAMES = {
  "STEP",
  "CLEAR",
  "PAUSE",
  "SAVE",
  "WRITE",
  "PRINT",
  "CATEGORY",
  "PREVIEW",
  "KEYWORD",
  "edge",
  "line",
  "outline",
  "color_outline"
}

local function noop()
end

local ROOT_COLOR = Yellow

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

-- Store the nearest positive surface hit seen so far.

local function keep_hit(ctx, l)
  if ctx.part and l and l < ctx.l then
    ctx.hit, ctx.l = ctx.part, l
  end
end

local function find_tri(ctx, x1, y1, z1, x2, y2, z2, x3, y3, z3)
  keep_hit(ctx, ray_triangle_l(ctx.ray, global_point(x1, y1, z1),
    global_point(x2, y2, z2), global_point(x3, y3, z3)))
end

local function find_quad(ctx, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  local p1, p2 = global_point(x1, y1, z1), global_point(x2, y2, z2)
  local p3, p4 = global_point(x3, y3, z3), global_point(x4, y4, z4)
  keep_hit(ctx, ray_triangle_l(ctx.ray, p1, p2, p3))
  keep_hit(ctx, ray_triangle_l(ctx.ray, p1, p3, p4))
end

-- Snapshot ctx.part on enter; restore via Lua's call stack.

local function on_enter(ctx, ref)
  local saved_part = ctx.part
  ctx.ref = ref
  return saved_part
end

local function on_leave(ctx, saved_part)
  ctx.part = saved_part
end

local function mark_part(ctx, kind)
  if kind == "Part" then
    ctx.part = ctx.ref
  end
end

local function base_callbacks()
  local callbacks = { }
  for _, name in pairs(PASS_NAMES) do
    callbacks[name] = noop
  end
  return callbacks
end

-- Picking is a traversal pass that only consumes Part, tri, and quad.

local function find_callbacks(ctx)
  local callbacks = base_callbacks()
  callbacks.enter_ref = function(r) return on_enter(ctx, r) end
  callbacks.leave_ref = function(s) on_leave(ctx, s) end
  callbacks.LDRAW_ORG = function(k) mark_part(ctx, k) end
  callbacks.tri = function(_, ...) find_tri(ctx, ...) end
  callbacks.quad = function(_, ...) find_quad(ctx, ...) end
  return callbacks
end

local function make_context(x, y, z, dx, dy, dz)
  return {
    ray = { origin = Vec.d3(x, y, z), dir = Vec.d3(dx, dy, dz) },
    l = math.huge
  }
end

function find_part(model, x, y, z, dx, dy, dz)
  local ctx = make_context(x, y, z, dx, dy, dz)
  traverse_ldraw(model, find_callbacks(ctx), ROOT_COLOR)
  if ctx.hit then
    return ctx.hit, ctx.l
  end
end
