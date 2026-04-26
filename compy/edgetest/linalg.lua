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
function Vec:c3()
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
  return r
end

-- renormalization
function Vec:renorm()
  local l2 = self:dot(self)
  local d = 0.5 * (1 - l2)
  if TOL < d then
    self:scale(1 + d)
  end
end

-- transformations

-- permutation, returns true for odd permutations
local function permute(t, o, n, i)
  local p = o + (i % n)
  local s = o < p
  t[o], t[p] = t[p], t[o]
  if n < 3 then
    return s
  elseif permute(t, o + 1, n - 1, math.floor(i / n)) then
    return not s
  end
  return s
end

-- permute the first n elements, 0 <= i < n!
function Vec:perm(n, i)
  return permute(self, 1, n, i)
end

-- negate coordinate
local function neg(x)
  return x and -x
end

-- generated orthogonal transformations
local function tr(n, i)
  local t = { }
  for j = 1, n do
    local v = "v[" .. j .. "]"
    if i % 2 == 1 then
      v = "neg(" .. v .. ")"
    end
    t[j] = v
    i = math.floor(i / 2)
  end
  permute(t, 1, n, i)
  return t
end

local function orthogonal(n, i)
  local t = tr(n, i)
  local r = "return function(neg, v) return Vec:new {"
  for j = 1, n do
    r = r .. t[j] .. ","
  end
  r = r .. "} end"
  local f = assert(loadstring(r))()
  return function(v)
    return f(neg, v)
  end
end

local orthogonal3 = { }
for i = 0, 47 do
  orthogonal3[i] = orthogonal(3, i)
end

-- 3d orthogonal transformation number i (between 1 and 47)
function Vec:orthogonal3(i)
  return orthogonal3[i](self)
end

-- find matching inverse transformations
local orthogonal3i = {
  [0] = 0
}

local v123 = Vec:new({
  1,
  2,
  3
})

for i = 1, 47 do
  local v = v123:orthogonal3(i)
  for j = 1, 47 do
    local w = v:orthogonal3(j)
    if w[1] == 1 and w[2] == 2 and w[3] == 3 then
      orthogonal3i[i] = j
    end
  end
end

-- 3d orthogonal inverse transofrmation number i
function Vec:orthogonal3i(i)
  return orthogonal3[orthogonal3i[i]](self)
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
  return m
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

-- matrix folding
local function fold(self, f)
  local r = Mat:new()
  for i, v in ipairs(self) do
    r[i] = f(v)
  end
  return r
end

-- matrix multiplication
function Mat:mul(m)
  return fold(self, function(v)
    return v:tr(m)
  end)
end

-- 3d orthogonal transformation
function Mat:orthogonal3(i)
  return fold(self, function(v)
    return v:orthogonal3(i)
  end)
end

-- 3d orthogonal inverse transformation
function Mat:orthogonal3i(i)
  return fold(self, function(v)
    return v:orthogonal3i(i)
  end)
end
