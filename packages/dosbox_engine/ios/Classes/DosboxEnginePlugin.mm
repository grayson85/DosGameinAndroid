#import "DosboxEnginePlugin.h"
#import "IosAudio.h"
#import "PixelBufferRenderer.h"
#include "libretro_host.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

struct IosEngineSession {
    dosbox_host::LibretroHost host;
    std::unique_ptr<dosbox_host::IosAudio> audio;
    DosboxPixelBufferRenderer *renderer = nil;

    explicit IosEngineSession(DosboxPixelBufferRenderer *r) : renderer(r) {
        audio = std::make_unique<dosbox_host::IosAudio>(host.audioBuffer());
        __weak DosboxPixelBufferRenderer *weakRenderer = r;
        host.setVideoCallback([weakRenderer](const void *data, unsigned w, unsigned h,
                                             size_t pitch, unsigned fmt) {
            DosboxPixelBufferRenderer *strongRenderer = weakRenderer;
            if (strongRenderer) {
                [strongRenderer renderFrame:data width:w height:h pitch:pitch pixelFormat:fmt];
            }
        });
        host.setAudioConfigCallback([this](double sampleRate) {
            if (audio) {
                audio->start(sampleRate);
            }
        });
    }

    ~IosEngineSession() {
        host.stop();
        if (audio) audio->stop();
        if (renderer) [renderer releaseBuffers];
    }
};

}  // namespace

