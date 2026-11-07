-- REAPER AI Control Hub - Plugin Interface Coordinator
-- @description Inspects master-track AI/routing FX, exports routing notes, and prints external-processing instructions
-- @author Scott Mills
-- @version 1.0
-- Acts as bridge between REAPER and external AI processing plugins

function msg(m)
    reaper.ShowConsoleMsg(tostring(m) .. "\n")
end

-- AI Plugin Bridge System
local AIPluginBridge = {}
AIPluginBridge.__index = AIPluginBridge

function AIPluginBridge:new()
    local bridge = {}
    setmetatable(bridge, AIPluginBridge)
    
    bridge.discovered_plugins = {}
    bridge.active_processors = {}
    bridge.plugin_types = {
        VST3 = "VST3",
        CLAP = "CLAP", 
        VST2 = "VST2",
        AU = "AU"  -- macOS only
    }
    
    return bridge
end

function AIPluginBridge:discover_ai_plugins()
    msg("Inspecting master-track FX for AI/routing tools...")
    self.discovered_plugins = {}
    
    -- Scan for known AI plugins
    local ai_plugin_patterns = {
        "ReWIre", "AudioMovers", "Baby Audio", "Cyanleaf",
        "Soundwide", "Neural DSP", "AI", "ML", "Neural",
        "Stem", "Separate", "Mastering", "Analysis"
    }
    
    local plugin_count = reaper.TrackFX_GetCount(reaper.GetMasterTrack(0))
    
    for i = 0, plugin_count - 1 do
        local retval, name = reaper.TrackFX_GetFXName(reaper.GetMasterTrack(0), i, "")
        if retval then
            for j, pattern in ipairs(ai_plugin_patterns) do
                if name:lower():find(pattern:lower(), 1, true) then
                    local plugin_info = {
                        index = i,
                        name = name,
                        type = self:_detect_plugin_type(i),
                        category = self:_categorize_plugin(name),
                        capabilities = self:_assess_capabilities(name)
                    }
                    
                    table.insert(self.discovered_plugins, plugin_info)
                    msg("  Found AI Plugin: " .. name)
                    break
                end
            end
        end
    end
    
    msg("Discovered " .. #self.discovered_plugins .. " AI-capable plugins")
    return self.discovered_plugins
end

function AIPluginBridge:_detect_plugin_type(fx_index)
    -- Detect plugin format
    local retval, fx_name = reaper.TrackFX_GetFXName(reaper.GetMasterTrack(0), fx_index, "")
    local lower_name = fx_name:lower()

    if lower_name:find(".vst3", 1, true) then
        return "VST3"
    elseif lower_name:find(".vst", 1, true) then
        return "VST2"
    elseif lower_name:find(".clap", 1, true) then
        return "CLAP"
    else
        return "Unknown"
    end
end

function AIPluginBridge:_categorize_plugin(plugin_name)
    local name_lower = plugin_name:lower()
    
    if name_lower:find("rewire") or name_lower:find("audiomovers") then
        return "Routing/Host"
    elseif name_lower:find("stem") or name_lower:find("separate") then
        return "Stem Separation"
    elseif name_lower:find("master") or name_lower:find("mastering") then
        return "Mastering"
    elseif name_lower:find("analyze") or name_lower:find("analysis") then
        return "Analysis"
    elseif name_lower:find("neural") or name_lower:find("ai") then
        return "AI Processing"
    else
        return "General"
    end
end

function AIPluginBridge:_assess_capabilities(plugin_name)
    local name_lower = plugin_name:lower()
    local capabilities = {}
    
    -- Stem separation
    if name_lower:find("separate") or name_lower:find("stem") then
        table.insert(capabilities, "stem_separation")
    end
    
    -- Routing/Host
    if name_lower:find("rewire") or name_lower:find("audiomovers") then
        table.insert(capabilities, "host_routing")
    end
    
    -- Mastering
    if name_lower:find("master") or name_lower:find("loudness") then
        table.insert(capabilities, "mastering")
    end
    
    -- Analysis
    if name_lower:find("analyze") or name_lower:find("meter") then
        table.insert(capabilities, "analysis")
    end
    
    -- AI processing
    if name_lower:find("neural") or name_lower:find("ai") then
        table.insert(capabilities, "ai_processing")
    end
    
    return capabilities
end

function AIPluginBridge:setup_rewire_host()
    msg("ReWire setup is host- and OS-specific. REAPER does not expose a portable")
    msg("ReWire device enumerator to Lua. Check Preferences > Audio > Device and")
    msg("your other DAW's ReWire documentation; no settings were changed.")
end

function AIPluginBridge:setup_audiomovers_bridge()
    msg("Setting up AudioMovers OmniBridge integration...")
    
    -- Instructions for OmniBridge setup
    msg("OmniBridge Setup Instructions:")
    msg("1. Install AudioMovers OmniBridge")
    msg("2. Route REAPER tracks to OmniBridge inputs")
    msg("3. Use OmniBridge plugin to process with external tools")
    msg("4. Route processed audio back to REAPER")
end

function AIPluginBridge:create_ai_routing_template()
    msg("Creating AI routing template...")
    
    -- Create template routing for common AI setups
    local routing_presets = {
        {
            name = "ReWire to Logic/Pro Tools",
            description = "Route stems to external DAW for AI processing",
            tracks = {
                {name = "ReWire Out - Drums", send_to = "ReWire", channel = 1},
                {name = "ReWire Out - Bass", send_to = "ReWire", channel = 2},
                {name = "ReWire Out - Vocals", send_to = "ReWire", channel = 3},
                {name = "ReWire Out - Instruments", send_to = "ReWire", channel = 4}
            }
        },
        {
            name = "OmniBridge to External Processing",
            description = "Route through AudioMovers for plugin processing",
            tracks = {
                {name = "OmniBridge Send", send_to = "OmniBridge", channel = 1},
                {name = "OmniBridge Return", receive_from = "OmniBridge", channel = 1}
            }
        },
        {
            name = "VST3 AI Processor Chain",
            description = "Use VST3 AI plugins on dedicated tracks",
            tracks = {
                {name = "AI Stem Separator", plugin = "AI_Separator.vst3"},
                {name = "AI Mastering", plugin = "AI_Mastering.vst3"},
                {name = "AI Analysis", plugin = "AI_Analyzer.vst3"}
            }
        }
    }
    
    -- Save routing template
    local template_path = reaper.GetResourcePath() .. "/ai_routing_template.json"
    local file = io.open(template_path, "w")
    
    if file then
        file:write("{\n")
        file:write('  "presets": [\n')
        
        for i, preset in ipairs(routing_presets) do
            file:write("    {\n")
            file:write('      "name": "' .. preset.name .. '",\n')
            file:write('      "description": "' .. preset.description .. '",\n')
            file:write('      "tracks": [\n')
            
            for j, track in ipairs(preset.tracks) do
                file:write("        {\n")
                for key, value in pairs(track) do
                    file:write('          "' .. key .. '": "' .. tostring(value) .. '"')
                    if next(track, key) then
                        file:write(",\n")
                    else
                        file:write("\n")
                    end
                end
                file:write("        }")
                if next(preset.tracks, j) then
                    file:write(",\n")
                else
                    file:write("\n")
                end
            end
            
            file:write("      ]\n")
            file:write("    }")
            if next(routing_presets, i) then
                file:write(",\n")
            else
                file:write("\n")
            end
        end
        
        file:write("  ]\n")
        file:write("}\n")
        file:close()
        
        msg("Routing template saved to: " .. template_path)
    else
        msg("ERROR: Could not save routing template")
    end
    
    return routing_presets
end

-- External Tool Launcher
local ExternalToolLauncher = {}
ExternalToolLauncher.__index = ExternalToolLauncher

function ExternalToolLauncher:new()
    local launcher = {}
    setmetatable(launcher, ExternalToolLauncher)
    
    launcher.installed_tools = {}
    launcher.tool_paths = self:_get_tool_paths()
    
    return launcher
end

function ExternalToolLauncher:_get_tool_paths()
    local paths = {}
    local os_type = reaper.GetOS()
    if os_type == "Win32" or os_type == "Win64" then
        table.insert(paths, "C:\\Program Files\\AudioMovers\\OmniBridge")
        table.insert(paths, "C:\\Program Files\\Common Files\\VST3\\AI")
        table.insert(paths, "C:\\Program Files\\ReWire")
    elseif os_type:match("^OSX") then
        local home = os.getenv("HOME") or ""
        table.insert(paths, "/Applications/AudioMovers/OmniBridge.app")
        if home ~= "" then
            table.insert(paths, home .. "/Library/Audio/Plug-Ins/VST3/AI")
        end
    else
        -- Linux
        local home = os.getenv("HOME") or ""
        if home ~= "" then
            table.insert(paths, home .. "/.vst3/AI")
            table.insert(paths, home .. "/.local/share/AudioMovers/OmniBridge")
        end
    end
    -- REAPER resource path works on every OS (forward slashes are portable)
    table.insert(paths, reaper.GetResourcePath() .. "/UserPlugins/AI")
    return paths
end

function ExternalToolLauncher:launch_external_processing(track_indices, tool_type)
    tool_type = tool_type or "stem_separation"
    
    msg("Launching external processing for tracks...")
    
    -- Get selected tracks or all tracks
    local tracks_to_process = {}
    
    if track_indices and #track_indices > 0 then
        for i, index in ipairs(track_indices) do
            local track = reaper.GetTrack(0, index)
            if track then
                table.insert(tracks_to_process, track)
            end
        end
    else
        -- Use selected tracks
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
            table.insert(tracks_to_process, reaper.GetSelectedTrack(0, i))
        end
    end
    
    -- REAPER's Lua API has no portable one-call stem renderer. Print exact
    -- manual render targets instead of claiming that files were exported.
    local project_path = reaper.GetProjectPath(0)
    if project_path == "" then
        msg("Save the project before choosing an external export directory.")
        return {}
    end
    local export_dir = project_path .. "/external_ai_export"
    reaper.RecursiveCreateDirectory(export_dir, 0)
    local exported_files = {}

    for i, track in ipairs(tracks_to_process) do
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        self:_export_track_stems(track, track_name, export_dir)
    end

    local tool_config = self:_get_tool_config(tool_type)
    self:_execute_external_tool(tool_config, exported_files)
    return exported_files
end

function ExternalToolLauncher:_export_track_stems(track, track_name, export_dir)
    -- This helper reports a manual render target; it does not create audio.
    
    local safe_name = (track_name ~= "" and track_name or "Unnamed Track"):gsub('[/\\:*?"<>|]', "_")
    local export_file = export_dir .. "/" .. safe_name .. "_export.wav"
    msg("  Manual render target: " .. safe_name .. " -> " .. export_file)
    msg("    Render this track as a stem before running the external command.")
    return nil
end

function ExternalToolLauncher:_get_tool_config(tool_type)
    local configs = {
        stem_separation = {
            executable = "python",
            args = "-m demucs",
            working_dir = reaper.GetProjectPath(0),
            name = "Demucs Stem Separator"
        },
        mastering = {
            executable = "omnibridge.exe", 
            args = "--mastering-mode",
            working_dir = "",
            name = "OmniBridge Mastering"
        },
        analysis = {
            executable = "ai_analyzer.exe",
            args = "--batch-analysis",
            working_dir = "",
            name = "AI Audio Analyzer"
        }
    }
    
    return configs[tool_type] or configs.stem_separation
end

function ExternalToolLauncher:_execute_external_tool(tool_config, files)
    msg("Launching external tool: " .. tool_config.name)
    msg("  Executable: " .. tool_config.executable)
    msg("  Arguments: " .. tool_config.args)
    msg("  Files currently rendered: " .. #files)
    if #files == 0 then msg("  No audio was rendered automatically; render the targets above first.") end

    -- External execution is intentionally manual so arguments and media can be reviewed.
    -- For now, just provide instructions
    msg("\nTo complete processing:")
    msg("1. Run: " .. tool_config.executable .. " " .. tool_config.args)
    msg("2. Process exported files in: " .. reaper.GetProjectPath(0) .. "/external_ai_export")
    msg("3. Import processed results back into REAPER")
end

-- Main AI Hub Controller
local AIHubController = {}
AIHubController.__index = AIHubController

function AIHubController:new()
    local controller = {}
    setmetatable(controller, AIHubController)
    
    controller.plugin_bridge = AIPluginBridge:new()
    controller.tool_launcher = ExternalToolLauncher:new()
    controller.active_mode = "bridge"
    
    return controller
end 

function AIHubController:show_interface()
    local menu = "REAPER AI Control Hub|" ..
        "Inspect Master FX / Export Routing Notes|" ..
        "ReWire Setup Notes|" ..
        "OmniBridge Setup Notes|" ..
        "External Processing Instructions"
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local choice = gfx.showmenu(menu)
    if choice == 1 then self:run_discovery_mode()
    elseif choice == 2 then self:run_rewire_mode()
    elseif choice == 3 then self:run_omnibridge_mode()
    elseif choice == 4 then self:run_external_tool_mode() end
end

function AIHubController:run_discovery_mode()
    msg("\n=== AI PLUGIN DISCOVERY MODE ===")
    
    local plugins = self.plugin_bridge:discover_ai_plugins()
    
    if #plugins > 0 then
        msg("\nAI Plugin Recommendations:")
        for i, plugin in ipairs(plugins) do
            msg("  " .. plugin.name .. " (" .. plugin.category .. ")")
            for j, capability in ipairs(plugin.capabilities) do
                msg("    - " .. capability)
            end
        end
    else
        msg("\nNo AI plugins found. Consider installing:")
        msg("  - ReWire-enabled DAWs for external processing")
        msg("  - AudioMovers OmniBridge for VST3 plugin hosting")
        msg("  - AI processing plugins (Neural DSP, Baby Audio, etc.)")
    end
    
    -- Create routing template
    self.plugin_bridge:create_ai_routing_template()
end

function AIHubController:run_rewire_mode()
    msg("\n=== REWIRE INTEGRATION MODE ===")
    self.plugin_bridge:setup_rewire_host()
end

function AIHubController:run_omnibridge_mode()
    msg("\n=== OMNIBRIDGE INTEGRATION MODE ===")
    self.plugin_bridge:setup_audiomovers_bridge()
end

function AIHubController:run_external_tool_mode()
    msg("\n=== EXTERNAL TOOL LAUNCHER MODE ===")
    self.tool_launcher:launch_external_processing(nil, "stem_separation")
end

-- Main function
function run_ai_hub()
    local controller = AIHubController:new()
    
    controller:show_interface()
end

-- Export for use in other scripts
_G.AIPluginBridge = AIPluginBridge
_G.ExternalToolLauncher = ExternalToolLauncher
_G.AIHubController = AIHubController
_G.run_ai_hub = run_ai_hub

-- Running the ReaScript opens the console-based hub. The globals above remain
-- available to other scripts that want to reuse its helpers.
run_ai_hub()
