-- Focused Lua 5.4 regressions. Run from repository root:
--   lua5.4 tests/lua_regression.lua

local failures = {}
local checks = 0
local function check(condition, message)
  checks = checks + 1
  if not condition then table.insert(failures, message) end
end

local temp_root = os.tmpname()
os.remove(temp_root)
local function make_dir(path)
  os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
end
make_dir(temp_root .. "/Effects")

local function write_file(path, content)
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()
end
local function read_file(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return content
end

write_file(temp_root .. "/reaper-vstplugins64.ini",
  '[vstcache]\nDelay.vst3=ABC,1,"Delay, Wide (Vendor)"\nEQ.dll=DEF,1,"Equalizer"\n')
write_file(temp_root .. "/Effects/utility", "desc:Utility")
write_file(temp_root .. "/Effects/include.jsfx-inc", "// include")

local tracks = {}
local sends_created = 0
local last_parallel_volume = nil
local parallel_send_pending = false
local file_lists = {
  [temp_root .. "/Effects"] = {"utility", "include.jsfx-inc"},
  ["/test"] = {"Legacy.DLL"},
}
local directory_lists = {["/test"] = {"Bundle.vst3"}}

reaper = {}
function reaper.GetResourcePath() return temp_root end
function reaper.GetProjectPath() return temp_root end
function reaper.GetOS() return "Linux" end
function reaper.ShowConsoleMsg(_) end
function reaper.ClearConsole() end
function reaper.ShowMessageBox(_, _, _) return 0 end
function reaper.EnumerateFiles(path, index)
  local list = file_lists[path] or {}
  return list[index + 1]
end
function reaper.EnumerateSubdirectories(path, index)
  local list = directory_lists[path] or {}
  return list[index + 1]
end
function reaper.RecursiveCreateDirectory(path, _) make_dir(path) return 1 end
function reaper.file_exists(path)
  local file = io.open(path, "r")
  if file then file:close() return true end
  return false
end
function reaper.time_precise() return os.clock() end
function reaper.GetMasterTrack(_) return {name = "Master"} end
function reaper.TrackFX_GetCount(_) return 0 end
function reaper.GetLastTouchedFX() return false, 0, -1, -1 end
function reaper.CountSelectedTracks(_) return 0 end
function reaper.CountTracks(_) return #tracks end
function reaper.InsertTrackAtIndex(index, _)
  table.insert(tracks, index + 1, {name = "", values = {}})
end
function reaper.GetTrack(_, index) return tracks[index + 1] end
function reaper.GetSetMediaTrackInfo_String(track, key, value, set)
  if set then track.name = value end
  return true, track.name
end
function reaper.GetTrackName(track) return true, track.name end
function reaper.SetMediaTrackInfo_Value(track, key, value)
  assert(type(value) == "number", key .. " must be numeric")
  track.values[key] = value
end
function reaper.SetTrackColor(_, _) end
function reaper.ColorToNative(r, g, b) return r * 65536 + g * 256 + b end
-- TrackFX_AddByName(track, fxname, recFX, instantiate): recFX is the boolean
-- record-input-FX flag (not an install flag); instantiate: negative=always add,
-- 0=query only, positive=add if missing. Returns -1 on failure.
-- The previous stub returned 0 unconditionally, masking the bug where
-- recFX=true with instantiate omitted queries the record-FX chain and never
-- installs stock FX. recFX is tested for truthiness so the buggy call
-- TrackFX_AddByName(track, name, 1) (recFX=1 number) is also rejected.
function reaper.TrackFX_AddByName(_track, _fxname, recFX, instantiate)
  if instantiate == nil then instantiate = 0 end
  if recFX and instantiate == 0 then return -1 end
  return 0
end
function reaper.CreateTrackSend(_, destination)
  sends_created = sends_created + 1
  parallel_send_pending = destination.name:find("Parallel", 1, true) ~= nil
  return sends_created - 1
end
function reaper.SetTrackSendInfo_Value(_, _, _, key, value)
  if key == "D_VOL" and parallel_send_pending then
    last_parallel_volume = value
    parallel_send_pending = false
  end
end
function reaper.Undo_BeginBlock() end
function reaper.Undo_EndBlock(_, _) end
function reaper.PreventUIRefresh(_) end
function reaper.TrackList_AdjustWindows(_) end
function reaper.UpdateArrange() end

gfx = {mouse_x = 0, mouse_y = 0, x = 0, y = 0}
function gfx.showmenu(_) return 0 end
ImGui = {}

-- Cache parsing, JSFX discovery, categories, and escaped JSON.
assert(loadfile("list-all-available-plugins.lua"))()
local Inventory = _G.SGMPluginInventory
check(Inventory ~= nil, "inventory module was not exported")
local inventory_json = read_file(temp_root .. "/plugin_inventory.json")
check(inventory_json:find("Delay, Wide (Vendor)", 1, true) ~= nil, "cache parser lost quoted comma name")
check(inventory_json:find('"utility"', 1, true) ~= nil, "extensionless JSFX was not inventoried")
check(inventory_json:find("include.jsfx-inc", 1, true) == nil, "JSFX include was listed as a plugin")
local scanner = Inventory:new()
local fixture = {
  total_count = 1,
  by_type = {vst = {{name = 'Quote " \\ line\n', path = "C:\\\\P.vst3", type = "vst3", category = "Utility"}},
    vst3 = {}, clap = {}, au = {}, lv2 = {}, js = {}},
  by_category = {Utility = {}},
}
local escaped_path = temp_root .. "/escaped.json"
check(scanner:exportToJSON(fixture, escaped_path), "inventory JSON export failed")
local escaped = read_file(escaped_path)
check(escaped:find('\\"', 1, true) ~= nil, "quotes were not JSON escaped")
check(escaped:find('\\n', 1, true) ~= nil, "newlines were not JSON escaped")

-- PluginDB must round-trip its complete flat schema without data loss.
assert(loadfile("plugin-wrapper.lua"))()
local db = _G.SGMPluginWrapper.PluginDB:new()
db.last_scan = 12345
db:addPlugin({name = 'A "quoted" \\ EQ', path = "C:\\\\Plugins\\A.vst3", format = "VST3",
  vendor = "Vendor", category = "EQ", param_count = 7})
local decoded = db:parseJSON(db:toJSON())
check(decoded and #decoded.plugins == 1, "plugin database did not round-trip")
check(decoded and decoded.last_scan == 12345, "plugin database timestamp changed")
check(decoded and decoded.plugins[1].name == db.plugins[1].name, "plugin name escaping broke round-trip")
check(decoded and decoded.plugins[1].path == db.plugins[1].path, "plugin path escaping broke round-trip")
check(decoded and decoded.plugins[1].param_count == 7, "plugin parameter count was lost")

-- Filesystem bundles use portable paths and are not recursively unpacked.
assert(loadfile("scan-real-plugins.lua"))()
local found = _G.SGMRealPluginScanner.scanDirectory("/test")
check(#found == 2, "filesystem scanner missed a file or VST3 bundle")
local portable = true
for _, plugin in ipairs(found) do
  if plugin.path:find("\\", 1, true) then portable = false end
end
check(portable, "filesystem scanner produced Windows paths on Linux")

-- Build and implement every session type against the in-memory REAPER API.
assert(loadfile("SGM_Professional_Session_Builder.lua"))()
local SessionBuilder = _G.SGMSessionBuilder.AdvancedSessionBuilder:new()
local full = assert(SessionBuilder:buildSessionFromAnalysis("full_production", "stock"))
check(#full.tracks == 25, "full production track count is stale")
check(#full.routing.sends == 31, "full production routing is incomplete")
local engine = _G.SGMSessionBuilder.SessionImplementationEngine:new()
local implemented, implementation_error = engine:implementSession(full)
check(implemented, "session implementation failed: " .. tostring(implementation_error))
check(#tracks == 25, "session implementation created wrong track count")
check(sends_created == 31, "session implementation created wrong send count")
check(#engine.fx_warnings == 0, "stock FX additions produced warnings: " .. table.concat(engine.fx_warnings, ", "))
check(last_parallel_volume and math.abs(last_parallel_volume - (10 ^ (-6 / 20))) < 0.000001, "parallel dB was not converted to linear gain")
check(tracks[1].values.B_MAINSEND == 0, "routed input still sends directly to master")
check(tracks[25].values.B_MAINSEND == 1, "master track does not send to hardware master")
for _, session_type in ipairs({"mixing", "mastering", "stem_separation"}) do
  local session, err = SessionBuilder:buildSessionFromAnalysis(session_type, "no_fx")
  check(session ~= nil, "missing session builder " .. session_type .. ": " .. tostring(err))
end

-- Installer manifest must contain only files that actually exist.
assert(loadfile("reaper-template-installer.lua"))()
for _, filename in ipairs(_G.SGMScriptInstaller.scripts) do
  local file = io.open(filename, "r")
  check(file ~= nil, "installer references missing script: " .. filename)
  if file then file:close() end
end
for _, filename in ipairs(_G.SGMScriptInstaller.documents) do
  local file = io.open(filename, "r")
  check(file ~= nil, "installer references missing document: " .. filename)
  if file then file:close() end
end
for _, filename in ipairs(_G.SGMScriptInstaller.plugin_files) do
  local file = io.open("plugin/" .. filename, "r")
  check(file ~= nil, "installer references missing plugin source: " .. filename)
  if file then file:close() end
end

-- The blueprint must generate an exact, complete copy of the canonical project.
reaper.ShowMessageBox = function(_, _, _) return 1 end
assert(loadfile("SGM_plugin_development_blueprint.lua"))()
reaper.ShowMessageBox = function(_, _, _) return 0 end
local development = _G.SGMPluginDevelopment
check(development ~= nil, "plugin development module was not exported")
if development then
  for _, filename in ipairs(development.project_files) do
    local generated = read_file(temp_root .. "/SGM_AI_Plugin_Suite/" .. filename)
    local canonical = read_file("plugin/" .. filename)
    check(generated == canonical, "generated plugin source differs: " .. filename)
  end
  check(not development.create_development_project(), "generator overwrote an existing project")
end

-- Remaining entry points must not crash with no menu selection/confirmation.
for _, filename in ipairs({
  "Reaper AI Control Hub.lua",
  "SGM_plugin_development_blueprint.lua",
  "phase-alignment-tool.lua",
  "rule-of-30-plugin-presets.lua",
  "signal-chain-presets.lua",
  "VALIDATE-ALL-SCRIPTS.lua",
}) do
  local chunk, load_error = loadfile(filename)
  check(chunk ~= nil, filename .. " syntax: " .. tostring(load_error))
  if chunk then
    local ok, runtime_error = pcall(chunk)
    check(ok, filename .. " runtime: " .. tostring(runtime_error))
  end
end

os.execute("rm -rf '" .. temp_root:gsub("'", "'\\''") .. "'")
if #failures > 0 then
  for _, failure in ipairs(failures) do io.stderr:write("FAIL: " .. failure .. "\n") end
  io.stderr:write(string.format("%d/%d Lua regression checks failed\n", #failures, checks))
  os.exit(1)
end
print(string.format("All %d Lua regression checks passed", checks))
