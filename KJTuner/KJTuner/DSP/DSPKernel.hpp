/*
	<samplecode>
 <abstract>
 Utility code to manage scheduled parameters in an audio unit implementation.
 </abstract>
	</samplecode>
 */

#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <algorithm>
#import "ParameterRamper.hpp"
#import "KJTuner.h"

extern "C" {
#include "soundpipe.h"
}


template <typename T>
T clamp(T input, T low, T high) {
    return std::min(std::max(input, low), high);
}


// Put your DSP code into a subclass of DSPKernel.
class DSPKernel {
public:
    virtual void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) = 0;
    virtual void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) = 0;
    
    // Override to handle MIDI events.
    virtual void handleMIDIEvent(AUMIDIEvent const& midiEvent) {}
    
    void processWithEvents(AudioTimeStamp const* timestamp, AUAudioFrameCount frameCount, AURenderEvent const* events);
    
private:
    void handleOneEvent(AURenderEvent const* event);
    void performAllSimultaneousEvents(AUEventSampleTime now, AURenderEvent const*& event);
};

class KJDSPKernel: public DSPKernel {
protected:
    int channels = 2;
    float sampleRate = 44100;
public:
    KJDSPKernel(int _channels, float _sampleRate):
      channels(_channels), sampleRate(_sampleRate) { }

    KJDSPKernel(): KJDSPKernel(2, 44100) { }

    virtual ~KJDSPKernel() { }
    //
    // todo: these should be constructors but the original samples
    // had init methods
    //

    virtual void init(int _channels, double _sampleRate) {
        channels = _channels;
        sampleRate = _sampleRate;
    }
};

class ParametricKernel {
protected:
    virtual ParameterRamper& getRamper(AUParameterAddress address) = 0;

public:

    AUValue getParameter(AUParameterAddress address) {
        return getRamper(address).getUIValue();
    }

    void setParameter(AUParameterAddress address, AUValue value) {
        return getRamper(address).setUIValue(value);
    }
    virtual void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) {
        getRamper(address).startRamp(value, duration);
    }
};

class OutputBuffered {
protected:
    AudioBufferList *outBufferListPtr = nullptr;
public:
    void setBuffer(AudioBufferList *outBufferList) {
        outBufferListPtr = outBufferList;
    }
};

class Buffered: public OutputBuffered {
protected:
    AudioBufferList *inBufferListPtr = nullptr;
public:
    void setBuffers(AudioBufferList *inBufferList, AudioBufferList *outBufferList) {
        OutputBuffered::setBuffer(outBufferList);
        inBufferListPtr = inBufferList;

    }
};

class SoundpipeKernel: public KJDSPKernel {
protected:
    sp_data *sp = nullptr;
public:
//    SoundpipeKernel(int _channels, float _sampleRate):
//        KJDSPKernel(_channels, _sampleRate) {
//
//      sp_create(&sp);
//      sp->sr = _sampleRate;
//      sp->nchan = _channels;
//    }

    void init(int _channels, double _sampleRate) override {
      KJDSPKernel::init(_channels, _sampleRate);
      sp_create(&sp);
      sp->sr = _sampleRate;
      sp->nchan = _channels;
    }

    ~SoundpipeKernel() {
        //printf("~SoundpipeKernel(), &sp is %p\n", (void *)sp);
        // releasing the memory in the destructor only
        sp_destroy(&sp);
    }
    
    void destroy() {
        //printf("SoundpipeKernel.destroy(), &sp is %p\n", (void *)sp);
    }
};


