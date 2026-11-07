#include "PluginProcessor.h"

#include <cmath>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace
{
void expect(bool condition, const char* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

void expectNear(float actual, float expected, float tolerance, const char* message)
{
    if (std::abs(actual - expected) > tolerance)
        throw std::runtime_error(message);
}

void setParameter(SGMUtilityAudioProcessor& processor, const char* id, float value)
{
    auto* parameter = processor.parameters.getParameter(id);
    expect(parameter != nullptr, "parameter is missing");
    parameter->setValueNotifyingHost(parameter->convertTo0to1(value));
}

void testProcessing()
{
    SGMUtilityAudioProcessor processor;
    processor.prepareToPlay(48000.0, 128);

    juce::AudioBuffer<float> buffer(2, 128);
    juce::MidiBuffer midi;
    buffer.clear();
    processor.processBlock(buffer, midi);
    expectNear(buffer.getSample(0, 0), 0.0f, 1.0e-7f, "silence was not preserved");

    buffer.clear();
    for (auto channel = 0; channel < buffer.getNumChannels(); ++channel)
        for (auto sample = 0; sample < buffer.getNumSamples(); ++sample)
            buffer.setSample(channel, sample, 0.25f);
    processor.processBlock(buffer, midi);
    expectNear(buffer.getSample(1, 64), 0.25f, 1.0e-6f, "unity gain changed audio");

    setParameter(processor, "gain", 6.0f);
    for (auto block = 0; block < 20; ++block)
    {
        for (auto channel = 0; channel < buffer.getNumChannels(); ++channel)
            for (auto sample = 0; sample < buffer.getNumSamples(); ++sample)
                buffer.setSample(channel, sample, 0.25f);
        processor.processBlock(buffer, midi);
    }
    expectNear(buffer.getSample(0, 127), 0.25f * 1.9952623f, 1.0e-4f,
               "gain parameter did not reach its target");

    setParameter(processor, "bypass", 1.0f);
    buffer.applyGain(0.5f);
    const auto beforeBypass = buffer.getSample(0, 0);
    processor.processBlock(buffer, midi);
    expectNear(buffer.getSample(0, 0), beforeBypass, 1.0e-7f, "bypass changed audio");
    processor.releaseResources();
}

void testDoublePrecisionAndState()
{
    SGMUtilityAudioProcessor processor;
    processor.setProcessingPrecision(juce::AudioProcessor::doublePrecision);
    processor.prepareToPlay(96000.0, 64);
    juce::AudioBuffer<double> buffer(2, 64);
    juce::MidiBuffer midi;
    for (auto channel = 0; channel < buffer.getNumChannels(); ++channel)
        for (auto sample = 0; sample < buffer.getNumSamples(); ++sample)
            buffer.setSample(channel, sample, 0.125);
    processor.processBlock(buffer, midi);
    const auto actual = buffer.getSample(0, 32);
    if (std::abs(actual - 0.125) >= 1.0e-12)
    {
        std::ostringstream details;
        details << std::setprecision(17)
                << "double-precision unity processing changed audio: actual=" << actual
                << ", gain=" << processor.parameters.getRawParameterValue("gain")->load()
                << ", inputs=" << processor.getTotalNumInputChannels()
                << ", outputs=" << processor.getTotalNumOutputChannels()
                << ", bufferChannels=" << buffer.getNumChannels();
        throw std::runtime_error(details.str());
    }

    setParameter(processor, "gain", 9.0f);
    juce::MemoryBlock state;
    processor.getStateInformation(state);
    expect(state.getSize() > 0, "state was not serialized");

    SGMUtilityAudioProcessor restored;
    setParameter(restored, "gain", -12.0f);
    restored.setStateInformation(state.getData(), static_cast<int>(state.getSize()));
    expectNear(restored.parameters.getRawParameterValue("gain")->load(), 9.0f, 1.0e-5f,
               "state did not restore the gain parameter");

    const char invalid[] = "not a plugin state";
    restored.setStateInformation(invalid, static_cast<int>(sizeof(invalid)));
    expectNear(restored.parameters.getRawParameterValue("gain")->load(), 9.0f, 1.0e-5f,
               "invalid state corrupted parameters");
}

void testBusLayouts()
{
    SGMUtilityAudioProcessor processor;
    auto layout = processor.getBusesLayout();
    expect(processor.isBusesLayoutSupported(layout), "stereo layout was rejected");
    layout.inputBuses.getReference(0) = juce::AudioChannelSet::mono();
    layout.outputBuses.getReference(0) = juce::AudioChannelSet::mono();
    expect(processor.isBusesLayoutSupported(layout), "mono layout was rejected");
    layout.outputBuses.getReference(0) = juce::AudioChannelSet::stereo();
    expect(! processor.isBusesLayoutSupported(layout), "mismatched bus layout was accepted");
}
} // namespace

int main()
{
    try
    {
        testProcessing();
        testDoublePrecisionAndState();
        testBusLayouts();
        std::cout << "SGM Utility native tests passed.\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "SGM Utility test failure: " << error.what() << '\n';
        return 1;
    }
}
