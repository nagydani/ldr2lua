-- Base64 decoding for MPD !DATA blocks.

local B64 = { }

-- Build the alphabet lookup once at module load time.

do
  local chars
  chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  chars = chars .. "abcdefghijklmnopqrstuvwxyz"
  chars = chars .. "0123456789+/"
  for i = 1, #chars do
    B64[chars:sub(i, i)] = i - 1
  end
end

-- Padding contributes zero bits to the 24-bit group.

local function b64_value(text, i)
  local c = text:sub(i, i)
  if c == "=" then
    return 0
  else
    return B64[c]
  end
end

-- Pack one 4-character group into a 24-bit integer.

local function b64_chunk(text, i)
  local a = b64_value(text, i)
  local b = b64_value(text, i + 1)
  local c = b64_value(text, i + 2)
  local d = b64_value(text, i + 3)
  return a * 262144 + b * 4096 + c * 64 + d
end

-- A padded group emits fewer bytes.

local function b64_chunk_len(text, i)
  if text:sub(i + 2, i + 3) == "==" then
    return 1
  elseif text:sub(i + 3, i + 3) == "=" then
    return 2
  end
  return 3
end

-- Extract one byte from the packed group.

local function b64_push(out, n, div)
  local byte = math.floor(n / div) % 256
  table.insert(out, string.char(byte))
end

-- Decode one base64 group into one, two, or three bytes.

local function b64_push_chunk(out, text, i)
  local n = b64_chunk(text, i)
  local len = b64_chunk_len(text, i)
  b64_push(out, n, 65536)
  if len == 2 then
    b64_push(out, n, 256)
  elseif len == 3 then
    b64_push(out, n, 256)
    b64_push(out, n, 1)
  end
end

-- Decode a complete MPD !DATA payload.

function b64_decode(text)
  local out = { }
  text = text:gsub("%s", "")
  for i = 1, #text, 4 do
    b64_push_chunk(out, text, i)
  end
  return table.concat(out)
end

