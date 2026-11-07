cmake_minimum_required(VERSION 3.22)
project(SGMUtility VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# For offline/reproducible development, point this at a JUCE 8.0.4 checkout.
set(SGM_JUCE_SOURCE_DIR "" CACHE PATH "Existing JUCE source tree (optional)")
if(SGM_JUCE_SOURCE_DIR)
    add_subdirectory("${SGM_JUCE_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/juce")
else()
    include(FetchContent)
    if(POLICY CMP0135)
        cmake_policy(SET CMP0135 NEW)
    endif()
    # JUCE 8.0.4, immutable commit archive with verified content checksum.
    FetchContent_Declare(JUCE
        URL https://codeload.github.com/juce-framework/JUCE/tar.gz/51d11a2be6d5c97ccf12b4e5e827006e19f0555a
        URL_HASH SHA256=840a8f14cf40ef25d83c80a72f5f7a5ce1a4ce2243bc9b2c7756276966ccc69d)
    FetchContent_MakeAvailable(JUCE)
endif()

juce_add_plugin(SGMUtility
    PRODUCT_NAME "SGM Utility"
    COMPANY_NAME "SGM Audio"
    COMPANY_WEBSITE "https://github.com/sgm-audio/reaper-scripts"
    BUNDLE_ID com.sgmaudio.SGMUtility
    PLUGIN_MANUFACTURER_CODE SgmA
    PLUGIN_CODE SgU1
    FORMATS VST3 Standalone
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS FALSE
    VST3_CATEGORIES Fx Tools)

juce_generate_juce_header(SGMUtility)
target_sources(SGMUtility PRIVATE
    Source/PluginProcessor.cpp
    Source/PluginProcessor.h
    Source/PluginEditor.cpp
    Source/PluginEditor.h)
target_compile_definitions(SGMUtility PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0)
target_include_directories(SGMUtility PRIVATE Source)
target_link_libraries(SGMUtility PRIVATE
    juce::juce_audio_utils
    juce::juce_recommended_config_flags
    juce::juce_recommended_lto_flags
    juce::juce_recommended_warning_flags)

include(CTest)
if(BUILD_TESTING)
    juce_add_console_app(SGMUtilityTests PRODUCT_NAME "SGM Utility Tests")
    juce_generate_juce_header(SGMUtilityTests)
    target_sources(SGMUtilityTests PRIVATE
        Tests/PluginTests.cpp
        Source/PluginProcessor.cpp
        Source/PluginProcessor.h
        Source/PluginEditor.cpp
        Source/PluginEditor.h)
    target_compile_definitions(SGMUtilityTests PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0)
    target_include_directories(SGMUtilityTests PRIVATE Source)
    target_link_libraries(SGMUtilityTests PRIVATE
        juce::juce_audio_utils
        juce::juce_recommended_config_flags
        juce::juce_recommended_warning_flags)
    add_test(NAME SGMUtilityTests COMMAND SGMUtilityTests)
endif()
