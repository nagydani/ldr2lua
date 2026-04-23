-- LDraw to Lua transpiler.

-- Converts one LDraw file (.ldr/.dat/.mpd) into a Lua chunk of

-- top-level DSL calls for the Compy edgetest runtime.

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

-- Output buffer shared by all emit helpers.

local insert = table.insert
out = { }

-- Format a number as a compact string: integer when the value

-- is integral, otherwise a fixed-point form with trailing zeros

-- stripped.

function fmt_num(n)
  if n == math.floor(n) then
    return tostring(math.floor(n))
  end
  local s = string.format("%.4f", n)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

-- Split a line into whitespace-delimited tokens.

function tokenize(line)
  local t = { }
  for word in line:gmatch("%S+") do
    insert(t, word)
  end
  return t
end

-- Strip prefix ending with "\" from an LDraw file reference and

-- rewrite "name.ext" as "ext_name".

function mangle_ref(name)
  local bs = name:find("\\[^\\]*$")
  if bs then
    name = name:sub(bs + 1)
  end
  local base, ext = name:match("^(.+)%.([^.]+)$")
  return ext:lower() .. "_" .. base
end

-- Approximate equality within TOL.

function approx_eq(a, b)
  return math.abs(a - b) < TOL
end

-- Append a blank line, collapsing consecutive blanks.

