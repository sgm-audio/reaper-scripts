-- REAPER Ultimate Template System v3.0
-- Complete Installation and Configuration Script
-- Author: Scott Mills Audio Systems

-- This script installs the complete template system including:
-- 1. Master templates with routing matrices
-- 2. Signal chain presets
-- 3. Pro Tools workflow enhancements  
-- 4. AI integration hooks
-- 5. Custom toolbars and menus

local script_version = "3.0"
local install_path = reaper.GetResourcePath() .. "/Scripts/ScottMills/"

-- Utility Functions
function msg(m)
  reaper.ShowConsoleMsg(tostring(m) .. "\n")
end

function create_directory(path)
  reaper.RecursiveCreateDirectory(path, 0)
end

-- Template Installation Functions
function install_master_templates()
  msg("Installing Master Templates...")
  
  local templates = {
    -- Mixing Templates
    {
      name = "AI-Enhanced Mix Template 96ch",
      tracks = 96,
      setup = function()
        -- Create track structure
        create_mix_template_tracks()
        
        -- Setup routing
        setup_advanced_routing()
        
        -- Load FX chains
        load_mix_fx_chains()
        
        -- Configure automation
        setup_automation_lanes()
        
        -- Setup metering
        configure_mix_metering()
      end
    },
    
    -- Production Templates
    {
      name = "Modern Production Suite 128ch",
      tracks = 128,
      setup = function()
        create_production_template()
        setup_midi_routing()
        configure_virtual_instruments()
        setup_tempo_mapping()
      end
    },
    
    -- Mastering Template
    {
      name = "AI Mastering Suite",
      tracks = 16,
      setup = function()
        create_mastering_template()
        setup_reference_tracks()
        configure_mastering_chain()
        setup_delivery_tracks()
      end
    }
  }
  
  -- Install each template
  for _, template in ipairs(templates) do
    install_template(template)
  end
  
  msg("Master Templates Installed Successfully!")
end

function create_mix_template_tracks()
  -- Drum tracks
  local drum_folder = create_folder_track("DRUMS", 1)
  create_track("Kick In", drum_folder, "audio", {color = rgb(255, 0, 0)})
  create_track("Kick Out", drum_folder, "audio", {color = rgb(200, 0, 0)})
  create_track("Snare Top", drum_folder, "audio", {color = rgb(255, 128, 0)})
  create_track("Snare Btm", drum_folder, "audio", {color = rgb(200, 100, 0)})
  create_track("HiHat", drum_folder, "audio", {color = rgb(255, 255, 0)})
  create_track("Toms", drum_folder, "audio", {color = rgb(255, 200, 0)})
  create_track("OH L", drum_folder, "audio", {color = rgb(128, 255, 128)})
  create_track("OH R", drum_folder, "audio", {color = rgb(128, 255, 128)})
  create_track("Room", drum_folder, "audio", {color = rgb(100, 200, 100)})
  
  -- Bass
  create_track("Bass DI", nil, "audio", {color = rgb(0, 128, 255)})
  create_track("Bass Amp", nil, "audio", {color = rgb(0, 100, 200)})
  
  -- Instrument tracks
  local inst_folder = create_folder_track("INSTRUMENTS", 20)
  for i = 1, 16 do
    create_track("Inst " .. i, inst_folder, "audio", {color = rgb(128, 0, 255)})
  end
  
  -- Vocal tracks
  local vox_folder = create_folder_track("VOCALS", 40)
  create_track("Lead Vox", vox_folder, "audio", {color = rgb(255, 128, 255)})
  create_track("Vox Dbl", vox_folder, "audio", {color = rgb(255, 100, 255)})
  create_track("Harmony 1", vox_folder, "audio", {color = rgb(255, 0, 255)})
  create_track("Harmony 2", vox_folder, "audio", {color = rgb(255, 0, 255)})
  create_track("Harmony 3", vox_folder, "audio", {color = rgb(255, 0, 255)})
  create_track("Ad Libs", vox_folder, "audio", {color = rgb(200, 0, 200)})
  
  -- Aux/Bus tracks
  create_track("Drum Bus", nil, "bus", {color = rgb(150, 0, 0)})
  create_track("Inst Bus", nil, "bus", {color = rgb(100, 0, 150)})
  create_track("Vox Bus", nil, "bus", {color = rgb(150, 0, 150)})
  create_track("Mix Bus", nil, "bus", {color = rgb(200, 200, 200)})
  
  -- FX Returns
  create_track("Rev Hall", nil, "aux", {color = rgb(0, 200, 200)})
  create_track("Rev Plate", nil, "aux", {color = rgb(0, 200, 200)})
  create_track("Rev Room", nil, "aux", {color = rgb(0, 200, 200)})
  create_track("Delay 1/4", nil, "aux", {color = rgb(200, 200, 0)})
  create_track("Delay 1/8D", nil, "aux", {color = rgb(200, 200, 0)})
  create_track("Delay Throw", nil, "aux", {color = rgb(200, 200, 0)})
