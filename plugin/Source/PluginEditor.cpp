#include "PluginEditor.h"

SGMUtilityAudioProcessorEditor::SGMUtilityAudioProcessorEditor(SGMUtilityAudioProcessor& owner)
    : AudioProcessorEditor(owner),
      processor(owner),
      gainAttachment(owner.parameters, "gain", gainSlider),
      bypassAttachment(owner.parameters, "bypass", bypassButton)
{
    title.setText("SGM Utility", juce::dontSendNotification);
    title.setFont(juce::FontOptions(24.0f, juce::Font::bold));
    title.setJustificationType(juce::Justification::centred);
    addAndMakeVisible(title);

    gainSlider.setSliderStyle(juce::Slider::RotaryHorizontalVerticalDrag);
    gainSlider.setTextBoxStyle(juce::Slider::TextBoxBelow, false, 100, 24);
    gainSlider.setDoubleClickReturnValue(true, 0.0);
    addAndMakeVisible(gainSlider);

    gainLabel.setText("Gain", juce::dontSendNotification);
    gainLabel.setJustificationType(juce::Justification::centred);
    gainLabel.attachToComponent(&gainSlider, false);
    addAndMakeVisible(gainLabel);

    addAndMakeVisible(bypassButton);
    setSize(360, 240);
}

void SGMUtilityAudioProcessorEditor::paint(juce::Graphics& graphics)
{
    graphics.fillAll(getLookAndFeel().findColour(juce::ResizableWindow::backgroundColourId));
}

void SGMUtilityAudioProcessorEditor::resized()
{
    auto area = getLocalBounds().reduced(24);
    title.setBounds(area.removeFromTop(42));
    area.removeFromTop(22);
    gainSlider.setBounds(area.removeFromTop(130).withSizeKeepingCentre(170, 130));
    bypassButton.setBounds(area.removeFromBottom(32).withSizeKeepingCentre(120, 28));
}
