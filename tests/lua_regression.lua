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
local is_windows = package.config:sub(1, 1) == "\\"
local function make_dir(path)
  if is_windows then
    os.execute('mkdir "' .. tostring(path):gsub("/", "\\") .. '"')
  else
    os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
  end
end
local function remove_dir(path)
  if is_windows then
    os.execute('rmdir /s /q "' .. tostring(path):gsub("/", "\\") .. '"')
  else
    os.execute("rm -rf '" .. tostring(path):gsub("'", "'\\''") .. "'")
  end
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
write_file(temp_root .. "/reaper-auplugins64.ini",
  '[aucache]\nAUComp.component=AU1,1,"AU Comp"\n')
write_file(temp_root .. "/reaper-lv2plugins64.ini",
  '[lv2cache]\nLV2Eq.lv2=LV1,1,"LV2 EQ"\n')
write_file(temp_root .. "/reaper-clap-linux-x86_64.ini",
  '[clapcache]\nSynth.clap=CL1,1,"CLAP Synth"\n')
write_file(temp_root .. "/Effects/utility", "desc:Utility")
write_file(temp_root .. "/Effects/include.jsfx-inc", "// include")

local tracks = {}
local sends_created = 0
local last_parallel_volume = nil
local parallel_send_pending = false
local file_lists = {
  [temp_root] = {"reaper-vstplugins64.ini", "reaper-auplugins64.ini", "reaper-lv2plugins64.ini", "reaper-clap-linux-x86_64.ini"},
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
function reaper.DeleteTrack(tr)
  for i = #tracks, 1, -1 do
    if tracks[i] == tr then table.remove(tracks, i) break end
  end
end
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
check(inventory_json:find("AU Comp", 1, true) ~= nil, "AU cache was not inventoried")
check(inventory_json:find("LV2 EQ", 1, true) ~= nil, "LV2 cache was not inventoried")
check(inventory_json:find("CLAP Synth", 1, true) ~= nil, "CLAP cache was not inventoried")
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

-- PluginDB must round-trip its complete flat schema without data loss, including \uXXXX escapes.
assert(loadfile("plugin-wrapper.lua"))()
local db = _G.SGMPluginWrapper.PluginDB:new()
db.last_scan = 12345
db:addPlugin({name = 'A "quoted" \\ EQ\007\\u0007', path = "C:\\\\Plugins\\A.vst3", format = "VST3",
  vendor = "Vendor", category = "EQ", param_count = 7})
local decoded = db:parseJSON(db:toJSON())
check(decoded and #decoded.plugins == 1, "plugin database did not round-trip")
check(decoded and decoded.last_scan == 12345, "plugin database timestamp changed")
check(decoded and decoded.plugins[1].name == db.plugins[1].name, "plugin name escaping (including \\uXXXX) broke round-trip")
check(decoded and decoded.plugins[1].path == db.plugins[1].path, "plugin path escaping broke round-trip")
check(decoded and decoded.plugins[1].param_count == 7, "plugin parameter count was lost")

-- plugin-wrapper.lua: macOS-arm64 paths, Linux .so, macOS .clap bundles, and multi-dot filenames.
local prev_get_os = reaper.GetOS
reaper.GetOS = function() return "macOS-arm64" end
local arm_paths = _G.SGMPluginWrapper.getScanPaths()
local has_mac_path = false
for _, p in ipairs(arm_paths) do
  if p == "/Library/Audio/Plug-Ins/VST3" then has_mac_path = true end
end
check(has_mac_path, "plugin-wrapper did not recognize macOS-arm64")
reaper.GetOS = prev_get_os

local pw_scanner = _G.SGMPluginWrapper.PluginScanner:new()
local multi_dot = pw_scanner:analyzePlugin("/usr/lib/vst3/FabFilter Pro-Q 3.5.vst3")
check(multi_dot and multi_dot.name == "FabFilter Pro-Q 3.5" and multi_dot.format == "VST3",
  "plugin-wrapper truncated multi-dot plugin name: " .. tostring(multi_dot and multi_dot.name))
local linux_so = pw_scanner:analyzePlugin("/usr/lib/lxvst/DragonflyRoomReverb.so")
check(linux_so and linux_so.name == "DragonflyRoomReverb" and linux_so.format == "VST2",
  "plugin-wrapper did not classify Linux .so as VST2")
file_lists["/test-pw"] = {"LinuxPlug.so"}
directory_lists["/test-pw"] = {"MacSynth.clap"}
local pw_files = pw_scanner:getFilesInDirectory("/test-pw")
check(#pw_files == 2, "plugin-wrapper missed Linux .so or macOS .clap bundle")

-- Filesystem bundles use portable paths and are not recursively unpacked, including .so and .clap.
file_lists["/test"] = {"Legacy.DLL", "LinuxVST.so"}
directory_lists["/test"] = {"Bundle.vst3", "Bundle.clap"}
assert(loadfile("scan-real-plugins.lua"))()
local found = _G.SGMRealPluginScanner.scanDirectory("/test")
check(#found == 4, "filesystem scanner missed .dll, .so, .vst3, or .clap bundle (got " .. #found .. ")")
local found_by_name = {}
for _, plugin in ipairs(found) do found_by_name[plugin.name] = plugin.type end
check(found_by_name["LinuxVST"] == "vst2", "scan-real-plugins did not classify .so as vst2")
check(found_by_name["Bundle"] ~= nil, "scan-real-plugins missed bundle entries")
local portable = true
for _, plugin in ipairs(found) do
  if plugin.path:find("\\", 1, true) then portable = false end
end
check(portable, "filesystem scanner produced Windows paths on Linux")
reaper.GetOS = function() return "macOS-arm64" end
local scan_arm_paths = _G.SGMRealPluginScanner.get_scan_paths()
local scan_has_mac = false
for _, p in ipairs(scan_arm_paths) do
  if p == "/Library/Audio/Plug-Ins/CLAP" then scan_has_mac = true end
end
check(scan_has_mac, "scan-real-plugins did not recognize macOS-arm64")
reaper.GetOS = prev_get_os

-- list-all-available-plugins.lua: real AU & CLAP schemas + multi-plugin shell dedup.
write_file(temp_root .. "/real-au.ini", "Apple: AUBandpass=<1234>\nDisabled: BadPlug=<!0>\n")
local real_au = scanner:parseCache(temp_root .. "/real-au.ini", "au")
check(#real_au == 1 and real_au[1].name == "Apple: AUBandpass" and real_au[1].type == "au",
  "AU real schema parsing failed")
write_file(temp_root .. "/real-clap.ini", "[Surge.clap]\nmtime=12345\norg.surge.xt=Surge XT\norg.surge.fx=Surge XT FX\n")
local real_clap = scanner:parseCache(temp_root .. "/real-clap.ini", "clap")
check(#real_clap == 2 and real_clap[1].uid == "org.surge.xt" and real_clap[2].uid == "org.surge.fx",
  "CLAP real schema parsing failed for multi-plugin bundle")

-- rule-of-30-plugin-presets.lua: hard-tuned ordering, word-boundary OH, case-insensitivity, new branches.
local presets = assert(loadfile("rule-of-30-plugin-presets.lua"))()
local tuned_chain = presets.getChainForTrack("Lead Vocal (Hard-Tuned)")
check(tuned_chain and tuned_chain.name == "Lead Vocal (Hard-Tuned)",
  "Hard-Tuned vocal track must map to lead_tuned, not lead_core")
check(presets.getChainForTrack("JOHN") == nil,
  "JOHN must not falsely match OH overheads")
local oh_chain = presets.getChainForTrack("Drum OH L")
check(oh_chain and oh_chain.name == "Overheads",
  "Drum OH L must match Overheads")
local scream_chain = presets.getChainForTrack("Scream Throw")
check(scream_chain and scream_chain.name == "Scream Throw",
  "Scream Throw must match scream_throw")
local talking_chain = presets.getChainForTrack("Texture Guitars (Talking)")
check(talking_chain and talking_chain.name == "Texture Guitars (Talking)",
  "Texture Guitars (Talking) must match texture_talking")
local glitch_chain = presets.getChainForTrack("Data Stream Bus")
check(glitch_chain and glitch_chain.name == "Data Stream Bus",
  "Data Stream Bus must match glitch.data_stream")
local master_chain = presets.getChainForTrack("Master Bus")
check(master_chain and master_chain.name == "Mastering Chain",
  "Master Bus must match master.mastering")

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
check(#engine.fx_warnings == 0, "stock FX additions produced warnings: " .. table.concat(engine.fx_warnings, ", "))
check(sends_created == 31, "session implementation created wrong send count")
check(last_parallel_volume and math.abs(last_parallel_volume - (10 ^ (-6 / 20))) < 0.000001, "parallel dB was not converted to linear gain")
check(tracks[1].values.B_MAINSEND == 0, "routed input still sends directly to master")
check(tracks[25].values.B_MAINSEND == 1, "master track does not send to hardware master")
for _, session_type in ipairs({"mixing", "mastering", "stem_separation"}) do
  local session, err = SessionBuilder:buildSessionFromAnalysis(session_type, "no_fx")
  check(session ~= nil, "missing session builder " .. session_type .. ": " .. tostring(err))
end

-- Session builder with pre-existing user tracks in project (adversarial track offset test)
local pre_existing_count = 5
tracks = {}
for i = 1, pre_existing_count do
  table.insert(tracks, {name = "User Stem " .. i, values = {B_MAINSEND = 1}})
end
sends_created = 0
local pre_engine = _G.SGMSessionBuilder.SessionImplementationEngine:new()
local pre_session = assert(SessionBuilder:buildSessionFromAnalysis("full_production", "stock"))
local pre_ok, pre_err = pre_engine:implementSession(pre_session)
check(pre_ok, "session implementation in pre-existing project failed: " .. tostring(pre_err))
check(#tracks == pre_existing_count + 25, "total tracks must be pre-existing + session tracks")
-- Ensure the first 5 tracks remain untouched and retain their original names and settings
for i = 1, pre_existing_count do
  check(tracks[i].name == "User Stem " .. i, "existing track " .. i .. " was overwritten or corrupted")
  check(tracks[i].values.B_MAINSEND == 1, "existing track " .. i .. " mainsend was corrupted")
end
-- Verify newly appended tracks are properly named and routed
check(tracks[pre_existing_count + 1].name == "Drums Input", "first created track name mismatch: " .. tostring(tracks[pre_existing_count + 1].name))
check(tracks[pre_existing_count + 25].name == "Master", "last created track name mismatch: " .. tostring(tracks[pre_existing_count + 25].name))
check(sends_created == 31, "sends created in pre-existing project mismatch")

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

-- rule-of-30-plugin-presets.lua: unit tests for findPlugin() and getChainForTrack() edge cases.
local fx_count_calls = 0
local mock_track = {
  fx = {
    {ok = false, name = "Unreadable"},
    {ok = true, name = "VST3: Pro-Q 3 (FabFilter)"},
    {ok = true, name = "VST3: CLA-76 Bluey (Waves)"},
    {ok = true, name = "VST3: H-EQ (Waves)"},
  }
}
local prev_fx_count = reaper.TrackFX_GetCount
local prev_fx_name = reaper.TrackFX_GetFXName
reaper.TrackFX_GetCount = function(tr)
  fx_count_calls = fx_count_calls + 1
  return tr and tr.fx and #tr.fx or 0
end
reaper.TrackFX_GetFXName = function(tr, idx, _)
  local entry = tr.fx[idx + 1]
  if not entry then return false, "" end
  return entry.ok, entry.name
end
check(presets.findPlugin(nil, "Pro-Q 3") == nil, "findPlugin(nil, name) must return nil")
check(presets.findPlugin(mock_track, nil) == nil, "findPlugin(track, nil) must return nil")
check(presets.findPlugin(mock_track, "") == nil, "findPlugin(track, '') must return nil")
check(presets.findPlugin(mock_track, 123) == nil, "findPlugin(track, non-string) must return nil")
check(fx_count_calls == 0, "findPlugin must guard invalid inputs before querying TrackFX_GetCount")
check(presets.findPlugin({fx = {}}, "Pro-Q 3") == nil, "findPlugin on empty track must return nil")
check(presets.findPlugin(mock_track, "pro-q 3") == 1, "findPlugin must match lowercase query to 0-based index 1")
check(presets.findPlugin(mock_track, "PRO-Q 3") == 1, "findPlugin must match uppercase query to 0-based index 1")
check(presets.findPlugin(mock_track, "(FabFilter)") == 1, "findPlugin must match plain Lua pattern metacharacters")
check(presets.findPlugin(mock_track, "cla-76") == 2, "findPlugin must match hyphenated plugin name")
check(presets.findPlugin(mock_track, "H-EQ") == 3, "findPlugin must find last plugin on track")
check(presets.findPlugin(mock_track, "Unreadable") == nil, "findPlugin must ignore entries where TrackFX_GetFXName returns false")
check(presets.findPlugin(mock_track, "NonExistent") == nil, "findPlugin must return nil when plugin absent")
reaper.TrackFX_GetCount = prev_fx_count
reaper.TrackFX_GetFXName = prev_fx_name

check(presets.getChainForTrack(nil) == nil, "getChainForTrack(nil) must return nil")
check(presets.getChainForTrack("") == nil, "getChainForTrack('') must return nil")
check(presets.getChainForTrack(42) == nil, "getChainForTrack(number) must return nil")
check(presets.getChainForTrack({}) == nil, "getChainForTrack(table) must return nil")
check(presets.getChainForTrack("ATOM") == nil, "ATOM must not falsely match toms")
check(presets.getChainForTrack("Unmatched Track") == nil, "Unmatched Track must return nil")
local chain_cases = {
  {"KICK IN", "Kick In (Click/Attack)"},
  {"kick out", "Kick Out (Body)"},
  {"Kick Sub", "Kick Sub (Sine Trigger)"},
  {"SNARE TOP", "Snare Top"},
  {"snare bottom", "Snare Bottom"},
  {"GLITCH SNARE", "Glitch Snare (Duplicate)"},
  {"Rack Tom 1", "Toms (Rack/Floor)"},
  {"FLOOR TOMS", "Toms (Rack/Floor)"},
  {"ROOM MONO", "Room Mono (Crushed)"},
  {"BASS DI", "Bass DI (The Lows)"},
  {"bass amp", "Bass Amp (The Mids)"},
  {"BASS FUZZ", "Bass Fuzz (The Highs)"},
  {"bass synth", "Bass Synth Layer"},
  {"RHYTHM L1", "Rhythm Guitars L/R (100%)"},
  {"rhythm r2", "Rhythm Guitars L2/R2 (80%)"},
  {"OCTAVE LEAD", "Octave Leads"},
  {"THE SCRAPE", "The Scrape"},
  {"IMPACTS", "Impacts/Boom"},
  {"WHITE NOISE RISER", "White Noise Risers"},
  {"GLITCH BUS", "Glitch Bus Master"},
  {"LEAD VOCAL", "Lead Vocal (Core)"},
  {"LEAD VOCAL (HARD-TUNED)", "Lead Vocal (Hard-Tuned)"},
  {"DEMON LAYER", "Demon Layer"},
  {"TELEPHONIC", "Telephonic Layer"},
  {"WHISPER L", "Whisper Tracks L/R"},
  {"SSL BUS COMP", "SSL Bus Compressor"},
  {"TAPE SAT", "Tape Saturation"},
}
for _, pair_case in ipairs(chain_cases) do
  local matched = presets.getChainForTrack(pair_case[1])
  check(matched and matched.name == pair_case[2],
    "getChainForTrack(" .. pair_case[1] .. ") expected " .. pair_case[2] .. ", got " .. tostring(matched and matched.name))
end

-- Parameterized multi-OS path tests across Linux, Win64, Win32, OSX64, and macOS-arm64.
assert(loadfile("Reaper AI Control Hub.lua"))()
local function verify_paths(label, paths, is_win, expected_substrings)
  check(type(paths) == "table" and #paths > 0, label .. ": must return non-empty path list")
  local seen = {}
  for _, p in ipairs(paths) do
    check(type(p) == "string" and p ~= "", label .. ": every path must be non-empty string")
    check(p:find("\\", 1, true) == nil, label .. ": path must use portable forward slashes: " .. tostring(p))
    check(p:find("//", 1, true) == nil, label .. ": path must not contain double slashes: " .. tostring(p))
    check(not p:match("/$"), label .. ": path must not end with trailing slash: " .. tostring(p))
    local key = is_win and p:lower() or p
    check(not seen[key], label .. ": duplicate path detected: " .. tostring(p))
    seen[key] = true
  end
  for _, needle in ipairs(expected_substrings) do
    local matched = false
    for _, p in ipairs(paths) do
      if p == needle then matched = true; break end
    end
    check(matched, label .. ": missing expected path " .. needle)
  end
end

local orig_getenv = os.getenv
local orig_getos = reaper.GetOS
local multi_os_cases = {
  {
    os_name = "Linux",
    is_win = false,
    env = {HOME = "/home/scott/"},
    scan_expect = {"/usr/lib/vst3", "/usr/lib/lxvst", "/home/scott/.vst3", "/home/scott/.clap"},
    wrap_expect = {"/usr/lib/vst3", "/usr/lib/lxvst", "/home/scott/.vst3", "/home/scott/.clap"},
    hub_expect = {"/home/scott/.vst3/AI", "/usr/lib/vst3/AI", temp_root:gsub("\\", "/") .. "/UserPlugins/AI"},
    expected_python = "python3",
    expected_ext = "",
  },
  {
    os_name = "Win64",
    is_win = true,
    env = {
      ProgramFiles = "D:\\Apps\\",
      ["ProgramFiles(x86)"] = "D:\\Apps (x86)\\",
      CommonProgramFiles = "D:\\Common\\",
      LOCALAPPDATA = "C:\\Users\\Scott\\AppData\\Local\\",
    },
    scan_expect = {"D:/Apps/VSTPlugins", "D:/Apps (x86)/VSTPlugins", "D:/Common/VST3", "D:/Common/CLAP", "C:/Users/Scott/AppData/Local/Programs/Common/VST3"},
    wrap_expect = {"D:/Apps/VSTPlugins", "D:/Apps (x86)/VSTPlugins", "D:/Common/VST3", "D:/Common/CLAP"},
    hub_expect = {"D:/Apps/AudioMovers/OmniBridge", "D:/Common/VST3/AI", "D:/Apps/ReWire", temp_root:gsub("\\", "/") .. "/UserPlugins/AI"},
    expected_python = "python",
    expected_ext = ".exe",
  },
  {
    -- Win32 where ProgramFiles == ProgramFiles(x86) to verify deduplication!
    os_name = "Win32",
    is_win = true,
    env = {
      ProgramFiles = "C:\\Program Files\\",
      ["ProgramFiles(x86)"] = "c:/program files",
      CommonProgramFiles = "C:\\Program Files\\Common Files\\",
    },
    scan_expect = {"C:/Program Files/VSTPlugins", "C:/Program Files/Steinberg/VSTPlugins", "C:/Program Files/Common Files/VST3", "C:/Program Files/Common Files/CLAP"},
    wrap_expect = {"C:/Program Files/VSTPlugins", "C:/Program Files/Steinberg/VSTPlugins", "C:/Program Files/Common Files/VST3", "C:/Program Files/Common Files/CLAP"},
    hub_expect = {"C:/Program Files/AudioMovers/OmniBridge", "C:/Program Files/Common Files/VST3/AI", "C:/Program Files/ReWire"},
    expected_python = "python",
    expected_ext = ".exe",
  },
  {
    os_name = "OSX64",
    is_win = false,
    env = {HOME = "/Users/scott/"},
    scan_expect = {"/Library/Audio/Plug-Ins/VST3", "/Library/Audio/Plug-Ins/Components", "/Users/scott/Library/Audio/Plug-Ins/VST3", "/Users/scott/Library/Audio/Plug-Ins/CLAP"},
    wrap_expect = {"/Library/Audio/Plug-Ins/VST3", "/Library/Audio/Plug-Ins/Components", "/Users/scott/Library/Audio/Plug-Ins/VST3", "/Users/scott/Library/Audio/Plug-Ins/CLAP"},
    hub_expect = {"/Applications/AudioMovers/OmniBridge.app", "/Users/scott/Library/Audio/Plug-Ins/VST3/AI"},
    expected_python = "python3",
    expected_ext = "",
  },
  {
    os_name = "macOS-arm64",
    is_win = false,
    env = {}, -- nil HOME fallback must omit per-user paths cleanly
    scan_expect = {"/Library/Audio/Plug-Ins/VST3", "/Library/Audio/Plug-Ins/Components", "/Library/Audio/Plug-Ins/CLAP"},
    wrap_expect = {"/Library/Audio/Plug-Ins/VST3", "/Library/Audio/Plug-Ins/Components", "/Library/Audio/Plug-Ins/CLAP"},
    hub_expect = {"/Applications/AudioMovers/OmniBridge.app", temp_root:gsub("\\", "/") .. "/UserPlugins/AI"},
    expected_python = "python3",
    expected_ext = "",
  },
}

for _, spec in ipairs(multi_os_cases) do
  reaper.GetOS = function() return spec.os_name end
  rawset(os, "getenv", function(key) return spec.env[key] end)

  local scan_paths = _G.SGMRealPluginScanner.get_scan_paths()
  verify_paths("scan-real-plugins[" .. spec.os_name .. "]", scan_paths, spec.is_win, spec.scan_expect)

  local wrap_paths = _G.SGMPluginWrapper.getScanPaths()
  verify_paths("plugin-wrapper[" .. spec.os_name .. "]", wrap_paths, spec.is_win, spec.wrap_expect)

  local launcher = _G.ExternalToolLauncher:new()
  verify_paths("ai-control-hub[" .. spec.os_name .. "]", launcher.tool_paths, spec.is_win, spec.hub_expect)

  local stem_cfg = launcher:_get_tool_config("stem_separation", "/proj")
  local master_cfg = launcher:_get_tool_config("mastering", "/proj")
  check(stem_cfg.executable == spec.expected_python,
    "ai-control-hub[" .. spec.os_name .. "] stem executable expected " .. spec.expected_python .. ", got " .. tostring(stem_cfg.executable))
  check(master_cfg.executable == ("omnibridge" .. spec.expected_ext),
    "ai-control-hub[" .. spec.os_name .. "] mastering executable expected omnibridge" .. spec.expected_ext)
end

-- Verify Win64 nil-env fallbacks produce valid default Windows paths with zero duplicates.
reaper.GetOS = function() return "Win64" end
rawset(os, "getenv", function(_) return nil end)
verify_paths("scan-real-plugins[Win64-nil-env]", _G.SGMRealPluginScanner.get_scan_paths(), true,
  {"C:/Program Files/VSTPlugins", "C:/Program Files (x86)/VSTPlugins", "C:/Program Files/Common Files/VST3"})
verify_paths("plugin-wrapper[Win64-nil-env]", _G.SGMPluginWrapper.getScanPaths(), true,
  {"C:/Program Files/VSTPlugins", "C:/Program Files (x86)/VSTPlugins", "C:/Program Files/Common Files/VST3"})
verify_paths("ai-control-hub[Win64-nil-env]", _G.ExternalToolLauncher:new().tool_paths, true,
  {"C:/Program Files/AudioMovers/OmniBridge", "C:/Program Files/Common Files/VST3/AI"})

rawset(os, "getenv", orig_getenv)
reaper.GetOS = orig_getos

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

remove_dir(temp_root)
if #failures > 0 then
  for _, failure in ipairs(failures) do io.stderr:write("FAIL: " .. failure .. "\n") end
  io.stderr:write(string.format("%d/%d Lua regression checks failed\n", #failures, checks))
  os.exit(1)
end
print(string.format("All %d Lua regression checks passed", checks))
