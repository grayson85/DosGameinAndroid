#pragma once

#include "ring_buffer.h"
#include <AudioToolbox/AudioToolbox.h>

#include <mutex>

namespace dosbox_host {

class IosAudio {
public:
    explicit IosAudio(AudioRingBuffer& ringBuffer);
    ~IosAudio();

    bool start(double sampleRate);
    void pause();
    void resume();
    void stop();

private:
    static OSStatus renderCallback(
        void* inRefCon,
        AudioUnitRenderActionFlags* ioActionFlags,
        const AudioTimeStamp* inTimeStamp,
        UInt32 inBusNumber,
        UInt32 inNumberFrames,
        AudioBufferList* ioData);

    AudioRingBuffer& ringBuffer_;
    std::mutex audioMutex_;
    AudioComponentInstance audioUnit_ = nullptr;
    bool isRunning_ = false;
};

}  // namespace dosbox_host
