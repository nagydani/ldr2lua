-- Lua call emission for the LDraw transpiler. Builds DSL calls
-- (edge, ref, quad, ...) into the shared output buffer.

-- Try to emit a function call on a single line; return true on
-- success, false if it would exceed the column limit.

function try_inline_call(name, args)
  local inline = name .. "(" .. table.concat(args, ", ") .. ")"
  if #inline > COLUMN_LIMIT then
    return false
  end
  table.insert(out, inline)
  return true
end

-- Emit a function call spread across multiple lines, one
-- argument per line with trailing commas.

function emit_multi_call(name, args)
  table.insert(out, name .. "(")
  for i = 1, #args do
    local tail = ","
    if i == #args then
      tail = ""
    end
    table.insert(out, "  " .. args[i] .. tail)
  end
  table.insert(out, ")")
end

-- Emit a function call inline if it fits, multiline otherwise.

function emit_call(name, args)
  if not try_inline_call(name, args) then
    emit_multi_call(name, args)
  end
end

-- Append each of the given numeric arguments to target as a
-- formatted string. Used wherever several fmt_num inserts would
-- otherwise repeat the same line verbatim.

function insert_nums(target, ...)
  for i = 1, select("#", ...) do
    table.insert(target, fmt_num(select(i, ...)))
  end
end

-- Append source[from..to] to target as formatted strings. The
-- table-backed counterpart to insert_nums.

function insert_all(target, source, from, to)
  for i = from, to do
    table.insert(target, fmt_num(source[i]))
  end
end

-- Convert tokens[from..to] to formatted number strings, parsing
-- each via tonumber first.

function nums_from_tokens(tokens, from, to)
  local nums = { }
  for i = from, to do
    table.insert(nums, fmt_num(tonumber(tokens[i])))
  end
  return nums
end
