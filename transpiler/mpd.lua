-- MPD FILE/NOFILE/!DATA handling.

local MPD_PREFIX = "^%s*0%s+"
local MPD_LINE_PREFIX = "%s*0%s+"

-- Match an MPD meta at the start of any source line.

local function has_line(src, pat)
  return src:match("^" .. pat) or src:match("\n" .. pat)
end

-- Detect one MPD meta anywhere in the source.

local function has_mpd_line(src, pat)
  return has_line(src, MPD_LINE_PREFIX .. pat)
end

-- MPD support is content-based, not extension-based.

function has_mpd_meta(src)
  return has_mpd_line(src, "FILE%s+")
    or has_mpd_line(src, "!DATA%s+")
    or has_mpd_line(src, "NOFILE%s*")
end

-- Extract the FILE target exactly as written in the MPD.

local function mpd_file_name(line)
  return line:match(MPD_PREFIX .. "FILE%s+(.+)%s*$")
end

-- Extract the output name of a !DATA payload.

local function mpd_data_name(line)
  return line:match(MPD_PREFIX .. "!DATA%s+(.+)%s*$")
end

-- NOFILE closes the current FILE or !DATA block.

local function mpd_is_nofile(line)
  return line:match(MPD_PREFIX .. "NOFILE%s*$")
end

-- Payload lines use the MPD "0 !:" continuation prefix.

local function mpd_data_payload(line)
  return line:match(MPD_PREFIX .. "!:%s*(.*)$")
end

-- Root lines go to the requested output path.

local function new_mpd(out_path)
  return {
    out_path = out_path,
    root = { }
  }
end

-- Outside FILE blocks, source is preserved as Lua comments.

local function mpd_comment(st, line)
  local old = out
  out = st.root
  if line == "" then
    emit_blank()
  else
    emit_comment(line)
  end
  out = old
end

-- A FILE block becomes its own transpiled Lua chunk.

local function mpd_write_file(st)
  local path = lua_output_path(st.out_path, st.name)
  local lines = transpile_lines(st.lines)
  write_lines(path, lines, "w")
end

-- !DATA blocks are decoded and written as binary files.

local function mpd_write_data(st)
  local path = data_output_path(st.out_path, st.name)
  write_binary(path, b64_decode(table.concat(st.lines)))
end

-- Finish the current block before another one starts.

local function mpd_close(st)
  if st.kind == "file" then
    mpd_write_file(st)
  elseif st.kind == "data" then
    mpd_write_data(st)
  end
  st.kind, st.name, st.lines = nil, nil, nil
end

-- Start collecting LDraw lines for a named MPD file.

local function mpd_start_file(st, name)
  mpd_close(st)
  st.kind = "file"
  st.name = name
  st.lines = { }
end

-- Start collecting base64 payload lines.

local function mpd_start_data(st, name)
  mpd_close(st)
  st.kind = "data"
  st.name = name
  st.lines = { }
end

-- Route a non-meta line according to the active block.

local function mpd_add_line(st, line)
  if st.kind == "file" then
    table.insert(st.lines, line)
  elseif st.kind == "data" then
    table.insert(st.lines, mpd_data_payload(line))
  else
    mpd_comment(st, line)
  end
end

-- FILE switches output to a new generated Lua file.

local function mpd_file_meta(st, line)
  local name = mpd_file_name(line)
  if name then
    mpd_start_file(st, name)
    return true
  end
end

-- !DATA switches output to a decoded binary file.

local function mpd_data_meta(st, line)
  local name = mpd_data_name(line)
  if name then
    mpd_start_data(st, name)
    return true
  end
end

-- NOFILE returns output to the requested root file.

local function mpd_nofile_meta(st, line)
  if mpd_is_nofile(line) then
    mpd_close(st)
    return true
  end
end

-- Try the MPD block-control metas in spec order.

local function mpd_start_meta(st, line)
  return mpd_file_meta(st, line)
    or mpd_data_meta(st, line)
    or mpd_nofile_meta(st, line)
end

-- Process one physical line of an MPD package.

local function mpd_line(st, line)
  if mpd_start_meta(st, line) then
    return
  end
  mpd_add_line(st, line)
end

-- Split an MPD package into its generated outputs.

function process_mpd(src, out_path)
  local st = new_mpd(out_path)
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    mpd_line(st, line)
  end
  mpd_close(st)
  write_lines(out_path, st.root, "w")
end
