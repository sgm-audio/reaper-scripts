-- REAPER Script Suite Installer
-- @description Installs the bundled ReaScripts and workflow documentation into the REAPER resource path
-- @author Scott Mills
-- @version 5.0
-- This installer copies files only. It does not alter the open project, keyboard
-- shortcuts, toolbars, FX chains, or REAPER preferences. The bundled JUCE
-- sources are installed for the blueprint generator; no binary is compiled.

local script_version = "5.0"
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

local PLUGIN_FILES = {
  "CMakeLists.txt",
  "README.md",
  ".gitignore",
  "Source/PluginProcessor.h",
  "Source/PluginProcessor.cpp",
  "Source/PluginEditor.h",
  "Source/PluginEditor.cpp",
  "Tests/PluginTests.cpp",
}

local function msg(message)
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end

local function normalized(path)
  local value = path:gsub("\\", "/"):gsub("/+", "/"):gsub("/+$", ""):lower()
  return value
end

-- destination path -> previous content (string) or false if it did not exist.
local backups, backup_order = {}, {}

local function remember_original(path)
  if backups[path] ~= nil then return end
  local existing = io.open(path, "rb")
  if existing then
    backups[path] = existing:read("*a") or false
    existing:close()
    if backups[path] == false then backups[path] = "" end
  else
    backups[path] = false
  end
  table.insert(backup_order, path)
end

local function rollback_install()
  local problems = {}
  for i = #backup_order, 1, -1 do
    local path = backup_order[i]
    local previous = backups[path]
    if previous == false then
      os.remove(path)
    else
      local file = io.open(path, "wb")
      if file then
        local ok = file:write(previous)
        file:close()
        if not ok then table.insert(problems, path) end
      else
        table.insert(problems, path)
      end
    end
  end
  return problems
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

  remember_original(destination_path)
  local destination, destination_error = io.open(destination_path, "wb")
  if not destination then return false, destination_error end
  local ok, write_error = destination:write(content)
  destination:close()
  if not ok then return false, write_error end
  return true
end

local function install_group(files, destination_dir, failures, copied, source_dir)
  source_dir = source_dir or script_dir
  reaper.RecursiveCreateDirectory(destination_dir, 0)
  for _, filename in ipairs(files) do
    local output_dir = (destination_dir .. filename):match("^(.*[/\\])") or destination_dir
    reaper.RecursiveCreateDirectory(output_dir, 0)
    local ok, result = copy_file(source_dir, filename, destination_dir)
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
  remember_original(manifest_path)
  local file, open_error = io.open(manifest_path, "w")
  if not file then return false, open_error end
  local lines = {
    "SGM REAPER Scripts installer v" .. script_version,
    "Installed " .. os.date("%Y-%m-%d %H:%M:%S"),
    "",
  }
  for _, path in ipairs(copied) do table.insert(lines, path) end
  local ok, write_error = file:write(table.concat(lines, "\n") .. "\n")
  file:close()
  if not ok then return false, write_error end
  return true
end

local function main()
  backups, backup_order = {}, {}
  msg("=== SGM REAPER SCRIPT SUITE INSTALLER v" .. script_version .. " ===")
  if script_dir == "" then
    reaper.ShowMessageBox("Could not determine the installer's source directory.", "Installation Failed", 0)
    return false
  end

  local answer = reaper.ShowMessageBox(
    "Install " .. #SCRIPTS .. " ReaScripts, " .. #DOCUMENTS ..
      " documents, and " .. #PLUGIN_FILES .. " JUCE source files to:\n" .. install_path ..
      "\n\nExisting files with the same names will be replaced. Your open project and REAPER settings will not be changed. No plugin binary is compiled or installed.",
    "Install SGM REAPER Scripts", 1)
  if answer ~= 1 then
    msg("Installation cancelled.")
    return false
  end

  local failures, copied = {}, {}
  install_group(SCRIPTS, install_path, failures, copied)
  install_group(DOCUMENTS, documentation_path, failures, copied)
  install_group(PLUGIN_FILES, install_path .. "plugin/", failures, copied, script_dir .. "plugin/")
  if #failures == 0 then
    local ok, manifest_error = write_manifest(copied)
    if not ok then table.insert(failures, "installed-files.txt: " .. tostring(manifest_error)) end
  end

  if #failures > 0 then
    local rollback_problems = rollback_install()
    local note = "\n\nAll changes were rolled back; previous files were restored."
    if #rollback_problems > 0 then
      note = "\n\nRollback could not restore:\n" .. table.concat(rollback_problems, "\n")
    end
    reaper.ShowMessageBox(
      #failures .. " file(s) could not be installed:\n\n" .. table.concat(failures, "\n") ..
      note .. "\n\nSee the REAPER console for details.",
      "Installation Failed", 0)
    return false
  end

  reaper.ShowMessageBox(
    "Installed " .. #copied .. " files successfully.\n\n" ..
    "Open Actions → Show action list → Load ReaScript to register scripts from:\n" ..
    install_path .. "\n\nJUCE source is in the plugin/ subdirectory. Run the blueprint action to copy it into a saved project. No compiled plugin, project templates, or FX chains are installed.",
    "Installation Complete", 0)
  msg("Installation complete: " .. #copied .. " files")
  return true
end

_G.SGMScriptInstaller = {
  copy_file = copy_file,
  main = main,
  scripts = SCRIPTS,
  documents = DOCUMENTS,
  plugin_files = PLUGIN_FILES,
}
main()
