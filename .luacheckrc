std = "lua54"

-- Global declarations (REAPER injects reaper.*, gfx.*, ImGui.*)
globals = {
  reaper = { other_fields = true, read_only = false },
  gfx = { other_fields = true, read_only = false },
  ImGui = { other_fields = true, read_only = false },
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

-- Do not warn on unused loop variables, self, or legacy formatting
ignore = {
  "212", -- Unused argument
  "213", -- Unused loop variable
  "611", -- Line contains only whitespace
  "612", -- Line contains trailing whitespace
  "613", -- Trailing whitespace in a string
  "614", -- Trailing whitespace in a comment
  "631", -- Line is too long
}