end

function setup_advanced_routing()
  msg("Setting up advanced routing matrix...")
  
  -- Create sends from drums to drum bus
  route_folder_to_bus("DRUMS", "Drum Bus", -12)
  
  -- Create sends from instruments to bus
  route_folder_to_bus("INSTRUMENTS", "Inst Bus", -6)
  
  -- Create sends from vocals to bus
  route_folder_to_bus("VOCALS", "Vox Bus", -6)
  
  -- Route all buses to mix bus
  route_track_to_track("Drum Bus", "Mix Bus", 0)
  route_track_to_track("Inst Bus", "Mix Bus", 0)
  route_track_to_track("Vox Bus", "Mix Bus", 0)
  
  -- Setup reverb sends
  create_send("Lead Vox", "Rev Plate", -20, "pre")
  create_send("Snare Top", "Rev Room", -15, "post")
  create_send("OH L", "Rev Hall", -18, "post")
  create_send("OH R", "Rev Hall", -18, "post")
  
  -- Setup delay sends  
  create_send("Lead Vox", "Delay 1/8D", -25, "pre")
  create_send("Lead Vox", "Delay Throw", -inf, "pre") -- For automation
  
  -- Configure parallel compression
  create_parallel_route("Drum Bus", "Drum Para", -6)
  create_parallel_route("Vox Bus", "Vox Para", -10)
end

function load_mix_fx_chains()
  msg("Loading FX chains...")
  
  local fx_chains = {
    -- Drum chains
    ["Kick In"] = "Modern Kick.RfxChain",
    ["Snare Top"] = "Crispy Snare Top.RfxChain",
    ["Snare Btm"] = "Snare Bottom Phase.RfxChain",
    ["OH L"] = "Smooth Overheads L.RfxChain",
    ["OH R"] = "Smooth Overheads R.RfxChain",
    
    -- Bus chains
    ["Drum Bus"] = "Analog Drum Bus.RfxChain",
    ["Vox Bus"] = "Vocal Bus Polish.RfxChain",
    ["Mix Bus"] = "AI Mix Bus Master.RfxChain",
    
    -- FX returns
    ["Rev Hall"] = "Concert Hall Reverb.RfxChain",
    ["Rev Plate"] = "Vintage Plate.RfxChain",
    ["Delay 1/4"] = "Quarter Note Delay.RfxChain"
  }
  
  for track_name, chain_file in pairs(fx_chains) do
    local track = get_track_by_name(track_name)
    if track then
      load_fx_chain(track, chain_file)
    end
  end
end

-- Signal Chain Management
function install_signal_chains()
  msg("Installing Signal Chain Presets...")
  
  local chain_path = install_path .. "SignalChains/"
  create_directory(chain_path)
  
  -- Write signal chain presets
  local chains = require("signal-chain-presets")
  
  for category, chain_list in pairs(chains) do
    local category_path = chain_path .. category .. "/"
    create_directory(category_path)
    
    for chain_name, chain_data in pairs(chain_list) do
      save_chain_preset(category_path, chain_name, chain_data)
    end
  end
  
  msg("Signal Chains Installed!")
end

