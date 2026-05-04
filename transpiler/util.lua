-- Formatting and I/O utilities for the LDraw transpiler.
-- Defines global helpers used by the code generation and
-- LDraw-parsing modules.

-- Output buffer shared by all emit helpers. Each emit_* call
-- appends strings to it; main writes it out at the end.

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
    table.insert(t, word)
  end
  return t
end

-- Rewrite an LDraw reference into a Lua identifier.
-- Subpart prefix "s/" is omitted; resolution paths are kept.

function mangle_ref(name)
  name = name:gsub("\\", "/")
  name = name:gsub("^parts/", "")
  name = name:gsub("^p/", "")
  name = name:gsub("^s/", "")
  local base, ext = name:match("^(.+)%.([^.]+)$")
  base = base:gsub("[^%w_]", "_")
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
  table.insert(out, "")
end

-- Append a word to a comment line, adding a space separator if
-- the line is not empty.

local function append_word(line, word)
  if line == "" then
    return word
  end
  return line .. " " .. word
end

-- Check whether appending word to current keeps the resulting
-- line (with its prefix) within the 64-column limit.

local function fits_comment(prefix, current, word)
  local full = prefix .. append_word(current, word)
  return #full <= COLUMN_LIMIT
end

-- Wrap a long comment at word boundaries. The first line starts
-- at column 0; continuations indent by two spaces before "-- ".

local function emit_wrapped_comment(rest)
  local prefix, line = "-- ", ""
  for word in rest:gmatch("%S+") do
    if fits_comment(prefix, line, word) then
      line = append_word(line, word)
    else
      table.insert(out, prefix .. line)
      prefix, line = "  -- ", word
    end
  end
  if line ~= "" then
    table.insert(out, prefix .. line)
  end
end

-- Append a comment line preserving original text verbatim when
-- it fits; otherwise word-wrap it.

function emit_comment(rest)
  if rest == "" then
    table.insert(out, "--")
  elseif #rest + 3 <= COLUMN_LIMIT then
    table.insert(out, "-- " .. rest)
  else
    emit_wrapped_comment(rest)
  end
end

-- Open a file or die with a clear message. Shared by read_file
-- and write_file so that the "check for nil" pattern is not
-- repeated.

local function open_or_die(path, mode)
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

function write_lines(path, lines, mode)
  local f = open_or_die(path, mode or "w")
  f:write(table.concat(lines, "\n"))
  f:write("\n")
  f:close()
end

function write_file(path)
  write_lines(path, out, "w")
end

function write_binary(path, data)
  local f = open_or_die(path, "wb")
  f:write(data)
  f:close()
end

local function dir_name(path)
  return path:match("^(.*)/[^/]*$") or "."
end

local function join_path(dir, name)
  if dir == "." then
    return name
  end
  return dir .. "/" .. name
end

function lua_output_path(out_path, name)
  local file = mangle_ref(name) .. ".lua"
  return join_path(dir_name(out_path), file)
end

function data_output_path(out_path, name)
  return join_path(dir_name(out_path), name:gsub("\\", "/"))
end
