#pragma once

#include "ring_buffer.h"
#include <oboe/Oboe.h>

#include <memory>
#include <mutex>

namespace dosbox_host {

class OboeAudio : public oboe::AudioStreamDataCallback {
public:
    explicit OboeAudio(AudioRingBuffer& ringBuffer);
    ~OboeAudio() override;

    bool start(int32_t sampleRate);
    void pause();
    void resume();
    void stop();

    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* audioStream, void* audioData, int32_t numFrames) override;

private:
    AudioRingBuffer& ringBuffer_;
    std::mutex streamMutex_;
    std::shared_ptr<oboe::AudioStream> stream_;
    int32_t sampleRate_ = 44100;
};

}  // namespace dosbox_host
