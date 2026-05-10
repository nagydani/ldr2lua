-- LDraw line-type handling for the transpiler. Covers Type 0
-- meta commands, Type 1 sub-part references with matrix shape
-- dispatch, Types 2-5 drawing primitives, and the top-level
-- line dispatcher.

-- Type 0 meta commands.

-- A factory that returns a handler emitting a no-argument call
-- with the given DSL name.

local function make_nullary_emitter(name)
  return function()
    emit_call(name, { })
  end
end

-- A factory that returns a handler emitting a call with one
-- quoted string argument (the captured text).

local function make_text_emitter(name)
  return function(msg)
    emit_call(name, { string.format("%q", msg) })
  end
end

-- Emit !LDRAW_ORG: the first word becomes the argument, the
-- rest of the line is appended as a comment on the same line.
-- "Part UPDATE 2020-03" -> LDRAW_ORG("Part") -- UPDATE 2020-03

local function emit_ldraw_org(rest)
  local first, tail = rest:match("^(%S+)%s*(.*)$")
  local call = string.format("LDRAW_ORG(%q)", first)
  if tail == "" then
    table.insert(out, call)
  else
    table.insert(out, call .. " -- " .. tail)
  end
end

-- Emit !PREVIEW: 13 numeric arguments (q tx ty tz plus a 3x3
-- matrix). The arguments are space-separated on the rest of
-- the line.

local function emit_preview(rest)
  local tokens = tokenize(rest)
  local args = { color_ref(tokens[1]) }
  for i = 2, #tokens do
    table.insert(args, fmt_num(tonumber(tokens[i])))
  end
  emit_call("PREVIEW", args)
end

-- Emit !KEYWORDS: each whitespace-separated word becomes a
-- separate KEYWORD call on its own line.

local function emit_keywords(rest)
  for word in rest:gmatch("%S+") do
    emit_call("KEYWORD", { string.format("%q", word) })
  end
end

-- A factory that returns a handler emitting BFC_X(arg) call.

local function make_bfc_const(name, arg)
  return function() emit_call(name, { tostring(arg) }) end
end

-- A factory that returns a handler emitting BFC_X() call.

local function make_bfc_void(name)
  return function() emit_call(name, { }) end
end

-- INVERTNEXT sets a transpiler flag; the next Type 1 wraps the
-- emit name with BFC_INVERT(...).

local INVERT_NEXT = false

local function handle_invertnext()
  INVERT_NEXT = true
end

-- Type 0 patterns as two parallel tables. Adding another meta
-- pattern is one line in each table.

local META_PATTERN = {
  "^STEP%s*$",
  "^CLEAR%s*$",
  "^PAUSE%s*$",
  "^SAVE%s*$",
  "^WRITE%s+(.*)$",
  "^PRINT%s+(.*)$",
  "^!CATEGORY%s+(.*)$",
  "^!LDRAW_ORG%s+(.*)$",
  "^!PREVIEW%s+(.*)$",
  "^!KEYWORDS%s+(.*)$",
  "^!COLOUR%s+(.*)$",
  "^BFC%s+CERTIFY%s+CW%s*$",
  "^BFC%s+CERTIFY%s+CCW%s*$",
  "^BFC%s+CERTIFY%s*$",
  "^BFC%s+NOCERTIFY%s*$",
  "^BFC%s+CW%s+CLIP%s*$",
  "^BFC%s+CCW%s+CLIP%s*$",
  "^BFC%s+CLIP%s+CW%s*$",
  "^BFC%s+CLIP%s+CCW%s*$",
  "^BFC%s+CLIP%s*$",
  "^BFC%s+NOCLIP%s*$",
  "^BFC%s+INVERTNEXT%s*$",
  "^BFC%s+CW%s*$",
  "^BFC%s+CCW%s*$"
}

