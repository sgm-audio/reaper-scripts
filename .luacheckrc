std = "lua54"

-- Global declarations
globals = {
  "reaper",
  "gfx",
  "ImGui",
}

-- ReaPack and module exports defined at top-level
read_globals = {
  "reaper.*",
  "gfx.*",
  "ImGui.*",
}

files["tests/*.lua"] = {
  globals = {
    "reaper",
    "gfx",
    "ImGui",
  },
}

-- Allow defining top-level namespaces
new_globals = {
  "SGMPluginInventory",
  "SGMPhaseAlignment",
  "SGMPluginWrapper",
  "SGMSessionBuilder",
  "SGMScriptInstaller",
  "SGMPluginDevelopment",
  "SGMRealPluginScanner",
  "AIPluginBridge",
  "ExternalToolLauncher",
  "AIHubController",
  "run_ai_hub",
  "buildProfessionalSession",
  "scanAllPlugins",
  "listAllPluginsOnTrack",
  "automateSelectedPlugin",
  "showMenu",
  "main",
  "msg",
  "show_plugin_development_guide",
  "create_development_project",
  "export_to_reaper",
}

-- Do not warn on unused loop variables or self in methods
ignore = {
  "212", -- Unused argument
  "213", -- Unused loop variable
}
