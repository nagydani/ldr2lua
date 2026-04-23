-- vector and matrix operations
-- nil elements in vectors are treated as zero
-- nil elements in matrices are treated as zero vectors
-- vector coordinates are positive integers; no other keys are allowed

-- Recommended pattern:
-- Use classes inside calculations, but do not expose in APIs.

-- clone
function clone(o)
  if type(o) ~= "table" then
    return o
  end
  local r = { }
  for k, v in pairs(o) do
    r[k] = clone(v)
  end
  setmetatable(r, getmetatable(o))
  return r
end

-- Vector operations

-- prototype zero vector
Vec = { }

-- vector constructor from array constructor or nil
function Vec:new(v)
  v = v or { }
  setmetatable(v, self)
  self.__index = self
  return v
end

-- axis-aligned unit vector constructor
function Vec.axis(i)
  local u = Vec:new()
  u[i] = 1
  return u
end

-- numeric non-zero element
local function nonzero(r)
  if math.abs(r) < TOL then
    return nil
  end
  return r
end

-- 3d vector constructor from numbers (safe for 2d)
function Vec.d3(x, y, z)
  return Vec:new({
    nonzero(x),
    nonzero(y),
    nonzero(z)
  })
end

-- numeric coordinate
function Vec:c(i)
  return self[i] or 0
end

-- 2d numeric coordinates
function Vec:c2()
  local c = Vec.c
  return c(self, 1), c(self, 2)
end

-- 3d numeric coordinates
function Vec:c2()
  local c = Vec.c
  return c(self, 1), c(self, 2), c(self, 3)
end

-- accumulate
function Vec:acc(b, s)
  for i, v in pairs(b) do
    if s then
      v = v * s
    end
    local w = self[i]
    if w then
      self[i] = w + v
    else
      self[i] = v
    end
  end
end

-- scale
function Vec:scale(s)
  for i, v in pairs(self) do
    self[i] = v * s
  end
end

-- dot product
function Vec:dot(b)
  local r = 0
  for i, v in pairs(self) do
    r = r + v * b:c(i)
  end
end

-- renormalization
function Vec:renorm()
  local l2 = self:dot(self)
  local d = 0.5 * (1 - l2)
  if TOL < d then
    self:scale(1 + d)
  end
end

-- transform by matrix
function Vec:tr(m)
  local t = Vec:new()
  for i, v in pairs(self) do
    local r = m[i]
    if r then
      t:acc(r, v)
    end
  end
  return t
end

-- Matrix operations

-- prototype zero matrix
Mat = { }

-- matrix constructor from array constructor or nil
function Mat:new(m)
  m = m or { }
  setmetatable(m, self)
  self.__index = self
  return m
end

-- unit matrix constructor
function Mat.unit(d)
  local m = Mat:new()
  for i = 1, d do
    m[i] = Vec.axis(i)
  end
end

-- orthonormal 3d matrix constructor from unit quaternion
function Mat.rot(a, b, c, d)
  local a2, b2, c2, d2 = a * a, b * b, c * c, d * d
  local bc, ad, bd = b * c, a * d, b * d
  local cd, ab, ac = c * d, a * b, a * c
  return Mat:new({
    Vec.d3((a2 + b2 - c2) - d2, 2 * (bc - ad), 2 * (bd + ac)),
    Vec.d3(2 * (bc + ad), (a2 - b2) + c2 - d2, 2 * (cd - ab)),
    Vec.d3(2 * (bd - ac), 2 * (cd + ab), ((a2 - b2) - c2) + d2)
  })
end

-- numeric element
function Mat:e(i, j)
  local r = self[i]
  if r then
    return r:c(j)
  end
  return 0
end

-- numeric 3d row (safe to use for 2d as well)
function Mat:row(i)
  local r = self[i]
  if r then
    return r:c3()
  end
  return 0, 0, 0
end

-- matrix multiplication
function Mat:mul(m)
  local r = Mat:new()
  for i, v in self do
    r[i] = v:tr(m)
  end
  return r
end
