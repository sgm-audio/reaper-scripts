#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <type_traits>

namespace
{
juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout()
{
    using Parameter = juce::AudioParameterFloat;
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> parameters;
    parameters.push_back(std::make_unique<Parameter>(
        juce::ParameterID { "gain", 1 }, "Gain",
        juce::NormalisableRange<float>(-60.0f, 12.0f, 0.1f), 0.0f,
        juce::AudioParameterFloatAttributes().withLabel("dB")));
    parameters.push_back(std::make_unique<juce::AudioParameterBool>(
        juce::ParameterID { "bypass", 1 }, "Bypass", false));
    return { parameters.begin(), parameters.end() };
}
} // namespace

SGMUtilityAudioProcessor::SGMUtilityAudioProcessor()
    : AudioProcessor(BusesProperties()
          .withInput("Input", juce::AudioChannelSet::stereo(), true)
          .withOutput("Output", juce::AudioChannelSet::stereo(), true)),
      parameters(*this, nullptr, "PARAMETERS", createParameterLayout())
{
    gain.setCurrentAndTargetValue(1.0f);
    doubleGain.setCurrentAndTargetValue(1.0);
}

void SGMUtilityAudioProcessor::prepareToPlay(double sampleRate, int)
{
    gain.reset(sampleRate, 0.020);
    doubleGain.reset(sampleRate, 0.020);
    const auto decibels = parameters.getRawParameterValue("gain")->load();
    const auto linear = juce::Decibels::decibelsToGain<double>(decibels, -60.0);
    gain.setCurrentAndTargetValue(static_cast<float>(linear));
    doubleGain.setCurrentAndTargetValue(linear);
}

void SGMUtilityAudioProcessor::releaseResources() {}

bool SGMUtilityAudioProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const
{
    const auto input = layouts.getMainInputChannelSet();
    const auto output = layouts.getMainOutputChannelSet();
    if (input != output)
        return false;

    return output == juce::AudioChannelSet::mono()
        || output == juce::AudioChannelSet::stereo();
}

template <typename SampleType>
void SGMUtilityAudioProcessor::process(juce::AudioBuffer<SampleType>& buffer)
{
    juce::ScopedNoDenormals noDenormals;
    for (auto channel = getTotalNumInputChannels(); channel < getTotalNumOutputChannels(); ++channel)
        buffer.clear(channel, 0, buffer.getNumSamples());

    if (parameters.getRawParameterValue("bypass")->load() >= 0.5f)
        return;

    const auto decibels = parameters.getRawParameterValue("gain")->load();
    const auto linear = juce::Decibels::decibelsToGain<double>(decibels, -60.0);
    if constexpr (std::is_same<SampleType, float>::value)
    {
        gain.setTargetValue(static_cast<float>(linear));
        gain.applyGain(buffer, buffer.getNumSamples());
    }
    else
    {
        doubleGain.setTargetValue(linear);
        doubleGain.applyGain(buffer, buffer.getNumSamples());
    }
}

void SGMUtilityAudioProcessor::processBlock(juce::AudioBuffer<float>& buffer,
                                            juce::MidiBuffer&)
{
    process(buffer);
}

void SGMUtilityAudioProcessor::processBlock(juce::AudioBuffer<double>& buffer,
                                            juce::MidiBuffer&)
{
    process(buffer);
}

juce::AudioProcessorEditor* SGMUtilityAudioProcessor::createEditor()
{
    return new SGMUtilityAudioProcessorEditor(*this);
}

void SGMUtilityAudioProcessor::getStateInformation(juce::MemoryBlock& destData)
{
    if (auto state = parameters.copyState().createXml())
        copyXmlToBinary(*state, destData);
}

void SGMUtilityAudioProcessor::setStateInformation(const void* data, int sizeInBytes)
{
    if (data == nullptr || sizeInBytes <= 0)
        return;

    const std::unique_ptr<juce::XmlElement> xml(getXmlFromBinary(data, sizeInBytes));
    if (xml != nullptr && xml->hasTagName(parameters.state.getType()))
    {
        const auto state = juce::ValueTree::fromXml(*xml);
        if (state.isValid())
            parameters.replaceState(state);
    }
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new SGMUtilityAudioProcessor();
}
