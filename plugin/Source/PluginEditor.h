#pragma once

#include "PluginProcessor.h"

class SGMUtilityAudioProcessorEditor final : public juce::AudioProcessorEditor
{
public:
    explicit SGMUtilityAudioProcessorEditor(SGMUtilityAudioProcessor&);
    ~SGMUtilityAudioProcessorEditor() override = default;

    void paint(juce::Graphics&) override;
    void resized() override;

private:
    SGMUtilityAudioProcessor& processor;
    juce::Label title;
    juce::Slider gainSlider;
    juce::Label gainLabel;
    juce::ToggleButton bypassButton { "Bypass" };
    juce::AudioProcessorValueTreeState::SliderAttachment gainAttachment;
    juce::AudioProcessorValueTreeState::ButtonAttachment bypassAttachment;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(SGMUtilityAudioProcessorEditor)
};
