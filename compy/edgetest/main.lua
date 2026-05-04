-- Edgetest entry point.

TOL = 0.0005

require "linalg"
require "ldraw_colors"
require "ldraw"

local gfx = love.graphics

local D = 1000
local CENTER_X = 512
local CENTER_Y = 300
local VIEW_M = Mat.unit(3)
local VIEW_T = Vec.d3(0, 0, 0)

local function perspective(x, y, z)
  local dz = D / z
  return CENTER_X + x * dz, CENTER_Y + y * dz
end

local project = perspective

local function apply_view(p)
  local g = p:tr(VIEW_M)
  g:acc(VIEW_T)
  return g
end

local function screen_point(x, y, z)
  local g = apply_view(apply_global(Vec.d3(x, y, z)))
  return project(g:c3())
end

local function set_draw_color(q)
  local v = q.value
  gfx.setColor(v[1], v[2], v[3], v[4] or 1)
end

local function draw_segment(q, x1, y1, z1, x2, y2, z2)
  local sx1, sy1 = screen_point(x1, y1, z1)
  local sx2, sy2 = screen_point(x2, y2, z2)
  set_draw_color(q)
  gfx.line(sx1, sy1, sx2, sy2)
end

local function draw_edge(x1, y1, z1, x2, y2, z2)
  draw_segment(EDGE_COLOR, x1, y1, z1, x2, y2, z2)
end

local function draw_line(q, x1, y1, z1, x2, y2, z2)
  draw_segment(q, x1, y1, z1, x2, y2, z2)
end

local function same_side(ax, ay, bx, by, cx, cy, dx, dy)
  local vx, vy = bx - ax, by - ay
  local s1 = vx * (cy - ay) - vy * (cx - ax)
  local s2 = vx * (dy - ay) - vy * (dx - ax)
  return 0 <= s1 * s2
end

local function draw_outline_with(q, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  local sx1, sy1 = screen_point(x1, y1, z1)
  local sx2, sy2 = screen_point(x2, y2, z2)
  local sx3, sy3 = screen_point(x3, y3, z3)
  local sx4, sy4 = screen_point(x4, y4, z4)
  if same_side(sx1, sy1, sx2, sy2, sx3, sy3, sx4, sy4) then
    set_draw_color(q)
    gfx.line(sx1, sy1, sx2, sy2)
  end
end

local function draw_outline(x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  draw_outline_with(EDGE_COLOR, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
end

local function draw_color_outline(q, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  draw_outline_with(q, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
end

local function draw_noop()
end

local DAT_FILES = {
  "dat_3001",
  "dat_3001s01",
  "dat_3003",
  "dat_3003s01",
  "dat_3003s02",
  "dat_4_4cyli",
  "dat_4_4disc",
  "dat_4_4edge",
  "dat_4_4ring3",
  "dat_box3u2p",
  "dat_box5",
  "dat_stud",
  "dat_stud4",
  "dat_stug_2x2"
}

local function load_chunks()
  for i = 1, #DAT_FILES do
    local name = DAT_FILES[i]
    _G[name] = loadfile(name .. ".lua")
  end
end

local function setup_view()
  VIEW_M = Mat:new({
    Vec.d3(0.8779, 0.1685, -0.4489),
    Vec.d3(0, 0.9363, 0.3511),
    Vec.d3(0.4789, -0.3082, 0.8221)
  })
  VIEW_T = Vec.d3(0, 70, 850)
end

local DRAW_CALLBACKS = {
  STEP = draw_noop,
  CLEAR = draw_noop,
  PAUSE = draw_noop,
  SAVE = draw_noop,
  WRITE = draw_noop,
  PRINT = draw_noop,
  LDRAW_ORG = draw_noop,
  CATEGORY = draw_noop,
  PREVIEW = draw_noop,
  KEYWORD = draw_noop,
  edge = draw_edge,
  line = draw_line,
  tri = draw_noop,
  quad = draw_noop,
  outline = draw_outline,
  color_outline = draw_color_outline
}

local function draw_ldraw(root)
  setup_view()
  traverse_ldraw(root, DRAW_CALLBACKS)
end


load_chunks()
local ldr_pyramid = loadfile("ldr_pyramid.lua")
draw_ldraw(ldr_pyramid)
