-- REAPER AI Control Hub - Plugin Interface Coordinator
-- @description Inspects master-track AI/routing FX, exports routing notes, and prints external-processing instructions
-- @author Scott Mills
-- @version 1.0
-- Acts as bridge between REAPER and external AI processing plugins

local function msg(m)
    reaper.ShowConsoleMsg(tostring(m) .. "\n")
end

-- Whole-word, case-insensitive match. Plain substring matching misclassified names such as
-- "Gain Reduction Scope" or "Chain" as AI tools because "gain"/"chain" contain "ai".
local function name_has(name, term)
    local escaped = term:lower():gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return tostring(name):lower():find("%f[%w]" .. escaped .. "%f[%W]") ~= nil
end

local function name_has_any(name, terms)
    for _, term in ipairs(terms) do
        if name_has(name, term) then return true end
    end
    return false
end

local function get_saved_project_dir()
    if reaper.EnumProjects then
        local _, proj_fn = reaper.EnumProjects(-1)
        if type(proj_fn) == "string" and proj_fn ~= "" then
            local dir = proj_fn:match("^(.*)[/\\][^/\\]+$")
            if dir and dir ~= "" then
                return dir
            end
        else
            return ""
        end
    end
    return reaper.GetProjectPath("") or ""
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
        AU = "AU",  -- macOS only
        LV2 = "LV2",
        JSFX = "JSFX"
    }
    
    return bridge
end

function AIPluginBridge:discover_ai_plugins()
    msg("Inspecting master-track FX for AI/routing tools...")
    self.discovered_plugins = {}
    
    -- Scan for known AI plugins
    local ai_plugin_patterns = {
        "ReWire", "AudioMovers", "Baby Audio", "Cyanleaf",
        "Soundwide", "Neural DSP", "AI", "ML", "Neural",
        "Stem", "Separate", "Mastering", "Analysis"
    }
    
    local master_track = reaper.GetMasterTrack(0)
    if not master_track then
        msg("Master track unavailable")
        return self.discovered_plugins
    end
    local plugin_count = reaper.TrackFX_GetCount(master_track)
    
    for i = 0, plugin_count - 1 do
        local retval, name = reaper.TrackFX_GetFXName(master_track, i, "")
        if retval and name then
            for _, pattern in ipairs(ai_plugin_patterns) do
                if name_has(name, pattern) then
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
    -- REAPER reports FX names with a format prefix ("VST3: ", "VST: ", "CLAP: ", "JS: ", ...),
    -- not a file extension, so classify on that prefix first, then fall back to extension.
    local master_track = reaper.GetMasterTrack(0)
    if not master_track then
        return "Unknown"
    end
    local retval, fx_name = reaper.TrackFX_GetFXName(master_track, fx_index, "")
    if not retval or not fx_name then
        return "Unknown"
    end
    local lower_name = fx_name:lower()

    if lower_name:match("^vst3i?:") then
        return "VST3"
    elseif lower_name:match("^vsti?:") then
        return "VST2"
    elseif lower_name:match("^clapi?:") then
        return "CLAP"
    elseif lower_name:match("^aui?:") then
        return "AU"
    elseif lower_name:match("^lv2i?:") then
        return "LV2"
    elseif lower_name:match("^js:") then
        return "JSFX"
    elseif lower_name:match("%.vst3$") then
        return "VST3"
    elseif lower_name:match("%.vst$") or lower_name:match("%.dll$") or lower_name:match("%.so$") then
        return "VST2"
    elseif lower_name:match("%.clap$") then
        return "CLAP"
    elseif lower_name:match("%.component$") then
        return "AU"
    elseif lower_name:match("%.lv2$") then
        return "LV2"
    else
        return "Unknown"
    end
end

function AIPluginBridge:_categorize_plugin(plugin_name)
    local name_lower = plugin_name:lower()
    
    if name_has_any(name_lower, {"rewire", "audiomovers", "omnibridge"}) then
        return "Routing/Host"
    elseif name_has_any(name_lower, {"stem", "stems", "separate", "separator", "separation"}) then
        return "Stem Separation"
    elseif name_has_any(name_lower, {"master", "mastering"}) then
        return "Mastering"
    elseif name_has_any(name_lower, {"analyze", "analyzer", "analysis"}) then
        return "Analysis"
    elseif name_has_any(name_lower, {"neural", "ai", "ml"}) then
        return "AI Processing"
    else
        return "General"
    end
