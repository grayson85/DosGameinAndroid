#import <AVFoundation/AVFoundation.h>
#include "IosAudio.h"

#include <cstring>

namespace dosbox_host {

IosAudio::IosAudio(AudioRingBuffer& ringBuffer) : ringBuffer_(ringBuffer) {}

IosAudio::~IosAudio() {
    stop();
}

bool IosAudio::start(double sampleRate) {
    stop();
    std::lock_guard<std::mutex> lk(audioMutex_);

    const double rate = sampleRate > 8000.0 ? sampleRate : 48000.0;

    NSError *sessionErr = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionMixWithOthers
                   error:&sessionErr];
    [session setPreferredSampleRate:rate error:&sessionErr];
    [session setPreferredIOBufferDuration:0.015 error:&sessionErr];
    [session setActive:YES error:&sessionErr];

    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp) return false;

    if (AudioComponentInstanceNew(comp, &audioUnit_) != noErr || !audioUnit_) {
        return false;
    }

    UInt32 enableOutput = 1;
    AudioUnitSetProperty(
        audioUnit_,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output,
        0,
        &enableOutput,
        sizeof(enableOutput));

    AudioStreamBasicDescription asbd{};
    asbd.mSampleRate = rate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mFramesPerPacket = 1;
    asbd.mChannelsPerFrame = 2;
    asbd.mBitsPerChannel = 16;
    asbd.mBytesPerFrame = 4;
    asbd.mBytesPerPacket = 4;

    if (AudioUnitSetProperty(
            audioUnit_,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &asbd,
            sizeof(asbd)) != noErr) {
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }

    AURenderCallbackStruct cb{};
    cb.inputProc = &IosAudio::renderCallback;
    cb.inputProcRefCon = this;

    if (AudioUnitSetProperty(
            audioUnit_,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &cb,
            sizeof(cb)) != noErr) {
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }

    if (AudioUnitInitialize(audioUnit_) != noErr) {
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }

    if (AudioOutputUnitStart(audioUnit_) != noErr) {
        AudioUnitUninitialize(audioUnit_);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
        return false;
    }

    isRunning_ = true;
    return true;
}

void IosAudio::pause() {
    std::lock_guard<std::mutex> lk(audioMutex_);
    if (audioUnit_ && isRunning_) {
        AudioOutputUnitStop(audioUnit_);
        isRunning_ = false;
    }
}

void IosAudio::resume() {
    std::lock_guard<std::mutex> lk(audioMutex_);
    if (audioUnit_ && !isRunning_) {
        if (AudioOutputUnitStart(audioUnit_) == noErr) {
            isRunning_ = true;
        }
    }
}

void IosAudio::stop() {
    std::lock_guard<std::mutex> lk(audioMutex_);
    if (audioUnit_) {
        if (isRunning_) {
            AudioOutputUnitStop(audioUnit_);
            isRunning_ = false;
        }
        AudioUnitUninitialize(audioUnit_);
        AudioComponentInstanceDispose(audioUnit_);
        audioUnit_ = nullptr;
    }
}

OSStatus IosAudio::renderCallback(
    void* inRefCon,
    AudioUnitRenderActionFlags* /*ioActionFlags*/,
    const AudioTimeStamp* /*inTimeStamp*/,
    UInt32 /*inBusNumber*/,
    UInt32 inNumberFrames,
    AudioBufferList* ioData) {
    auto* self = static_cast<IosAudio*>(inRefCon);
    if (!self || !ioData || ioData->mNumberBuffers == 0) return noErr;

    auto* out = static_cast<int16_t*>(ioData->mBuffers[0].mData);
    const size_t samplesNeeded = static_cast<size_t>(inNumberFrames) * 2;
    const size_t samplesRead = self->ringBuffer_.read(out, samplesNeeded);
    if (samplesRead < samplesNeeded) {
        std::memset(out + samplesRead, 0, (samplesNeeded - samplesRead) * sizeof(int16_t));
    }
    ioData->mBuffers[0].mDataByteSize = static_cast<UInt32>(samplesNeeded * sizeof(int16_t));
    return noErr;
}

}  // namespace dosbox_host
