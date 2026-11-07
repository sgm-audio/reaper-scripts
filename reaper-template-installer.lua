-- REAPER Script Suite Installer
-- @description Installs the bundled ReaScripts and workflow documentation into the REAPER resource path
-- @author Scott Mills
-- @version 4.0
-- This installer copies files only. It does not alter the open project, keyboard
-- shortcuts, toolbars, FX chains, or REAPER preferences.

local script_version = "4.0"
local script_dir = debug.getinfo(1, "S").source:match("@(.+[/\\])") or ""
local install_path = reaper.GetResourcePath() .. "/Scripts/ScottMills/"
local documentation_path = install_path .. "Documentation/"

local SCRIPTS = {
  "Reaper AI Control Hub.lua",
  "SGM_Professional_Session_Builder.lua",
  "SGM_plugin_development_blueprint.lua",
  "VALIDATE-ALL-SCRIPTS.lua",
  "list-all-available-plugins.lua",
  "phase-alignment-tool.lua",
  "plugin-wrapper.lua",
  "reaper-template-installer.lua",
  "rule-of-30-plugin-presets.lua",
  "scan-real-plugins.lua",
  "signal-chain-presets.lua",
}

local DOCUMENTS = {
  "README.md",
  "AUDIT.md",
  "CHANGELOG.md",
  "RULE-OF-30-COMPLETE-WORKFLOW.md",
  "SUNO_REAPER_WORKFLOW.md",
  "LICENSE",
}

local function msg(message)
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end

local function normalized(path)
  local value = path:gsub("\\", "/"):gsub("/+$", ""):lower()
  return value
end

local function copy_file(source_dir, filename, destination_dir)
  local source_path = source_dir .. filename
  local destination_path = destination_dir .. filename
  if normalized(source_path) == normalized(destination_path) then
    return true, "already installed"
  end

  local source, source_error = io.open(source_path, "rb")
  if not source then return false, source_error end
  local content = source:read("*a")
  source:close()
  if content == nil then return false, "could not read source file" end

  local destination, destination_error = io.open(destination_path, "wb")
  if not destination then return false, destination_error end
  local ok, write_error = destination:write(content)
  destination:close()
  if not ok then return false, write_error end
  return true
end

local function install_group(files, destination_dir, failures, copied)
  reaper.RecursiveCreateDirectory(destination_dir, 0)
  for _, filename in ipairs(files) do
    local ok, result = copy_file(script_dir, filename, destination_dir)
    if ok then
      table.insert(copied, destination_dir .. filename)
      msg("Installed: " .. destination_dir .. filename)
    else
      local message = filename .. ": " .. tostring(result)
      table.insert(failures, message)
      msg("ERROR: " .. message)
    end
  end
end

local function write_manifest(copied)
  local manifest_path = install_path .. "installed-files.txt"
  local file, open_error = io.open(manifest_path, "w")
  if not file then return false, open_error end
  file:write("SGM REAPER Scripts installer v" .. script_version .. "\n")
  file:write("Installed " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
  for _, path in ipairs(copied) do file:write(path .. "\n") end
  file:close()
  return true
end

local function main()
  msg("=== SGM REAPER SCRIPT SUITE INSTALLER v" .. script_version .. " ===")
  if script_dir == "" then
    reaper.ShowMessageBox("Could not determine the installer's source directory.", "Installation Failed", 0)
    return false
  end

  local answer = reaper.ShowMessageBox(
    "Install " .. #SCRIPTS .. " ReaScripts and " .. #DOCUMENTS ..
      " documents to:\n" .. install_path ..
      "\n\nExisting files with the same names will be replaced. Your open project and REAPER settings will not be changed.",
    "Install SGM REAPER Scripts", 1)
  if answer ~= 1 then
    msg("Installation cancelled.")
    return false
  end

  local failures, copied = {}, {}
  install_group(SCRIPTS, install_path, failures, copied)
  install_group(DOCUMENTS, documentation_path, failures, copied)
  if #failures == 0 then
    local ok, manifest_error = write_manifest(copied)
    if not ok then table.insert(failures, "installed-files.txt: " .. tostring(manifest_error)) end
  end

  if #failures > 0 then
    reaper.ShowMessageBox(
      #failures .. " file(s) could not be installed:\n\n" .. table.concat(failures, "\n") ..
      "\n\nSee the REAPER console for details.",
      "Installation — Partial Failure", 0)
    return false
  end

  reaper.ShowMessageBox(
    "Installed " .. #copied .. " files successfully.\n\n" ..
    "Open Actions → Show action list → Load ReaScript to register scripts from:\n" ..
    install_path .. "\n\nNo project templates or FX chains are bundled.",
    "Installation Complete", 0)
  msg("Installation complete: " .. #copied .. " files")
  return true
end

_G.SGMScriptInstaller = {copy_file = copy_file, scripts = SCRIPTS, documents = DOCUMENTS}
main()
