-- Edgetest entry point.

TOL = 0.0005

require "linalg"
require "ldraw_colors"
require "ldraw"
require "picking"

local gfx = love.graphics

local D = 1000
local CENTER_X = 512
local CENTER_Y = 300
local VIEW_M = Mat.unit(3)
local VIEW_T = Vec.d3(0, 0, 0)
local SELECTED_PART
local MODEL
local ROOT_COLOR = Yellow

local function perspective(x, y, z)
  local dz = D / z
  return CENTER_X + x * dz, CENTER_Y + y * dz
end

local function apply_view(p)
  local g = p:tr(VIEW_M)
  g:acc(VIEW_T)
  return g
end

local function screen_point(x, y, z)
  local g = apply_view(apply_global(Vec.d3(x, y, z)))
  return perspective(g:c3())
end

-- Type 2 segment in the current gfx colour.

local function draw_line_segment(x1, y1, z1, x2, y2, z2)
  local sx1, sy1 = screen_point(x1, y1, z1)
  local sx2, sy2 = screen_point(x2, y2, z2)
  gfx.line(sx1, sy1, sx2, sy2)
end

-- line/color_outline drop their LDraw colour parameter.

local function draw_line(_, x1, y1, z1, x2, y2, z2)
  draw_line_segment(x1, y1, z1, x2, y2, z2)
end

local function same_side(ax, ay, bx, by, cx, cy, dx, dy)
  local vx, vy = bx - ax, by - ay
  local s1 = vx * (cy - ay) - vy * (cx - ax)
  local s2 = vx * (dy - ay) - vy * (dx - ax)
  return 0 <= s1 * s2
end

-- Type 5 conditional edge in the current gfx colour.

local function draw_outline_with(x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  local sx1, sy1 = screen_point(x1, y1, z1)
  local sx2, sy2 = screen_point(x2, y2, z2)
  local sx3, sy3 = screen_point(x3, y3, z3)
  local sx4, sy4 = screen_point(x4, y4, z4)
  if same_side(sx1, sy1, sx2, sy2, sx3, sy3, sx4, sy4) then
    gfx.line(sx1, sy1, sx2, sy2)
  end
end

local function draw_outline(x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  draw_outline_with(x1, y1, z1, x2, y2, z2, x3, y3, z3,
    x4, y4, z4)
end

local function draw_color_outline(_, x1, y1, z1, x2, y2, z2,
    x3, y3, z3, x4, y4, z4)
  draw_outline_with(x1, y1, z1, x2, y2, z2, x3, y3, z3,
    x4, y4, z4)
end

local function ignore()
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

-- Draw pass: ignore faces and render only wireframe primitives.

local DRAW_CALLBACKS = {
  STEP = ignore,
  CLEAR = ignore,
  PAUSE = ignore,
  SAVE = ignore,
  WRITE = ignore,
  PRINT = ignore,
  LDRAW_ORG = ignore,
  CATEGORY = ignore,
  PREVIEW = ignore,
  KEYWORD = ignore,
  edge = draw_line_segment,
  line = draw_line,
  tri = ignore,
  quad = ignore,
  outline = draw_outline,
  color_outline = draw_color_outline
}

local function draw_ldraw(root)
  traverse_ldraw(root, DRAW_CALLBACKS, ROOT_COLOR)
end

local function draw_ref(part)
  ref(part.ldraw, ROOT_COLOR, part.x, part.y, part.z,
    part.a, part.b, part.c, part.d, part.e, part.f,
    part.g, part.h, part.i)
end

local function view_to_ldraw(v)
  return Vec.d3(v:dot(VIEW_M[1]), v:dot(VIEW_M[2]),
    v:dot(VIEW_M[3]))
end

-- Invert the fixed view/projection to cast an LDraw-space ray.

local function mouse_ray(mx, my)
  local origin = view_to_ldraw(Vec.d3(-VIEW_T:c(1), -VIEW_T:c(2),
    -VIEW_T:c(3)))
  local dir = view_to_ldraw(Vec.d3((mx - CENTER_X) / D,
    (my - CENTER_Y) / D, 1))
  return origin, dir
end

local function pick_part(mx, my)
  local origin, dir = mouse_ray(mx, my)
  return find_part(MODEL, origin:c(1), origin:c(2), origin:c(3),
    dir:c(1), dir:c(2), dir:c(3))
end

local function draw_scene()
  setup_view()
  gfx.setColor(0, 0, 0, 1)
  draw_ldraw(MODEL)
  if SELECTED_PART then
    gfx.setColor(1, 0, 0, 1)
    draw_ldraw(function() draw_ref(SELECTED_PART) end)
  end
end

-- Mouse changes selection; love.draw renders the current state.

function love.mousepressed(mx, my)
  SELECTED_PART = pick_part(mx, my)
end

function love.draw()
  gfx.clear(1, 1, 1, 1)
  draw_scene()
end

load_chunks()
MODEL = loadfile("ldr_pyramid.lua")