-- Pro Tools Workflow Installation
function install_protools_workflow()
  msg("Installing Pro Tools Workflow Enhancements...")
  
  -- Install keyboard shortcuts
  install_keyboard_shortcuts()
  
  -- Configure edit modes
  setup_edit_modes()
  
  -- Setup smart tool
  configure_smart_tool()
  
  -- Configure automation modes
  setup_automation_modes()
  
  -- Install custom actions
  install_custom_actions()
  
  msg("Pro Tools Workflow Installed!")
end

function install_keyboard_shortcuts()
  local shortcuts = {
    -- Transport
    {key = "space", action = "_TRANSPORT_PLAY_STOP"},
    {key = "F12", action = "_TRANSPORT_RECORD"},
    {key = "shift+L", action = "_TRANSPORT_TOGGLE_REPEAT"},
    {key = "return", action = "_TRANSPORT_STOP_GOTO_START"},
    
    -- Tools
    {key = "F5", action = "_RS_SELECT_TOOL"},
    {key = "F6", action = "_RS_TRIM_TOOL"},
    {key = "F7", action = "_RS_SMART_TOOL"},
    {key = "F8", action = "_RS_GRAB_TOOL"},
    
    -- Zoom
    {key = "T", action = "_XENAKIOS_VZOOMSELITEMS"},
    {key = "R", action = "_VIEW_ZOOM_OUT_VERT"},
    {key = "Z", action = "_SWS_TOGZOOMHORIZ_ITEMS"},
    
    -- Editing
    {key = "ctrl+E", action = "_XENAKIOS_SPLIT_ITEMS_AT_EDIT_CURSOR"},
    {key = "ctrl+H", action = "_XENAKIOS_HEAL_SPLITS_IN_ITEMS"},
    {key = "ctrl+D", action = "_XENAKIOS_DUPLICATE_ITEMS"},
    {key = "ctrl+T", action = "_SWS_AWTRIMMEDIA"},
    
    -- Automation
    {key = "ctrl+/", action = "_RS_CYCLE_AUTO_MODE"},
    {key = "ctrl+shift+A", action = "_RS_SHOW_ALL_AUTO"},
    {key = "ctrl+shift+H", action = "_RS_HIDE_ALL_AUTO"}
  }
  
  for _, shortcut in ipairs(shortcuts) do
    set_keyboard_shortcut(shortcut.key, shortcut.action)
  end
end

function setup_automation_modes()
  -- Create automation mode toolbar
  local toolbar_id = create_toolbar("Automation Modes")
  
  add_toolbar_button(toolbar_id, "Read", "_RS_AUTO_READ", "auto_read.png")
  add_toolbar_button(toolbar_id, "Write", "_RS_AUTO_WRITE", "auto_write.png")
  add_toolbar_button(toolbar_id, "Touch", "_RS_AUTO_TOUCH", "auto_touch.png")
  add_toolbar_button(toolbar_id, "Latch", "_RS_AUTO_LATCH", "auto_latch.png")
  add_toolbar_button(toolbar_id, "Trim", "_RS_AUTO_TRIM", "auto_trim.png")
end

-- AI Integration Setup
function setup_ai_integration()
  msg("Setting up AI Integration...")
  
  -- Create AI analysis folder
  local ai_path = install_path .. "AI/"
  create_directory(ai_path)
  
  -- Install Python scripts
  copy_file("ai-integration-module.py", ai_path)
  
  -- Create ReaScript bridge
  local bridge_script = [[
-- AI Bridge Script
-- Communicates between REAPER and Python AI module

local socket = require("socket")
local json = require("json")

function analyze_project()
  -- Gather project data
  local project_data = {
    tracks = get_all_track_data(),
    tempo = reaper.Master_GetTempo(),
    sample_rate = get_project_sample_rate()
  }
  
  -- Send to Python AI module
  local client = socket.tcp()
  client:connect("localhost", 8888)
  client:send(json.encode(project_data))
  
  -- Receive analysis
  local response = client:receive("*a")
  client:close()
  
  return json.decode(response)
end

function apply_ai_suggestions(analysis)
  -- Apply EQ suggestions
  for _, eq in ipairs(analysis.eq_suggestions) do
    apply_eq_to_track(eq.track, eq.settings)
  end
  
  -- Apply automation
  for _, auto in ipairs(analysis.automation) do
    create_automation_item(auto.track, auto.param, auto.points)
  end
end
]]
  
  save_script(ai_path .. "ai_bridge.lua", bridge_script)
  
  -- Create AI toolbar
  local ai_toolbar = create_toolbar("AI Assistant")
  add_toolbar_button(ai_toolbar, "Analyze", "_RS_AI_ANALYZE", "ai_analyze.png")
  add_toolbar_button(ai_toolbar, "Mix Balance", "_RS_AI_MIX_BALANCE", "ai_mix.png")
  add_toolbar_button(ai_toolbar, "Auto EQ", "_RS_AI_AUTO_EQ", "ai_eq.png")
  add_toolbar_button(ai_toolbar, "Reference", "_RS_AI_REFERENCE", "ai_ref.png")
  
  msg("AI Integration Complete!")
