std = "lua54"

-- Global declarations (REAPER injects reaper.*, gfx.*, ImGui.*)
globals = {
  "reaper",
  "gfx",
  "ImGui",
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

-- Do not warn on host API fields, unused loop/arg vars, or legacy formatting
ignore = {
  "142", -- Setting undefined field of global (gfx.x, gfx.y)
  "143", -- Accessing undefined field of global (reaper.*, gfx.*, ImGui.*)
  "212", -- Unused argument
  "213", -- Unused loop variable
  "611", -- Line contains only whitespace
  "612", -- Line contains trailing whitespace
  "613", -- Trailing whitespace in a string
  "614", -- Trailing whitespace in a comment
  "631", -- Line is too long
}
