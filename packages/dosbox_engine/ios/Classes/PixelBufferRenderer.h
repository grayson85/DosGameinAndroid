#import <CoreVideo/CoreVideo.h>
#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Double-buffered CVPixelBuffer renderer implementing FlutterTexture for zero-copy Metal display on iPadOS/iOS.
@interface DosboxPixelBufferRenderer : NSObject <FlutterTexture>

@property(nonatomic, assign) int64_t textureId;

- (instancetype)initWithTextureRegistry:(id<FlutterTextureRegistry>)registry;
- (void)renderFrame:(const void *)data
              width:(unsigned)width
             height:(unsigned)height
              pitch:(size_t)pitch
        pixelFormat:(unsigned)pixelFormat;
- (void)releaseBuffers;

@end

NS_ASSUME_NONNULL_END
