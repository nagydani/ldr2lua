-- LDraw colour parsing and lookup.

local FINISH = {
  CHROME = true,
  PEARLESCENT = true,
  RUBBER = true,
  MATTE_METALLIC = true,
  METAL = true
}

local CURRENT_COLOUR = {
  [16] = true,
  [24] = true
}

-- Quote generated Lua string literals consistently.

local function quote(s)
  return ("%q"):format(s)
end

-- Turn an LDraw colour name into a Lua identifier.

local function color_name(name)
  local s = name:gsub("[^%w_]", "_")
  if s:match("^%d") then
    s = "C_" .. s
  end
  return s
end

-- Replace a numeric LDraw colour code with its symbol.

function color_ref(code)
  local name = color_id[tonumber(code)]
  if not name then
    error("unknown colour code: " .. tostring(code))
  end
  return name
end

-- Find an LDConfig attribute by token name.

local function find_key(tokens, key, first)
  for i = first or 1, #tokens do
    if tokens[i] == key then
      return i
    end
  end
end

-- Read the value following an LDConfig attribute.

local function attr(tokens, key, first)
  local i = find_key(tokens, key, first)
  if i then
    return tokens[i + 1]
  end
end

-- Accept both #RRGGBB and 0xRRGGBB notation.

local function hex_start(hex)
  if hex:sub(1, 1) == "#" then
    return 2
  else
    return 3
  end
end

-- Convert one hex byte to a 0..1 channel.

local function hex_byte(hex, first)
  local s = hex:sub(first, first + 1)
  return tonumber(s, 16) / 255
end

-- Convert VALUE or EDGE colour data to a Lua array.

local function hex_values(hex, alpha)
  local first = hex_start(hex)
  local t = { }
  table.insert(t, fmt_num(hex_byte(hex, first)))
  table.insert(t, fmt_num(hex_byte(hex, first + 2)))
  table.insert(t, fmt_num(hex_byte(hex, first + 4)))
  if alpha then
    table.insert(t, fmt_num(tonumber(alpha) / 255))
  end
  return t
end

-- Emit a multi-line Lua table field.

local function emit_array(name, values, pad)
  pad = pad or "  "
  table.insert(out, pad .. name .. " = {")
  for _, v in ipairs(values) do
    table.insert(out, pad .. "  " .. v .. ",")
  end
  table.insert(out, pad .. "},")
end

-- Emit one scalar table field.

local function emit_field(name, value, pad)
  pad = pad or "  "
  table.insert(out, pad .. name .. " = " .. value .. ",")
end

-- Skip absent optional LDConfig attributes.

local function emit_optional_field(name, value, pad)
  if value then
    emit_field(name, value, pad)
  end
end

-- Keep the transpiler lookup beside each colour definition.

local function emit_color_id(code, name)
  local line = "color_id[" .. code .. "] = "
  table.insert(out, line .. quote(name))
end

-- Emit code, value, edge, and luminance fields.

local function emit_color_head(tokens, name, code)
  local alpha = attr(tokens, "ALPHA")
  emit_color_id(code, name)
  table.insert(out, name .. " = {")
  emit_field("code", code)
  emit_array("value", hex_values(attr(tokens, "VALUE"), alpha))
  emit_array("edge", hex_values(attr(tokens, "EDGE")))
  emit_optional_field("luminance", attr(tokens, "LUMINANCE"))
end

-- Emit simple finish markers such as CHROME or RUBBER.

local function emit_finish(tokens)
  for _, tok in ipairs(tokens) do
    if FINISH[tok] then
      emit_field("finish", quote(tok))
    end
  end
end

-- Glitter and speckle use either SIZE or min/max size.

local function emit_grain_size(tokens, mi)
  local size = attr(tokens, "SIZE", mi)
  if size then
    emit_field("size", size, "    ")
  else
    emit_field("minsize", attr(tokens, "MINSIZE", mi), "    ")
    emit_field("maxsize", attr(tokens, "MAXSIZE", mi), "    ")
  end
end

-- Emit nested VALUE data for GLITTER and SPECKLE.

local function emit_grain_value(tokens, mi)
  local alpha = attr(tokens, "ALPHA", mi)
  local value = attr(tokens, "VALUE", mi)
  local lum = attr(tokens, "LUMINANCE", mi)
  emit_array("value", hex_values(value, alpha), "    ")
  emit_optional_field("luminance", lum, "    ")
end

-- Emit a GLITTER or SPECKLE material table.

local function emit_grain(kind, tokens, mi)
  table.insert(out, "  " .. kind:lower() .. " = {")
  emit_grain_value(tokens, mi)
  emit_field("fraction", attr(tokens, "FRACTION", mi), "    ")
  local vf = attr(tokens, "VFRACTION", mi)
  emit_optional_field("vfraction", vf, "    ")
  emit_grain_size(tokens, mi)
  table.insert(out, "  },")
end

-- FABRIC stores a named fabric variant.

local function emit_fabric(tokens, mi)
  local fabric = tokens[mi + 2]
  if fabric then
    emit_field("fabric", quote(fabric))
  end
end

-- Emit the MATERIAL branch of an LDConfig colour.

local function emit_material(tokens)
  local mi = find_key(tokens, "MATERIAL")
  if not mi then
    return
  end
  local kind = tokens[mi + 1]
  emit_field("finish", quote("MATERIAL"))
  emit_field("material", quote(kind))
  if kind == "FABRIC" then
    emit_fabric(tokens, mi)
  else
    emit_grain(kind, tokens, mi)
  end
end

-- Emit one complete !COLOUR definition.

function emit_colour(rest)
  local tokens = tokenize(rest)
  local name = color_name(tokens[1])
  local code = attr(tokens, "CODE")
  if CURRENT_COLOUR[tonumber(code)] then
    return
  end
  color_id[tonumber(code)] = name
  emit_color_head(tokens, name, code)
  emit_finish(tokens)
  emit_material(tokens)
  table.insert(out, "}")
end