@implementation DosboxEnginePlugin {
    id<FlutterTextureRegistry> _textureRegistry;
    dispatch_queue_t _lifecycleQueue;
    std::unique_ptr<IosEngineSession> _session;
    DosboxPixelBufferRenderer *_activeRenderer;
    int64_t _activeTextureId;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel =
        [FlutterMethodChannel methodChannelWithName:@"com.gs.dosbox_engine"
                                    binaryMessenger:[registrar messenger]];
    DosboxEnginePlugin *instance =
        [[DosboxEnginePlugin alloc] initWithTextureRegistry:[registrar textures]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithTextureRegistry:(id<FlutterTextureRegistry>)registry {
    self = [super init];
    if (self) {
        _textureRegistry = registry;
        _lifecycleQueue = dispatch_queue_create("com.gs.dosbox_engine.lifecycle", DISPATCH_QUEUE_SERIAL);
        _activeTextureId = -1;
    }
    return self;
}

- (void)dealloc {
    _session.reset();
    if (_activeTextureId >= 0) {
        [_textureRegistry unregisterTexture:_activeTextureId];
        _activeTextureId = -1;
    }
    _activeRenderer = nil;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *method = call.method;
    NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};

    if ([method isEqualToString:@"startGame"]) {
        NSString *gamePath = args[@"gamePath"];
        NSString *saveDir = args[@"saveDir"];
        NSString *systemDir = args[@"systemDir"];
        NSDictionary<NSString *, NSString *> *coreOptions = args[@"coreOptions"] ?: @{};

        if (gamePath.length == 0 || saveDir.length == 0 || systemDir.length == 0) {
            result([FlutterError errorWithCode:@"INVALID_ARGS"
                                       message:@"gamePath, saveDir, and systemDir are required."
                                       details:nil]);
            return;
        }

        DosboxPixelBufferRenderer *renderer =
            [[DosboxPixelBufferRenderer alloc] initWithTextureRegistry:_textureRegistry];
        int64_t texId = [_textureRegistry registerTexture:renderer];
        renderer.textureId = texId;

        dosbox_host::HostConfig config;
        config.corePath = "static://dosbox_pure";
        config.gamePath = gamePath.UTF8String;
        config.saveDir = saveDir.UTF8String;
        config.systemDir = systemDir.UTF8String;
        for (NSString *k in coreOptions) {
            NSString *v = coreOptions[k];
            if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSString class]]) {
                config.coreOptions[k.UTF8String] = v.UTF8String;
            }
        }

        dispatch_async(_lifecycleQueue, ^{
            [[NSFileManager defaultManager] createDirectoryAtPath:saveDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            [[NSFileManager defaultManager] createDirectoryAtPath:systemDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];

            self->_session.reset();
            auto nextSession = std::make_unique<IosEngineSession>(renderer);
            std::string err;
            const bool ok = nextSession->host.start(config, err);
            const double aspect = ok ? static_cast<double>(nextSession->host.aspectRatio()) : (4.0 / 3.0);

            if (ok) {
                self->_session = std::move(nextSession);
            } else {
                nextSession.reset();
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) {
                    [self->_textureRegistry unregisterTexture:texId];
                    result([FlutterError errorWithCode:@"START_FAILED"
                                               message:[NSString stringWithUTF8String:err.c_str()]
                                               details:nil]);
                } else {
                    if (self->_activeTextureId >= 0) {
                        [self->_textureRegistry unregisterTexture:self->_activeTextureId];
                    }
                    self->_activeRenderer = renderer;
                    self->_activeTextureId = texId;
                    result(@{
                        @"textureId" : @(texId),
                        @"aspectRatio" : @(aspect),
                    });
                }
            });
        });
        return;
    }

    if ([method isEqualToString:@"pause"]) {
        if (_session) {
            _session->host.pause();
            if (_session->audio) _session->audio->pause();
        }
        result(nil);
        return;
    }

    if ([method isEqualToString:@"resume"]) {
        if (_session) {
            if (_session->audio) _session->audio->resume();
            _session->host.resume();
        }
        result(nil);
        return;
    }

    if ([method isEqualToString:@"stop"]) {
        int64_t oldTexId = _activeTextureId;
        _activeTextureId = -1;
        _activeRenderer = nil;
        dispatch_async(_lifecycleQueue, ^{
            self->_session.reset();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (oldTexId >= 0) {
                    [self->_textureRegistry unregisterTexture:oldTexId];
                }
                result(nil);
            });
        });
        return;
    }

    if ([method isEqualToString:@"reset"]) {
        if (_session) _session->host.reset();
        result(nil);
        return;
    }

    if ([method isEqualToString:@"setFastForward"]) {
        int mult = [args[@"multiplier"] intValue];
        if (_session) _session->host.setFastForward(mult);
        result(nil);
        return;
    }

    if ([method isEqualToString:@"setLinearFilter"]) {
        // Metal FlutterTexture filtering is handled by Flutter's Texture(filterQuality:).
        result(nil);
        return;
    }

    if ([method isEqualToString:@"updateCoreOption"]) {
        NSString *key = args[@"key"];
        NSString *val = args[@"value"];
        if (_session && key.length > 0 && val != nil) {
            _session->host.updateCoreOption(key.UTF8String, val.UTF8String);
        }
        result(nil);
        return;
    }

    if ([method isEqualToString:@"sendKeyEvent"]) {
        unsigned key = [args[@"key"] unsignedIntValue];
        bool down = [args[@"down"] boolValue];
        if (_session) _session->host.sendKeyEvent(key, down);
        result(nil);
        return;
    }

    if ([method isEqualToString:@"sendMouseDelta"]) {
        int32_t dx = [args[@"dx"] intValue];
        int32_t dy = [args[@"dy"] intValue];
        if (_session) _session->host.sendMouseDelta(dx, dy);
        result(nil);
        return;
    }

    if ([method isEqualToString:@"sendMouseButton"]) {
        int btn = [args[@"button"] intValue];
        bool down = [args[@"down"] boolValue];
        if (_session) _session->host.sendMouseButton(btn, down);
        result(nil);
        return;
    }

    if ([method isEqualToString:@"sendPointer"]) {
        int16_t x = static_cast<int16_t>([args[@"x"] intValue]);
        int16_t y = static_cast<int16_t>([args[@"y"] intValue]);
        bool pressed = [args[@"pressed"] boolValue];
        if (_session) _session->host.sendPointer(x, y, pressed);
        result(nil);
        return;
    }

    if ([method isEqualToString:@"sendJoypadButton"]) {
        unsigned btnId = [args[@"id"] unsignedIntValue];
        bool down = [args[@"down"] boolValue];
        if (_session) _session->host.sendJoypadButton(btnId, down);
        result(nil);
        return;
    }

    if ([method isEqualToString:@"saveState"]) {
        if (!_session) {
            result(nil);
            return;
        }
        std::vector<uint8_t> data;
        if (!_session->host.serializeState(data) || data.empty()) {
            result(nil);
            return;
        }
        NSData *nsData = [NSData dataWithBytes:data.data() length:data.size()];
        result([FlutterStandardTypedData typedDataWithBytes:nsData]);
        return;
    }

    if ([method isEqualToString:@"loadState"]) {
        FlutterStandardTypedData *typed = args[@"data"];
        if (!_session || ![typed isKindOfClass:[FlutterStandardTypedData class]] || typed.data.length == 0) {
            result(@(NO));
            return;
        }
        const bool ok = _session->host.unserializeState(
            static_cast<const uint8_t *>(typed.data.bytes),
            typed.data.length);
        result(@(ok));
        return;
    }

    result(FlutterMethodNotImplemented);
}

@end
