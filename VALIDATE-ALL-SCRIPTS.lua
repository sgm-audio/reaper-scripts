-- SCRIPT VALIDATOR
-- Tests ALL Rule of 30 scripts for syntax errors BEFORE user runs them
-- Version 1.0

local scripts_to_test = {
  "rule-of-30-session-builder.lua",
  "rule-of-30-plugin-presets.lua",
  "scan-real-plugins.lua",
  "phase-alignment-tool.lua"
}

-- Get the directory where THIS validator script is located
local script_dir = debug.getinfo(1, "S").source:match("@(.+[/\\])") or ""

reaper.ClearConsole()
reaper.ShowConsoleMsg("=== SCRIPT VALIDATION SYSTEM ===\n\n")

local pass_count = 0
local fail_count = 0
local errors = {}

for _, script_name in ipairs(scripts_to_test) do
  local full_path = script_dir .. script_name

  reaper.ShowConsoleMsg("Testing: " .. script_name .. " ... ")

  -- Try to load the script
  local func, err = loadfile(full_path)

  if func then
    reaper.ShowConsoleMsg("✅ PASS\n")
    pass_count = pass_count + 1
  else
    reaper.ShowConsoleMsg("❌ FAIL\n")
    reaper.ShowConsoleMsg("  Error: " .. tostring(err) .. "\n\n")
    fail_count = fail_count + 1
    table.insert(errors, {script = script_name, error = err})
  end
end

reaper.ShowConsoleMsg("\n=== RESULTS ===\n")
reaper.ShowConsoleMsg("Passed: " .. pass_count .. "\n")
reaper.ShowConsoleMsg("Failed: " .. fail_count .. "\n")

if fail_count > 0 then
  reaper.ShowConsoleMsg("\n❌ FIX THESE ERRORS BEFORE RUNNING:\n\n")
  for _, err_info in ipairs(errors) do
    reaper.ShowConsoleMsg(err_info.script .. ":\n")
    reaper.ShowConsoleMsg("  " .. err_info.error .. "\n\n")
  end
else
  reaper.ShowConsoleMsg("\n✅ ALL SCRIPTS ARE VALID - SAFE TO RUN!\n")
end