local META_HANDLER = {
  make_nullary_emitter("STEP"),
  make_nullary_emitter("CLEAR"),
  make_nullary_emitter("PAUSE"),
  make_nullary_emitter("SAVE"),
  make_text_emitter("WRITE"),
  make_text_emitter("PRINT"),
  make_text_emitter("CATEGORY"),
  emit_ldraw_org,
  emit_preview,
  emit_keywords,
  emit_colour,
  make_bfc_const("BFC_CERTIFY", -1),
  make_bfc_const("BFC_CERTIFY", 1),
  make_bfc_const("BFC_CERTIFY", 1),
  make_bfc_void("BFC_NOCERTIFY"),
  make_bfc_const("BFC_CLIP", -1),
  make_bfc_const("BFC_CLIP", 1),
  make_bfc_const("BFC_CLIP", -1),
  make_bfc_const("BFC_CLIP", 1),
  make_bfc_void("BFC_CLIP"),
  make_bfc_void("BFC_NOCLIP"),
  handle_invertnext,
  make_bfc_const("BFC", -1),
  make_bfc_const("BFC", 1)
}

-- Dispatch a Type 0 line: match its text against each pattern
-- in order, invoking the first matching handler. Lines that
-- match no pattern fall through to the comment emitter.

local function handle_type0(rest)
  for i, pat in ipairs(META_PATTERN) do
    local cap = rest:match(pat)
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

local function matches_matrix(m, pattern)
  for i = 1, 9 do
    if not approx_eq(m[i], pattern[i]) then
      return false
    end
  end
  return true
end

-- Convert LDraw row-major entries to linalg column order.

local function ldraw_to_linalg(m)
  return {
    m[1], m[4], m[7],
    m[2], m[5], m[8],
    m[3], m[6], m[9]
  }
end

-- Search the orthogonal_base table for a matrix matching m.
-- Returns the matching index 1..47 or nil if no match. The
-- table comes from orthogonal_bases.lua which is required by
-- the entry point before this module is loaded.

local function match_orthogonal(m)
  local cm = ldraw_to_linalg(m)
  for i, base in ipairs(orthogonal_base) do
    if matches_matrix(cm, base) then
      return i
    end
  end
  return nil
end

-- Map from orthogonal_base index to the name of a dedicated
-- DSL function. Indices not in this table fall through to the
-- generic place(... i) form.

local NAMED_INDEX = {
  [1] = "mirrorEW",
  [2] = "mirrorUD",
  [4] = "mirrorNS",
  [5] = "placeS",
  [17] = "placeW",
  [20] = "placeE"
}

-- The identity matrix is not present in orthogonal_base; check
-- it directly. Used to dispatch to placeN.

local function is_identity(m)
  return approx_eq(m[1], 1) and approx_eq(m[2], 0)
    and approx_eq(m[3], 0) and approx_eq(m[4], 0)
    and approx_eq(m[5], 1) and approx_eq(m[6], 0)
    and approx_eq(m[7], 0) and approx_eq(m[8], 0)
    and approx_eq(m[9], 1)
end

-- A diagonal matrix has zero off-diagonal entries and arbitrary
-- diagonal scalars (a, e, i). Maps to stretch(... a, e, i).

local function is_stretch(m)
  return approx_eq(m[2], 0) and approx_eq(m[3], 0)
    and approx_eq(m[4], 0) and approx_eq(m[6], 0)
    and approx_eq(m[7], 0) and approx_eq(m[8], 0)
end

-- The twist shape is [a, 0, c; 0, 1, 0; -c, 0, a]. It has two
-- free scalars, a and c, so it cannot be matched against a
-- constant pattern.

local function is_twist(m)
  return approx_eq(m[2], 0)
    and approx_eq(m[4], 0) and approx_eq(m[5], 1)
    and approx_eq(m[6], 0) and approx_eq(m[8], 0)
    and approx_eq(m[1], m[9]) and approx_eq(m[3], -m[7])
end

-- Return the rest of a line after count whitespace tokens.

local function line_tail(line, count)
  local tail = line
  for i = 1, count do
    tail = tail:match("^%S+%s*(.*)$")
  end
  return tail
end

-- Parse a Type 1 line. Fields: "1", colour, tx, ty, tz, nine
-- matrix entries, filename.

local function parse_type1_line(line)
  local tokens = tokenize(line)
  local q = color_ref(tokens[2])
  local x = tonumber(tokens[3])
  local y = tonumber(tokens[4])
  local z = tonumber(tokens[5])
  local m = { }
  for i = 1, 9 do
    m[i] = tonumber(tokens[5 + i])
  end
  return q, x, y, z, m, line_tail(line, 14)
end

-- Build the head of the argument list common to every Type 1
-- emission: the sub-part reference, colour, and translation.

