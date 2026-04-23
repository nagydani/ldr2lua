-- 3x4 affine matrices represented as a table of four vectors:

-- three row vectors of the 3x3 rotation part plus a translation

-- vector. The layout is m = { r1, r2, r3, t }.

function mat_new(r1, r2, r3, t)
  local m = { }
  m[1], m[2], m[3], m[4] = r1, r2, r3, t
  return m
end

-- Return a scaled identity matrix: scale times I with zero

-- translation.

function mat_scaled_identity(s)
  local r1 = vec_new(s, 0, 0)
  local r2 = vec_new(0, s, 0)
  local r3 = vec_new(0, 0, s)
  local t = vec_new(0, 0, 0)
  return mat_new(r1, r2, r3, t)
end

-- Build a matrix from a 3x3 rotation (as three row vectors) and

-- a translation vector.

function mat_from_rot(r1, r2, r3, t)
  return mat_new(r1, r2, r3, t)
end

-- Apply a matrix to a vector: m * v + t.

function mat_apply(m, v)
  local x = vec_dot(m[1], v) + m[4][1]
  local y = vec_dot(m[2], v) + m[4][2]
  local z = vec_dot(m[3], v) + m[4][3]
  return vec_new(x, y, z)
end

-- Column vector i of the rotation part of m, as a vec.

function mat_col(m, i)
  return vec_new(m[1][i], m[2][i], m[3][i])
end

-- Dot the row vector r against three column vectors and return

-- the result as a vec.

function mat_row_times_cols(r, c1, c2, c3)
  local x = vec_dot(r, c1)
  local y = vec_dot(r, c2)
  local z = vec_dot(r, c3)
  return vec_new(x, y, z)
end

-- Composition: result = m1 * m2. Rotation part is the matrix

-- product; translation is m1 applied to m2's translation.

function mat_compose(m1, m2)
  local c1 = mat_col(m2, 1)
  local c2 = mat_col(m2, 2)
  local c3 = mat_col(m2, 3)
  local r1 = mat_row_times_cols(m1[1], c1, c2, c3)
  local r2 = mat_row_times_cols(m1[2], c1, c2, c3)
  local r3 = mat_row_times_cols(m1[3], c1, c2, c3)
  local t = mat_apply(m1, m2[4])
  return mat_new(r1, r2, r3, t)
end