function emit_blank()
  if out[#out] == "" then
    return 
  end
  insert(out, "")
end

-- Comment formatting.

-- Append a word to a comment line, adding a space separator if

-- the line is not empty.

function append_word(line, word)
  if line == "" then
    return word
  end
  return line .. " " .. word
end

-- Check whether appending word to current keeps the resulting

-- line (with its prefix) within the 64-column limit.

function fits_comment(prefix, current, word)
  local full = prefix .. append_word(current, word)
  return #full <= COLUMN_LIMIT
end

-- Wrap a long comment at word boundaries. The first line starts

-- at column 0; continuations indent by two spaces before "-- ".

function emit_wrapped_comment(rest)
  local prefix, line = "-- ", ""
  for word in rest:gmatch("%S+") do
    if fits_comment(prefix, line, word) then
      line = append_word(line, word)
    else
      insert(out, prefix .. line)
      prefix, line = "  -- ", word
    end
  end
  if line ~= "" then
    insert(out, prefix .. line)
  end
end

-- Append a comment line preserving original text verbatim when

-- it fits; otherwise word-wrap it.

function emit_comment(rest)
  if rest == "" then
    insert(out, "--")
    return 
  end
  if #rest + 3 <= COLUMN_LIMIT then
    insert(out, "-- " .. rest)
  else
    emit_wrapped_comment(rest)
  end
end

-- Function call emission.

-- Try to emit a function call on a single line; return true on

-- success, false if it would exceed 64 columns.

function try_inline_call(name, args)
  local inline = name .. "(" .. table.concat(args, ", ") .. ")"
  if #inline > COLUMN_LIMIT then
    return false
  end
  insert(out, inline)
  return true
end

-- Emit a function call spread across multiple lines, one

-- argument per line with trailing commas.

function emit_multi_call(name, args)
  insert(out, name .. "(")
  for i = 1, #args do
    local tail = ","
    if i == #args then
      tail = ""
    end
    insert(out, "  " .. args[i] .. tail)
  end
  insert(out, ")")
end

-- Emit a function call inline if it fits, multiline otherwise.

function emit_call(name, args)
  if not try_inline_call(name, args) then
    emit_multi_call(name, args)
  end
end

-- Type 0 meta commands.

-- A factory that returns a handler emitting a no-argument call

-- with the given DSL name.

function make_nullary_emitter(name)
  return function()
    emit_call(name, { })
  end
end

-- A factory that returns a handler emitting a call with one

-- quoted string argument (the captured text).

function make_text_emitter(name)
  return function(msg)
    emit_call(name, { string.format("%q", msg) })
  end
end

-- Type 0 patterns as two parallel tables. Adding another meta

-- pattern is one line in each table.

META_PATTERN = {
  "^STEP%s*$",
  "^CLEAR%s*$",
  "^PAUSE%s*$",
  "^SAVE%s*$",
  "^WRITE%s+(.*)$",
  "^PRINT%s+(.*)$"
}

META_HANDLER = {
  make_nullary_emitter("STEP"),
  make_nullary_emitter("CLEAR"),
  make_nullary_emitter("PAUSE"),
  make_nullary_emitter("SAVE"),
  make_text_emitter("WRITE"),
  make_text_emitter("PRINT")
}

-- Dispatch a Type 0 line: match its text against each pattern

-- in order, invoking the first matching handler. Lines that

-- match no pattern fall through to the comment emitter.

function handle_type0(rest)
  for i = 1, #META_PATTERN do
    local cap = rest:match(META_PATTERN[i])
    if cap then
      META_HANDLER[i](cap)
      return 
    end
  end
  emit_comment(rest)
end

-- Type 1 matrix shape dispatch.

-- Check whether the nine matrix entries match a fixed pattern

-- of constants. The pattern is a 9-element table with the same

-- index convention as m.

function matches_matrix(m, pattern)
  for i = 1, 9 do
    if not approx_eq(m[i], pattern[i]) then
      return false
    end
  end
  return true
end

-- Factory that packs nine matrix entries into a 9-element

-- pattern table without an expanded table literal.

function make_pattern(a, b, c, d, e, f, g, h, i)
  local p = { }
  p[1], p[2], p[3] = a, b, c
  p[4], p[5], p[6] = d, e, f
  p[7], p[8], p[9] = g, h, i
  return p
end

-- Fixed rotation patterns for compass-direction placement, as

-- three parallel tables.

PLACE_PATTERN = {
  make_pattern(1, 0, 0, 0, 1, 0, 0, 0, 1),
  make_pattern(0, 0, 1, 0, 1, 0, -1, 0, 0),
  make_pattern(-1, 0, 0, 0, 1, 0, 0, 0, -1),
  make_pattern(0, 0, -1, 0, 1, 0, 1, 0, 0)
}

PLACE_NAME = {
  "placeN",
  "placeE",
  "placeS",
  "placeW"
}

-- Check whether m matches a placeN/E/S/W pattern; return the

-- matching DSL name or nil if no match.

function match_place(m)
  for i = 1, #PLACE_PATTERN do
    if matches_matrix(m, PLACE_PATTERN[i]) then
      return PLACE_NAME[i]
    end
  end
  return nil
end

-- The twist shape is [a, 0, c; 0, 1, 0; -c, 0, a]. It has two

-- free scalars, a and c, so it cannot be matched against a

-- constant pattern.

function is_twist(m)
  return approx_eq(m[2], 0)
       and approx_eq(m[4], 0)
       and approx_eq(m[5], 1)
       and approx_eq(m[6], 0)
       and approx_eq(m[8], 0)
       and approx_eq(m[1], m[9])
       and approx_eq(m[3], -m[7])
end

-- Append each of the given numeric arguments to target as a

-- formatted string. Used wherever several fmt_num inserts would

-- otherwise repeat the same line verbatim.

function insert_nums(target, ...)
  for i = 1, select("#", ...) do
    insert(target, fmt_num(select(i, ...)))
  end
end

-- Append source[from..to] to target as formatted strings. The

-- table-backed counterpart to insert_nums.

function insert_all(target, source, from, to)
  for i = from, to do
    insert(target, fmt_num(source[i]))
  end
end

-- Parse a Type 1 line. Tokens: "1", colour, tx, ty, tz, nine

-- matrix entries, filename.

function parse_type1(tokens)
  local q = tonumber(tokens[2])
  local x = tonumber(tokens[3])
  local y = tonumber(tokens[4])
  local z = tonumber(tokens[5])
  local m = { }
  for i = 1, 9 do
    m[i] = tonumber(tokens[5 + i])
  end
  return q, x, y, z, m, tokens[15]
end

-- Build the head of the argument list common to every Type 1

-- emission: the sub-part reference, colour, and translation.

function build_type1_head(fname, q, x, y, z)
  local head = { }
  insert(head, mangle_ref(fname))
  insert_nums(head, q, x, y, z)
  return head
end

-- Emit a twist call if the matrix has the twist shape, or a

-- ref call with all nine matrix coefficients otherwise.

function emit_twist_or_ref(m, args)
  if is_twist(m) then
    insert_nums(args, m[1], m[3])
    emit_call("twist", args)
    return
  end
  insert_all(args, m, 1, 9)
  emit_call("ref", args)
end

-- Emit a Type 1 line: dispatch to placeN/E/S/W if the matrix

-- matches a compass pattern, otherwise hand off to the

-- twist-or-ref tail.

function handle_type1(tokens)
  local q, x, y, z, m, fname = parse_type1(tokens)
  local args = build_type1_head(fname, q, x, y, z)
  local place = match_place(m)
  if place then
    emit_call(place, args)
    return 
  end
  emit_twist_or_ref(m, args)
end

-- Types 2 through 5.

-- Convert tokens[from..to] to formatted number strings.

function nums_from_tokens(tokens, from, to)
  local nums = { }
  for i = from, to do
    insert(nums, fmt_num(tonumber(tokens[i])))
  end
  return nums
end

-- Shared logic for Types 2 and 5: colour 24 uses the unsigned

-- DSL name, any other colour uses the explicit-colour name.

function emit_colour_variant(tokens, last, name_24, name_q)
  local q = tonumber(tokens[2])
  local coords = nums_from_tokens(tokens, 3, last)
  if q == EDGE_COLOUR then
    emit_call(name_24, coords)
  else
    insert(coords, 1, fmt_num(q))
    emit_call(name_q, coords)
  end
end

-- Factory for Types 3 and 4, which take a colour plus a fixed

-- number of coordinates and emit a single call.

function make_poly_handler(last, name)
  return function(tokens)
    emit_call(name, nums_from_tokens(tokens, 2, last))
  end
end

function handle_type2(tokens)
  emit_colour_variant(tokens, 8, "edge", "line")
end

function handle_type5(tokens)
  emit_colour_variant(tokens, 14, "outline", "color_outline")
end

TYPE_HANDLER = {
  ["1"] = handle_type1,
  ["2"] = handle_type2,
  ["3"] = make_poly_handler(11, "tri"),
  ["4"] = make_poly_handler(14, "quad"),
  ["5"] = handle_type5
}

-- Line dispatch.

-- Handle a Type 0 line: strip the leading "0" token and pass

-- the rest to handle_type0 as raw text.

function process_zero(trimmed)
  local rest = trimmed:sub(2):match("^%s*(.-)$")
  handle_type0(rest)
end

-- Dispatch a non-blank trimmed line by its first token.

function dispatch_line(trimmed)
  local first = trimmed:match("^(%S+)")
  if first == "0" then
    process_zero(trimmed)
    return 
  end
  local handler = TYPE_HANDLER[first]
  if handler then
    handler(tokenize(trimmed))
  end
end

-- Process one input line: blank lines collapse via emit_blank,

-- non-blank lines go through dispatch_line.

function process_line(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  if trimmed == "" then
    emit_blank()
  else
    dispatch_line(trimmed)
  end
end

-- I/O and entry point.

-- Open a file or die with a clear message. Shared by read_file

-- and write_file so that the "check for nil" pattern is not

-- repeated.

function open_or_die(path, mode)
  local f = io.open(path, mode)
  if not f then
    error("cannot open: " .. path)
  end
  return f
end

function read_file(path)
  local f = open_or_die(path, "r")
  local s = f:read("*all")
  f:close()
  return s
end

function write_file(path)
  local f = open_or_die(path, "w")
  f:write(table.concat(out, "\n"))
  f:write("\n")
  f:close()
end

-- Main: read the input file, normalise line endings, process

-- each line, and write the result.

function main(in_path, out_path)
  local src = read_file(in_path)
  src = src:gsub("\13\n", "\n"):gsub("\13", "\n")
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    process_line(line)
  end
  write_file(out_path)
end

if arg and arg[1] and arg[2] then
  main(arg[1], arg[2])
  print("OK: " .. arg[1] .. " -> " .. arg[2])
end