local function build_type1_head(fname, q, x, y, z)
  local head = { }
  table.insert(head, mangle_ref(fname))
  table.insert(head, q)
  insert_nums(head, x, y, z)
  return head
end

-- Emit a Type 1 dispatch call, wrapping in BFC_INVERT if a
-- BFC INVERTNEXT meta preceded this Type 1 line.

local function emit_type1_call(name, args)
  if INVERT_NEXT then
    INVERT_NEXT = false
    name = "BFC_INVERT(" .. name .. ")"
  end
  emit_call(name, args)
end

-- Try to dispatch the matrix to a named or generic orthogonal
-- DSL function. Returns true on success, false if the matrix
-- is not one of the 47 orthogonal bases.

local function emit_orthogonal(m, args)
  local i = match_orthogonal(m)
  if not i then
    return false
  end
  local named = NAMED_INDEX[i]
  if named then
    emit_type1_call(named, args)
  else
    insert_nums(args, i)
    emit_type1_call("place", args)
  end
  return true
end

-- Emit stretch(... a, e, i) for a diagonal matrix.

local function emit_stretch(m, args)
  insert_nums(args, m[1], m[5], m[9])
  emit_type1_call("stretch", args)
end

-- Emit a twist call if the matrix has the twist shape, or a
-- ref call with all nine matrix coefficients otherwise.

local function emit_twist_or_ref(m, args)
  if is_twist(m) then
    insert_nums(args, m[1], m[3])
    emit_type1_call("twist", args)
  else
    insert_all(args, m, 1, 9)
    emit_type1_call("ref", args)
  end
end

-- Try the early dispatch paths: identity, named or generic
-- orthogonal, and stretch. Returns true on success.

local function try_named_dispatch(m, args)
  if is_identity(m) then
    emit_type1_call("placeN", args)
    return true
  elseif emit_orthogonal(m, args) then
    return true
  elseif is_stretch(m) then
    emit_stretch(m, args)
    return true
  end
  return false
end

-- Emit a Type 1 line: dispatch in order of specificity from
-- identity, through named and generic orthogonal, diagonal
-- stretch, twist, and the general ref form.

local function handle_type1_line(line)
  local q, x, y, z, m, fname = parse_type1_line(line)
  local args = build_type1_head(fname, q, x, y, z)
  if try_named_dispatch(m, args) then
    return
  end
  emit_twist_or_ref(m, args)
end

-- Types 2 through 5.

-- Shared logic for Types 2 and 5: colour EDGE_COLOUR uses the
-- unsigned DSL name, any other colour uses the q-variant.

local function emit_colour_variant(tokens, last, name_24, name_q)
  local q = tonumber(tokens[2])
  local coords = nums_from_tokens(tokens, 3, last)
  if q == EDGE_COLOUR then
    emit_call(name_24, coords)
  else
    table.insert(coords, 1, color_ref(q))
    emit_call(name_q, coords)
  end
end

-- Factory for Types 3 and 4, which take a colour plus a fixed
-- number of coordinates and emit a single call.

local function make_poly_handler(last, name)
  return function(tokens)
    local args = nums_from_tokens(tokens, 3, last)
    table.insert(args, 1, color_ref(tokens[2]))
    emit_call(name, args)
  end
end

local function handle_type2(tokens)
  emit_colour_variant(tokens, 8, "edge", "line")
end

local function handle_type5(tokens)
  emit_colour_variant(tokens, 14, "outline", "color_outline")
end

local TYPE_HANDLER = {
  ["2"] = handle_type2,
  ["3"] = make_poly_handler(11, "tri"),
  ["4"] = make_poly_handler(14, "quad"),
  ["5"] = handle_type5
}

-- Line dispatch.

-- Handle a Type 0 line: strip the leading "0" token and pass
-- the rest to handle_type0 as raw text.

local function process_zero(trimmed)
  local rest = trimmed:sub(2):match("^%s*(.-)$")
  handle_type0(rest)
end

-- Dispatch a non-blank trimmed line by its first token.

local function dispatch_line(trimmed)
  local first = trimmed:match("^(%S+)")
  local handler = TYPE_HANDLER[first]
  if first == "0" then
    return process_zero(trimmed)
  elseif first == "1" then
    return handle_type1_line(trimmed)
  elseif handler then
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
