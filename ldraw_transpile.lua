-- LDraw to Lua transpiler.
-- Converts LDraw files and MPD packages into Lua chunks for
-- the Compy edgetest runtime.

-- Matrix comparison tolerance per the LDraw spec.

TOL = 0.0005

-- Column limit enforced by the Compy editor. All emit helpers
-- wrap long output so that no generated line exceeds it.

COLUMN_LIMIT = 64

-- LDraw colour code that means "use the current edge colour of
-- the enclosing scope" rather than a specific colour. Lines and
-- optional lines with this code transpile to the unsigned DSL
-- name (edge, outline); any other colour uses the q-variant.

EDGE_COLOUR = 24

-- Load the transpiler modules. Shared entry points remain
-- global; implementation helpers are file-local inside modules.
-- orthogonal_bases comes before transpiler.types because the
-- latter uses orthogonal_base when initialising its tables.

require "transpiler.util"
require "transpiler.emit"
require "transpiler.colors"
color_id = { }
require "transpiler.ldraw_color_id"
require "orthogonal_bases"
require "transpiler.types"
require "transpiler.base64"
require "transpiler.mpd"

-- Main: read the input file, normalise line endings, process
-- each line, and write the result.

local function normalise_source(src)
  return src:gsub("\13\n", "\n"):gsub("\13", "\n")
end

local function source_lines(src)
  local lines = { }
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end
  return lines
end

function transpile_lines(lines)
  out = { }
  for i = 1, #lines do
    process_line(lines[i])
  end
  return out
end

local function transpile_source(src)
  return transpile_lines(source_lines(src))
end

local function main(in_path, out_path)
  local src = normalise_source(read_file(in_path))
  if has_mpd_meta(src) then
    process_mpd(src, out_path)
  else
    write_lines(out_path, transpile_source(src), "w")
  end
end

if arg and arg[1] and arg[2] then
  main(arg[1], arg[2])
  print("OK: " .. arg[1] .. " -> " .. arg[2])
end

