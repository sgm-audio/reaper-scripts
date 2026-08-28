-- REAPER Advanced Signal Chain Library v3.0
-- Professional Audio Engineering Presets
-- Developed by Scott Mills Audio Systems

-- Signal Chain Architecture with AI Enhancement

SIGNAL_CHAIN_LIBRARY = {
  -- VOCAL PRODUCTION CHAINS
  vocal_chains = {
    -- Modern Pop Vocal Chain with AI Enhancement
    modern_pop_vocal = {
      name = "AI-Enhanced Pop Vocal",
      description = "Crystal-clear modern pop vocal with intelligent processing",
      
      input_stage = {
        {plugin = "Input Trim", params = {gain = 0, phase = 0, hpf = 80}},
        {plugin = "Pitch Correction", params = {speed = 65, natural = true, formant = true}}
      },
      
      dynamics_stage = {
        {plugin = "FET Compressor", params = {
          input = 24, output = 18, attack = 3, release = 7,
          ratio = "4:1", mix = 100, sidechain_filter = 120
        }},
        {plugin = "Optical Compressor", params = {
          gain_reduction = 3, makeup = "auto", frequency = "flat"
        }}
      },
      
      eq_stage = {
        {plugin = "Surgical EQ", params = {
          band1 = {freq = 180, gain = -2, q = 3, type = "bell"},
          band2 = {freq = 600, gain = -1.5, q = 6, type = "bell"},
          band3 = {freq = 3500, gain = 2, q = 0.7, type = "shelf"},
          band4 = {freq = 8000, gain = 3, q = 0.5, type = "shelf"},
          dynamic_bands = {2, 3}, -- AI-controlled dynamic EQ
        }},
        {plugin = "Analog EQ", params = {
          low_shelf = {freq = 100, gain = 2, character = "warm"},
          high_shelf = {freq = 10000, gain = 2.5, character = "air"}
        }}
      },
      
      enhancement_stage = {
        {plugin = "Harmonic Exciter", params = {
          low_harmonics = 15, high_harmonics = 25, mix = 20
        }},
        {plugin = "Tape Saturation", params = {
          drive = 3, bias = 0, flutter = 0.1, wow = 0.05
        }}
      },
      
      spatial_stage = {
        {plugin = "Dimension Expander", params = {width = 110, depth = 20}},
        {plugin = "Reverb Send", params = {
          amount = 15, predelay = 20, type = "plate", 
          eq_pre = {lpf = 8000, hpf = 200}
        }}
      },
      
      ai_processing = {
        adaptive_deessing = {enabled = true, sensitivity = "auto"},
        resonance_suppression = {enabled = true, threshold = -20},
        presence_optimization = {enabled = true, target = "streaming"}
      }
    },
    
    -- Rap/Hip-Hop Vocal Chain
    rap_vocal_chain = {
      name = "Modern Rap Vocal",
      description = "Punchy, present rap vocal with aggressive character",
      
      chain = {
        {plugin = "Gate", params = {threshold = -35, ratio = "10:1", attack = 0.1}},
        {plugin = "1176 Compressor", params = {input = 30, output = 20, attack = 3, release = 7, ratio = "8:1"}},
        {plugin = "SSL Channel EQ", params = {
          hpf = 100, lpf = 18000,
          lf = {gain = 3, freq = 200}, 
          lmf = {gain = -2, freq = 500, q = 2},
          hmf = {gain = 4, freq = 3000, q = 1.5},
          hf = {gain = 5, freq = 8000}
        }},
        {plugin = "Distortion", params = {drive = 15, mix = 25, tone = 70}},
        {plugin = "Limiter", params = {ceiling = -0.5, release = 50, lookahead = 1}}
      }
    },
    
    -- Podcast/Broadcast Chain
    broadcast_chain = {
      name = "Broadcast Ready Voice",
      description = "Professional broadcast standard voice processing",
      
      processing = {
        {plugin = "Noise Reduction", params = {learn_profile = true, reduction = 12}},
        {plugin = "De-breath", params = {sensitivity = 70, room_tone = true}},
        {plugin = "Multiband Comp", params = {
          low_band = {threshold = -18, ratio = "2:1", crossover = 120},
          mid_band = {threshold = -15, ratio = "3:1", crossover = 2500},
          high_band = {threshold = -12, ratio = "2:1"}
        }},
        {plugin = "Broadcast Limiter", params = {
          standard = "EBU R128", integrated = -16, true_peak = -1
        }}
      }
    }
  },
  
  -- INSTRUMENT CHAINS
  instrument_chains = {
    -- Modern Drum Kit Processing
    drum_kit = {
      kick = {
        name = "Punchy Modern Kick",
        chain = {
          {plugin = "Transient Designer", params = {attack = 5, sustain = -2}},
          {plugin = "EQ", params = {
            boost_60hz = 4, cut_250hz = -3, boost_3k = 2, 
            boost_6k = 1.5, hpf = 30
          }},
          {plugin = "Compressor", params = {
            threshold = -15, ratio = "4:1", attack = 10, 
            release = 100, knee = "hard"
          }},
          {plugin = "Clipper", params = {ceiling = -0.5, soft_clip = true}}
        }
      },
      
      snare = {
        name = "Crispy Snare",
        top_mic = {
          {plugin = "Gate", params = {threshold = -25, hold = 20, range = -15}},
          {plugin = "EQ", params = {
            cut_100hz = -2, boost_200hz = 3, boost_5k = 4,
            notch_600hz = {gain = -3, q = 8}
          }},
          {plugin = "Compressor", params = {threshold = -12, ratio = "4:1", attack = 5}}
        },
        bottom_mic = {
          {plugin = "Phase Align", params = {auto_align = true}},
          {plugin = "EQ", params = {boost_200hz = 2, boost_8k = 3}},
          {plugin = "Mix", params = {blend = 30}}
        }
      },
      
      overheads = {
        name = "Smooth Overheads",
        chain = {
          {plugin = "Console Emulation", params = {model = "vintage", drive = 2}},
          {plugin = "Stereo Imager", params = {width = 120, bass_mono = 200}},
          {plugin = "EQ", params = {hpf = 400, shelf_10k = 2}},
          {plugin = "Compressor", params = {threshold = -10, ratio = "2:1", mix = 50}}
        }
      },
      
      room_mics = {
        name = "Ambient Room",
        chain = {
          {plugin = "Mono Maker", params = {frequency = 120}},
          {plugin = "Compressor", params = {threshold = -20, ratio = "10:1", attack = 0.1}},
          {plugin = "EQ", params = {lpf = 8000, hpf = 100}},
          {plugin = "Blend", params = {amount = "to_taste"}}
        }
      }
    },
    
    -- Bass Guitar Processing
    bass_guitar = {
      di_chain = {
        name = "Modern Bass DI",
        chain = {
          {plugin = "DI Emulation", params = {model = "vintage_tube", warmth = 30}},
          {plugin = "Compressor", params = {threshold = -15, ratio = "4:1", attack = 10}},
          {plugin = "EQ", params = {
            boost_80hz = 3, cut_500hz = -2, boost_2k = 2,
            hpf = 40, presence = 3
          }}
        }
      },
      
      amp_chain = {
        name = "Bass Amp Character",
        chain = {
          {plugin = "Amp Simulator", params = {
            model = "vintage_svt", drive = 6, 
            bass = 7, mid = 5, treble = 6
          }},
          {plugin = "Cabinet Simulator", params = {
            model = "8x10_vintage", mic = "d112", 
            position = "cap_edge"
          }}
        }
      },
      
      parallel_processing = {
        clean = {gain = 70},
        distorted = {
          chain = {
            {plugin = "Distortion", params = {drive = 80, tone = 60}},
            {plugin = "EQ", params = {lpf = 3000, hpf = 200}}
          },
          gain = 30
        }
      }
    },
    
    -- Electric Guitar Chains
    electric_guitar = {
      clean_tone = {
        {plugin = "Amp Sim", params = {model = "twin_reverb", gain = 3}},
        {plugin = "Spring Reverb", params = {mix = 20, decay = 2.5}},
        {plugin = "Chorus", params = {rate = 1.5, depth = 25, mix = 40}},
        {plugin = "Compressor", params = {threshold = -10, ratio = "2:1"}}
      },
      
      lead_tone = {
        {plugin = "Tube Screamer", params = {drive = 7, tone = 5, level = 5}},
        {plugin = "Amp Sim", params = {model = "plexi", gain = 7}},
        {plugin = "Cabinet", params = {model = "4x12_vintage", mic_blend = "57/121"}},
        {plugin = "Delay", params = {time = "1/8D", feedback = 35, mix = 25}},
        {plugin = "Reverb", params = {type = "hall", mix = 15}}
      }
    },
    
    -- Synthesizer Processing
    synthesizer = {
      modern_lead = {
        {plugin = "Dimension", params = {width = 130, chorusing = 20}},
        {plugin = "Filter", params = {cutoff = 8000, resonance = 30, env = 50}},
        {plugin = "Compressor", params = {threshold = -10, ratio = "3:1"}},
        {plugin = "Delay", params = {
          left = "1/8T", right = "1/8", feedback = 40, 
          cross_feedback = 20, filter = 5000
        }}
      },
      
      analog_bass = {
        {plugin = "Analog Emulation", params = {warmth = 60, drift = 10}},
        {plugin = "Sub Enhancer", params = {frequency = 60, amount = 30}},
        {plugin = "Distortion", params = {tube = 20, tape = 15}}
      }
    }
  },
  
  -- MIX BUS CHAINS
  mix_bus_chains = {
    -- Analog Console Emulation
    analog_mix_bus = {
      name = "Analog Console Mix Bus",
      chain = {
        {plugin = "Console Emulation", params = {
          model = "ssl_4000g", drive = 1.5, 
          crosstalk = 20, noise = 5
        }},
        {plugin = "Bus Compressor", params = {
          threshold = -4, ratio = "2:1", attack = 10, 
          release = "auto", makeup = 2
        }},
        {plugin = "Tape Emulation", params = {
          ips = 15, flux = 3, wow_flutter = 0.1, 
          bias = 0, eq = "nab"
        }},
        {plugin = "Mix Bus EQ", params = {
          low_shelf = {freq = 60, gain = 0.5, q = 0.7},
          high_shelf = {freq = 12000, gain = 1, q = 0.7}
        }}
      }
    },
    
    -- Modern Digital Mix Bus
    digital_mix_bus = {
      name = "Transparent Digital Mix Bus",
      chain = {
        {plugin = "Linear Phase EQ", params = {
          corrections = "auto", matching = true
        }},
        {plugin = "Multiband Dynamics", params = {
          bands = 5, link_bands = true, 
          preserve_transients = true
        }},
        {plugin = "Stereo Imager", params = {
          low_mono = 120, high_width = 110, 
          correlation_meter = true
        }},
        {plugin = "True Peak Limiter", params = {
          ceiling = -1, release = 50, 
          oversampling = "4x", dither = "none"
        }}
      }
    },
    
    -- AI-Optimized Mix Bus
    ai_mix_bus = {
      name = "AI-Adaptive Mix Bus",
      chain = {
        {plugin = "AI Analyzer", params = {
          reference_track = true, genre_detection = true,
          streaming_target = "spotify", realtime = true
        }},
        {plugin = "Adaptive EQ", params = {
          match_reference = true, preserve_character = 70,
          dynamic_adaptation = true
        }},
        {plugin = "Smart Compressor", params = {
          program_dependent = true, transient_preserve = true,
          spectral_compression = true
        }},
        {plugin = "Intelligent Limiter", params = {
          lufs_target = -14, true_peak = -1,
          codec_compensation = true
        }}
      }
    }
  },
  
  -- MASTERING CHAINS
  mastering_chains = {
    -- Genre-Specific Mastering
    genres = {
      pop = {
        {plugin = "Linear EQ", params = {presence_boost = 2, air = 1.5}},
        {plugin = "Multiband Comp", params = {glue_mode = true}},
        {plugin = "Tape Saturation", params = {warmth = 15}},
        {plugin = "Limiter", params = {lufs = -9, true_peak = -1}}
      },
      
      edm = {
        {plugin = "Sub Enhancement", params = {frequency = 50, boost = 2}},
        {plugin = "Multiband Comp", params = {pump_mode = true}},
        {plugin = "Spectral Shaper", params = {brightness = 20}},
        {plugin = "Clipper", params = {hard_clip = 0.5}},
        {plugin = "Limiter", params = {lufs = -6, true_peak = -0.5}}
      },
      
      jazz = {
        {plugin = "Vintage EQ", params = {transparency = true}},
        {plugin = "Gentle Comp", params = {ratio = "1.5:1", slow_attack = true}},
        {plugin = "Tape Emulation", params = {subtle = true}},
        {plugin = "Limiter", params = {lufs = -16, preserve_dynamics = true}}
      }
    },
    
    -- Delivery Format Chains
    delivery_formats = {
      streaming = {
        spotify = {target_lufs = -14, true_peak = -1, codec_preview = "ogg_320"},
        apple_music = {target_lufs = -16, true_peak = -1, spatial_check = true},
        youtube = {target_lufs = -14, true_peak = -1, codec_preview = "opus"}
      },
      
      physical = {
        cd = {bit_depth = 16, sample_rate = 44100, dither = "pow-r3"},
        vinyl = {mono_bass = 150, phase_check = true, headroom = 3}
      }
    }
  },
  
  -- ROUTING MATRIX CONFIGURATIONS
  routing_configurations = {
    -- Send Effects Routing
    send_effects = {
      reverbs = {
        hall = {predelay = 30, decay = 2.5, eq = {hpf = 200, lpf = 8000}},
        room = {predelay = 10, decay = 1.2, early_reflections = 60},
        plate = {predelay = 0, decay = 2.0, modulation = 2},
        spring = {tension = 70, decay = 3.0, drip = 20},
        shimmer = {pitch = "+12", decay = 5.0, mix = 50}
      },
      
      delays = {
        quarter = {time = "1/4", feedback = 35, filter = 6000},
        eighth_dot = {time = "1/8D", feedback = 45, pan = "ping_pong"},
        multi_tap = {taps = {1, 3, 5, 7}, feedback = 30, spread = 80}
      },
      
      modulation = {
        chorus = {voices = 4, rate = 1.5, depth = 30},
        phaser = {stages = 12, rate = 0.5, feedback = 50},
        flanger = {rate = 0.3, depth = 60, manual = 50}
      }
    },
    
    -- Parallel Processing
    parallel_routing = {
      drum_parallel = {
        dry = 70,
        compressed = {
          chain = {
            {plugin = "1176", params = {ratio = "20:1", all_buttons = true}},
            {plugin = "EQ", params = {boost_100 = 3, boost_10k = 4}}
          },
          blend = 30
        }
      },
      
      vocal_parallel = {
        dry = 80,
        excitement = {
          chain = {
            {plugin = "Exciter", params = {harmonics = 40}},
            {plugin = "Compressor", params = {ratio = "10:1"}}
          },
          blend = 20
        }
      }
    }
  },
  
  -- AUTOMATION TEMPLATES
  automation_templates = {
    -- Dynamic Automation
    dynamic_automation = {
      vocal_rides = {
        verse_to_chorus = {gain_change = 3, transition_time = 500},
        bridge_pullback = {gain_change = -2, eq_change = {hpf = 200}},
        adlib_throws = {send_increase = 40, timing = "musical"}
      },
      
      instrument_automation = {
        filter_sweeps = {rate = "tempo_sync", depth = "midi_cc"},
        spatial_movement = {pan_lfo = true, depth_automation = true},
        dynamic_eq = {frequency_tracking = true, ai_assisted = true}
      }
    },
    
    -- Mix Automation
    mix_automation = {
      arrangement_based = {
        intro_filtering = {hpf_sweep = {20, 80}, time = "4_bars"},
        drop_impact = {all_tracks_gain = -3, kick_snare_gain = 0},
        breakdown = {reverb_increase = 30, delay_feedback = 60}
      },
      
      reference_matching = {
        enabled = true,
        update_rate = "per_section",
        parameters = [eq_curve", "dynamics", "stereo_width]
      }
    }
  },
  
  -- METERING AND ANALYSIS
  metering_config = {
    -- Meter Types
    meters = {
      level_meters = {
        peak = {hold_time = 3000, fall_time = 20},
        rms = {integration_time = 300, k_weighting = true},
        lufs = {short_term = 3, momentary = 0.4, integrated = true}
      },
      
      spectral_meters = {
        spectrum_analyzer = {
          fft_size = 8192, 
          averaging = "exponential",
          slope = 4.5,
          bands = "1/3_octave"
        },
        
        correlation_meter = {
          display = "goniometer",
          phase_warnings = true,
          history = 10
        }
      },
      
      loudness_meters = {
        standards = ["ebu_r128", "atsc_a85", "aes_streaming"],
        true_peak = true,
        history_graph = true,
        loudness_range = true
      }
    }
  }
}

-- Export function for REAPER integration
function export_to_reaper()
  -- Convert to REAPER-compatible format
  return {
    version = "3.0",
    chains = SIGNAL_CHAIN_LIBRARY,
    metadata = {
      author = "Scott Mills Audio Systems",
      created = os.date(),
      compatibility = "REAPER 6.0+"
    }
  }
end

return SIGNAL_CHAIN_LIBRARY
