-- Buildable JUCE Plugin Development Project
-- @description Copies the bundled, buildable SGM Utility JUCE/CMake project into the current REAPER project
-- @author Scott Mills
-- @version 2.0

--[[
The generated baseline builds VST3 and Standalone targets with smoothed gain,
bypass, parameter automation/state, mono/stereo bus validation, an editor, and
native tests. It does NOT contain AI inference, stem-separation models, or CLAP.
Those are later extensions and must not be represented as working features until
implemented and tested. See plugin/README.md for prerequisites and build steps.
]]

local script_dir = debug.getinfo(1, "S").source:match("@(.+[/\\])") or ""
local template_dir = script_dir .. "plugin/"
local project_name = "SGM_AI_Plugin_Suite"

local PROJECT_FILES = {
  "CMakeLists.txt",
  "README.md",
  ".gitignore",
  "Source/PluginProcessor.h",
  "Source/PluginProcessor.cpp",
  "Source/PluginEditor.h",
  "Source/PluginEditor.cpp",
  "Tests/PluginTests.cpp",
}

local function message(text)
  reaper.ShowConsoleMsg(tostring(text) .. "\n")
end

local function read_file(path)
  local file, open_error = io.open(path, "rb")
  if not file then return nil, open_error end
  local content = file:read("*a")
  file:close()
  if content == nil then return nil, "could not read file" end
  return content
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close() return true end
  return false
end

function show_plugin_development_guide()
  message("=== SGM BUILDABLE JUCE PLUGIN BASELINE ===")
  message("Builds: VST3, Standalone, and native processing tests")
  message("Requires: CMake 3.22+, a C++17 compiler, and JUCE 8.0.4")
  message("CMake fetches the pinned JUCE commit unless SGM_JUCE_SOURCE_DIR is set.")
  message("AI inference and CLAP are not implemented in this baseline.")
  message("After generation, follow README.md in the destination directory.")
end

function create_development_project()
  local parent_path = reaper.GetProjectPath(0)
  if parent_path == nil or parent_path == "" then
    reaper.ShowMessageBox(
      "Save the REAPER project before generating the JUCE project.",
      "JUCE Project Generator", 0)
    return false
  end
  if not file_exists(template_dir .. "CMakeLists.txt") then
    reaper.ShowMessageBox(
      "The bundled plugin sources were not found at:\n" .. template_dir ..
      "\n\nRe-run reaper-template-installer.lua from the complete repository.",
      "JUCE Project Generator", 0)
    return false
  end

  local destination = parent_path .. "/" .. project_name .. "/"
  local contents = {}
  for _, relative_path in ipairs(PROJECT_FILES) do
    if file_exists(destination .. relative_path) then
      reaper.ShowMessageBox(
        "Generation stopped to avoid overwriting:\n" .. destination .. relative_path,
        "JUCE Project Already Exists", 0)
      return false
    end
    local content, read_error = read_file(template_dir .. relative_path)
    if content == nil then
      reaper.ShowMessageBox(
        "Missing or unreadable template file:\n" .. template_dir .. relative_path ..
        "\n" .. tostring(read_error), "JUCE Project Generator", 0)
      return false
    end
    contents[relative_path] = content
  end

  local written = {}
  for _, relative_path in ipairs(PROJECT_FILES) do
    local output_path = destination .. relative_path
    local output_dir = output_path:match("^(.*[/\\])") or destination
    reaper.RecursiveCreateDirectory(output_dir, 0)
    local output, open_error = io.open(output_path, "wb")
    if not output then
      for _, path in ipairs(written) do os.remove(path) end
      reaper.ShowMessageBox(
        "Could not create:\n" .. output_path .. "\n" .. tostring(open_error) ..
        "\n\nGenerated files were rolled back.", "JUCE Project Generator", 0)
      return false
    end
    local ok, write_error = output:write(contents[relative_path])
    output:close()
    if not ok then
      os.remove(output_path)
      for _, path in ipairs(written) do os.remove(path) end
      reaper.ShowMessageBox(
        "Could not write:\n" .. output_path .. "\n" .. tostring(write_error) ..
        "\n\nGenerated files were rolled back.", "JUCE Project Generator", 0)
      return false
    end
    table.insert(written, output_path)
  end

  message("Buildable JUCE project created: " .. destination)
  message("Next: cd \"" .. destination .. "\" && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release")
  message("Then: cmake --build build --config Release && ctest --test-dir build --output-on-failure")
  reaper.ShowMessageBox(
    "Created the buildable JUCE project at:\n" .. destination ..
    "\n\nNo binary has been compiled yet. Install the prerequisites and follow README.md to build VST3, Standalone, and native tests.\n\nAI inference and CLAP are not included.",
    "JUCE Project Created", 0)
  return true
end

function main()
  show_plugin_development_guide()
  local answer = reaper.ShowMessageBox(
    "Create the buildable SGM Utility JUCE project in the current project folder?\n\n" ..
    "This copies source files; it does not compile or install a plugin. Existing files will not be overwritten.",
    "SGM JUCE Project Generator", 1)
  if answer == 1 then return create_development_project() end
  return false
end

_G.SGMPluginDevelopment = {
  create_development_project = create_development_project,
  project_files = PROJECT_FILES,
  template_dir = template_dir,
}

return main()
