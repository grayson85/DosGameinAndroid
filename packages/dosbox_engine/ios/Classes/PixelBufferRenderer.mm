#import "PixelBufferRenderer.h"
#include "libretro.h"

#include <cstdint>
#include <cstring>
#include <mutex>

@implementation DosboxPixelBufferRenderer {
    __weak id<FlutterTextureRegistry> _registry;
    CVPixelBufferRef _frontBuffer;
    CVPixelBufferRef _backBuffer;
    unsigned _bufWidth;
    unsigned _bufHeight;
    std::mutex _bufferMutex;
}

- (instancetype)initWithTextureRegistry:(id<FlutterTextureRegistry>)registry {
    self = [super init];
    if (self) {
        _registry = registry;
        _frontBuffer = nullptr;
        _backBuffer = nullptr;
        _bufWidth = 0;
        _bufHeight = 0;
        _textureId = -1;
    }
    return self;
}

- (void)dealloc {
    [self releaseBuffers];
}

- (CVPixelBufferRef)createBufferWithWidth:(unsigned)width height:(unsigned)height {
    NSDictionary *attrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
        (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    CVPixelBufferRef pb = nullptr;
    CVReturn rc = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attrs,
        &pb
    );
    return (rc == kCVReturnSuccess) ? pb : nullptr;
}

- (void)ensureBuffersForWidth:(unsigned)width height:(unsigned)height {
    if (_bufWidth == width && _bufHeight == height && _frontBuffer && _backBuffer) {
        return;
    }
    if (_frontBuffer) {
        CVPixelBufferRelease(_frontBuffer);
        _frontBuffer = nullptr;
    }
    if (_backBuffer) {
        CVPixelBufferRelease(_backBuffer);
        _backBuffer = nullptr;
    }
    _frontBuffer = [self createBufferWithWidth:width height:height];
    _backBuffer = [self createBufferWithWidth:width height:height];
    _bufWidth = (_frontBuffer && _backBuffer) ? width : 0;
    _bufHeight = (_frontBuffer && _backBuffer) ? height : 0;
}

- (void)renderFrame:(const void *)data
              width:(unsigned)width
             height:(unsigned)height
              pitch:(size_t)pitch
        pixelFormat:(unsigned)pixelFormat {
    if (!data || width == 0 || height == 0) return;

    CVPixelBufferRef target = nullptr;
    {
        std::lock_guard<std::mutex> lk(_bufferMutex);
        [self ensureBuffersForWidth:width height:height];
        target = _backBuffer;
        if (!target) return;
        CVPixelBufferRetain(target);
    }

    if (CVPixelBufferLockBaseAddress(target, 0) == kCVReturnSuccess) {
        uint8_t *dstBase = static_cast<uint8_t *>(CVPixelBufferGetBaseAddress(target));
        const size_t dstStride = CVPixelBufferGetBytesPerRow(target);
        const uint8_t *srcBase = static_cast<const uint8_t *>(data);

        if (pixelFormat == RETRO_PIXEL_FORMAT_XRGB8888) {
            // Little-endian XRGB8888 is already [B, G, R, X] == BGRA; set alpha to 0xFF.
            for (unsigned y = 0; y < height; ++y) {
                const uint32_t *srcRow = reinterpret_cast<const uint32_t *>(srcBase + y * pitch);
                uint32_t *dstRow = reinterpret_cast<uint32_t *>(dstBase + y * dstStride);
                for (unsigned x = 0; x < width; ++x) {
                    dstRow[x] = srcRow[x] | 0xFF000000u;
                }
            }
        } else {
            // RGB565 -> BGRA8888
            for (unsigned y = 0; y < height; ++y) {
                const uint16_t *srcRow = reinterpret_cast<const uint16_t *>(srcBase + y * pitch);
                uint32_t *dstRow = reinterpret_cast<uint32_t *>(dstBase + y * dstStride);
                for (unsigned x = 0; x < width; ++x) {
                    const uint16_t p = srcRow[x];
                    const uint32_t r = ((p >> 11) & 0x1F) * 255 / 31;
                    const uint32_t g = ((p >> 5) & 0x3F) * 255 / 63;
                    const uint32_t b = (p & 0x1F) * 255 / 31;
                    dstRow[x] = 0xFF000000u | (r << 16) | (g << 8) | b;
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(target, 0);
    }

    {
        std::lock_guard<std::mutex> lk(_bufferMutex);
        if (target == _backBuffer) {
            CVPixelBufferRef tmp = _frontBuffer;
            _frontBuffer = _backBuffer;
            _backBuffer = tmp;
        }
    }
    CVPixelBufferRelease(target);

    id<FlutterTextureRegistry> reg = _registry;
    int64_t tid = _textureId;
    if (reg && tid >= 0) {
        [reg textureFrameAvailable:tid];
    }
}

- (CVPixelBufferRef)copyPixelBuffer {
    std::lock_guard<std::mutex> lk(_bufferMutex);
    if (!_frontBuffer) return nullptr;
    CVPixelBufferRetain(_frontBuffer);
    return _frontBuffer;
}

- (void)releaseBuffers {
    std::lock_guard<std::mutex> lk(_bufferMutex);
    if (_frontBuffer) {
        CVPixelBufferRelease(_frontBuffer);
        _frontBuffer = nullptr;
    }
    if (_backBuffer) {
        CVPixelBufferRelease(_backBuffer);
        _backBuffer = nullptr;
    }
    _bufWidth = 0;
    _bufHeight = 0;
}

@end