end

function AIPluginBridge:_assess_capabilities(plugin_name)
    local name_lower = plugin_name:lower()
    local capabilities = {}
    
    -- Stem separation
    if name_has_any(name_lower, {"separate", "separator", "separation", "stem", "stems"}) then
        table.insert(capabilities, "stem_separation")
    end
    
    -- Routing/Host
    if name_has_any(name_lower, {"rewire", "audiomovers", "omnibridge"}) then
        table.insert(capabilities, "host_routing")
    end
    
    -- Mastering
    if name_has_any(name_lower, {"master", "mastering", "loudness"}) then
        table.insert(capabilities, "mastering")
    end
    
    -- Analysis
    if name_has_any(name_lower, {"analyze", "analyzer", "analysis", "meter"}) then
        table.insert(capabilities, "analysis")
    end
    
    -- AI processing
    if name_has_any(name_lower, {"neural", "ai", "ml"}) then
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

local function json_string(value)
    local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
    escaped = escaped:gsub("%c", function(char)
        local replacements = {["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
        return replacements[char] or string.format("\\u%04X", string.byte(char))
    end)
    return '"' .. escaped .. '"'
end

local function json_value(value)
    if type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    end
    return json_string(value)
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
            file:write('      "name": ' .. json_string(preset.name) .. ',\n')
            file:write('      "description": ' .. json_string(preset.description) .. ',\n')
            file:write('      "tracks": [\n')
            
            for j, track in ipairs(preset.tracks) do
                file:write("        {\n")
                local keys = {}
                for key in pairs(track) do table.insert(keys, key) end
                table.sort(keys)
                for k_idx, key in ipairs(keys) do
                    file:write('          ' .. json_string(key) .. ': ' .. json_value(track[key]))
                    if k_idx < #keys then
                        file:write(",\n")
                    else
                        file:write("\n")
                    end
                end
                file:write("        }")
                if j < #preset.tracks then
                    file:write(",\n")
                else
                    file:write("\n")
                end
            end
            
            file:write("      ]\n")
            file:write("    }")
            if i < #routing_presets then
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
    local os_type = reaper.GetOS() or ""
    local is_win = os_type == "Win32" or os_type == "Win64"
    local paths, seen = {}, {}
    local function join_path(left, right)
        return tostring(left or ""):gsub("\\", "/"):gsub("/+$", "") .. "/" .. right
    end
    local function add(path)
        if type(path) ~= "string" or path == "" then return end
        local normalized = path:gsub("\\", "/"):gsub("/+$", "")
        if normalized == "" then return end
        local key = is_win and normalized:lower() or normalized
        if not seen[key] then
            seen[key] = true
            table.insert(paths, normalized)
        end
    end

    if is_win then
        local prog_files = (os.getenv("ProgramFiles") or "C:/Program Files"):gsub("\\", "/")
        local common_files = (os.getenv("CommonProgramFiles") or join_path(prog_files, "Common Files")):gsub("\\", "/")
        add(join_path(prog_files, "AudioMovers/OmniBridge"))
        add(join_path(common_files, "VST3/AI"))
        add(join_path(prog_files, "ReWire"))
    elseif os_type:match("^OSX") or os_type:match("^macOS") then
        local home = os.getenv("HOME") or ""
        add("/Applications/AudioMovers/OmniBridge.app")
        if home ~= "" then
            add(join_path(home, "Library/Audio/Plug-Ins/VST3/AI"))
        end
    else
        -- Linux
        local home = os.getenv("HOME") or ""
        if home ~= "" then
            add(join_path(home, ".vst3/AI"))
            add(join_path(home, ".local/share/AudioMovers/OmniBridge"))
        end
        add("/usr/lib/vst3/AI")
        add("/usr/local/lib/vst3/AI")
    end
    -- REAPER resource path works on every OS (forward slashes are portable)
    local res_path = reaper.GetResourcePath and reaper.GetResourcePath() or ""
    if res_path ~= "" then
        add(join_path(res_path, "UserPlugins/AI"))
    end
    return paths
end

function ExternalToolLauncher:launch_external_processing(track_indices, tool_type)
    tool_type = tool_type or "stem_separation"
    
    msg("Launching external processing for tracks...")
    
    -- Get selected tracks or all tracks
    local tracks_to_process = {}
    
    if track_indices and #track_indices > 0 then
        for _, index in ipairs(track_indices) do
            local track = reaper.GetTrack(0, index)
            if track then
                table.insert(tracks_to_process, {track = track, index = index + 1})
            end
        end
    else
        -- Use selected tracks
        for i = 0, reaper.CountSelectedTracks(0) - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            if track then
                table.insert(tracks_to_process, {track = track, index = i + 1})
            end
        end
    end
    
    if #tracks_to_process == 0 then
        msg("Select at least one track before generating external render targets.")
        return {}
    end

    -- REAPER's Lua API has no portable one-call stem renderer. Print exact
    -- manual render targets instead of claiming that files were exported.
    local project_path = get_saved_project_dir()
    if project_path == "" then
        msg("Save the project before choosing an external export directory.")
        return {}
    end
    local export_dir = project_path .. "/external_ai_export"
    local exported_files = {}

    for _, entry in ipairs(tracks_to_process) do
        local _, track_name = reaper.GetSetMediaTrackInfo_String(entry.track, "P_NAME", "", false)
        self:_export_track_stems(entry.track, track_name, export_dir, entry.index)
    end

    local tool_config = self:_get_tool_config(tool_type, project_path)
    self:_execute_external_tool(tool_config, exported_files, export_dir)
    return exported_files
end

function ExternalToolLauncher:_export_track_stems(track, track_name, export_dir, track_index)
    -- This helper reports a manual render target; it does not create audio.
    
    local safe_name = (track_name ~= "" and track_name or "Unnamed Track"):gsub('[/\\:*?"<>|]', "_")
    local prefix = track_index and string.format("%02d_", track_index) or ""
    local export_file = export_dir .. "/" .. prefix .. safe_name .. "_export.wav"
    msg("  Manual render target: " .. safe_name .. " -> " .. export_file)
    msg("    Render this track as a stem before running the external command.")
    return nil
end

function ExternalToolLauncher:_get_tool_config(tool_type, project_path)
    local os_type = reaper.GetOS() or ""
    local is_win = os_type == "Win32" or os_type == "Win64"
    local ext = is_win and ".exe" or ""
    local configs = {
        stem_separation = {
            executable = is_win and "python" or "python3",
            args = "-m demucs",
            working_dir = project_path or get_saved_project_dir(),
            name = "Demucs Stem Separator"
        },
        mastering = {
            executable = "omnibridge" .. ext,
            args = "--mastering-mode",
            working_dir = "",
            name = "OmniBridge Mastering"
        },
        analysis = {
            executable = "ai_analyzer" .. ext,
            args = "--batch-analysis",
            working_dir = "",
            name = "AI Audio Analyzer"
        }
    }
    
    return configs[tool_type] or configs.stem_separation
end

function ExternalToolLauncher:_execute_external_tool(tool_config, files, export_dir)
    msg("Launching external tool: " .. tool_config.name)
    msg("  Executable: " .. tool_config.executable)
    msg("  Arguments: " .. tool_config.args)
    msg("  Files currently rendered: " .. #files)
    if #files == 0 then msg("  No audio was rendered automatically; render the targets above first.") end

    -- External execution is intentionally manual so arguments and media can be reviewed.
    -- For now, just provide instructions
    local target_dir = export_dir or (get_saved_project_dir() .. "/external_ai_export")
    msg("\nTo complete processing:")
    msg("1. Run: " .. tool_config.executable .. " " .. tool_config.args)
    msg("2. Process exported files in: " .. target_dir)
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
    local menu = "" ..
        "Inspect Master FX / Export Routing Notes|" ..
        "ReWire Setup Notes|" ..
        "OmniBridge Setup Notes|" ..
        "External Processing Instructions"
    if gfx.init then gfx.init("", 0, 0, 0, 0, 0) end
    gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
    local choice = gfx.showmenu(menu)
    if gfx.quit then gfx.quit() end
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
