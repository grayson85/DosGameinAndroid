#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

namespace dosbox_host {

// Lock-free Single-Producer Single-Consumer (SPSC) ring buffer for stereo int16 PCM samples.
class AudioRingBuffer {
public:
    explicit AudioRingBuffer(size_t capacityPow2 = 65536)
        : capacity_(nextPow2(capacityPow2)),
          mask_(capacity_ - 1),
          buffer_(capacity_, 0) {}

    void clear() {
        readPos_.store(0, std::memory_order_release);
        writePos_.store(0, std::memory_order_release);
    }

    size_t availableRead() const {
        const size_t w = writePos_.load(std::memory_order_acquire);
        const size_t r = readPos_.load(std::memory_order_relaxed);
        return w - r;
    }

    size_t availableWrite() const {
        return capacity_ - availableRead();
    }

    size_t write(const int16_t* data, size_t count) {
        const size_t w = writePos_.load(std::memory_order_relaxed);
        const size_t r = readPos_.load(std::memory_order_acquire);
        const size_t freeSpace = capacity_ - (w - r);
        const size_t toWrite = (count < freeSpace) ? count : freeSpace;
        if (toWrite == 0) return 0;

        const size_t start = w & mask_;
        const size_t firstChunk = capacity_ - start;
        if (toWrite <= firstChunk) {
            std::memcpy(&buffer_[start], data, toWrite * sizeof(int16_t));
        } else {
            std::memcpy(&buffer_[start], data, firstChunk * sizeof(int16_t));
            std::memcpy(&buffer_[0], data + firstChunk, (toWrite - firstChunk) * sizeof(int16_t));
        }
        writePos_.store(w + toWrite, std::memory_order_release);
        return toWrite;
    }

    size_t read(int16_t* out, size_t count) {
        const size_t r = readPos_.load(std::memory_order_relaxed);
        const size_t w = writePos_.load(std::memory_order_acquire);
        const size_t avail = w - r;
        const size_t toRead = (count < avail) ? count : avail;
        if (toRead == 0) return 0;

        const size_t start = r & mask_;
        const size_t firstChunk = capacity_ - start;
        if (toRead <= firstChunk) {
            std::memcpy(out, &buffer_[start], toRead * sizeof(int16_t));
        } else {
            std::memcpy(out, &buffer_[start], firstChunk * sizeof(int16_t));
            std::memcpy(out + firstChunk, &buffer_[0], (toRead - firstChunk) * sizeof(int16_t));
        }
        readPos_.store(r + toRead, std::memory_order_release);
        return toRead;
    }

private:
    static size_t nextPow2(size_t v) {
        size_t p = 1;
        while (p < v) p <<= 1;
        return p;
    }

    const size_t capacity_;
    const size_t mask_;
    std::vector<int16_t> buffer_;
    std::atomic<size_t> readPos_{0};
    std::atomic<size_t> writePos_{0};
};

}  // namespace dosbox_host