end

-- Custom Menus
function create_custom_menus()
  msg("Creating custom menus...")
  
  local menu_structure = {
    {
      name = "Scott Mills Tools",
      items = {
        {name = "Load Mix Template", action = "_RS_LOAD_MIX_TEMPLATE"},
        {name = "Load Production Template", action = "_RS_LOAD_PROD_TEMPLATE"},
        {name = "-"},
        {name = "Analyze with AI", action = "_RS_AI_ANALYZE"},
        {name = "Match to Reference", action = "_RS_AI_REFERENCE"},
        {name = "-"},
        {name = "Quick Vocal Chain", action = "_RS_QUICK_VOX_CHAIN"},
        {name = "Quick Drum Chain", action = "_RS_QUICK_DRUM_CHAIN"},
        {name = "-"},
        {name = "Setup Parallel Compression", action = "_RS_PARALLEL_COMP"},
        {name = "Create Sidechain", action = "_RS_CREATE_SIDECHAIN"}
      }
    }
  }
  
  for _, menu in ipairs(menu_structure) do
    create_menu(menu.name, menu.items)
  end
end

-- Helper Functions
function create_track(name, parent, track_type, options)
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  local track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
  
  if options.color then
    reaper.SetTrackColor(track, options.color)
  end
  
  if parent then
    reaper.SetParent(track, parent)
  end
  
  return track
end

function create_folder_track(name, position)
  local track = create_track(name, nil, "folder", {color = rgb(100, 100, 100)})
  reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)
  return track
end

function rgb(r, g, b)
  return reaper.ColorToNative(r, g, b)|0x1000000
end

function get_track_by_name(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, track_name = reaper.GetTrackName(track)
    if track_name == name then
      return track
    end
  end
  return nil
end

-- Progress Display
function show_progress(step, total, message)
  local progress = math.floor((step / total) * 100)
  msg(string.format("[%d%%] %s", progress, message))
end

-- Main Installation Function
function main()
  msg("==============================================")
  msg("REAPER Ultimate Template System v" .. script_version)
  msg("Professional Audio Engineering Suite")
  msg("==============================================")
  msg("")
  
  local steps = {
    {func = install_master_templates, name = "Master Templates"},
    {func = install_signal_chains, name = "Signal Chains"},
    {func = install_protools_workflow, name = "Pro Tools Workflow"},
    {func = setup_ai_integration, name = "AI Integration"},
    {func = create_custom_menus, name = "Custom Menus"}
  }
  
  for i, step in ipairs(steps) do
    show_progress(i-1, #steps, "Installing " .. step.name .. "...")
    step.func()
    show_progress(i, #steps, step.name .. " Complete!")
    msg("")
  end
  
  msg("==============================================")
  msg("Installation Complete!")
  msg("")
  msg("Your REAPER installation now includes:")
  msg("• Advanced mixing and production templates")
  msg("• Professional signal chain presets")
  msg("• Pro Tools workflow enhancements")
  msg("• AI-powered analysis and assistance")
  msg("• Custom menus and toolbars")
  msg("")
  msg("Restart REAPER to ensure all features are loaded.")
  msg("==============================================")
  
  -- Open documentation
  local doc_path = install_path .. "Documentation.html"
  if reaper.file_exists(doc_path) then
    open_url("file://" .. doc_path)
  end
end

-- Run installation
main()
