std = "lua54"
read_globals = {
  "reaper",
  "gfx",
  "ImGui",
}

files["tests/*.lua"] = {
  globals = {
    "reaper",
    "gfx",
    "ImGui",
  },
}
