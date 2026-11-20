package com.gs.dosbox_engine

import android.content.Context
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

internal object DosboxNative {
    init {
        System.loadLibrary("dosbox_host")
    }

    @JvmStatic
    external fun nativeStartGame(
        corePath: String,
        gamePath: String,
        saveDir: String,
        systemDir: String,
        surface: Surface,
        linearFilter: Boolean,
        optionKeys: Array<String>,
        optionValues: Array<String>,
    ): String?

    @JvmStatic external fun nativeGetAspectRatio(): Float
    @JvmStatic external fun nativePause()
    @JvmStatic external fun nativeResume()
    @JvmStatic external fun nativeStop()
    @JvmStatic external fun nativeReset()
    @JvmStatic external fun nativeSetFastForward(multiplier: Int)
    @JvmStatic external fun nativeSetLinearFilter(enabled: Boolean)
    @JvmStatic external fun nativeUpdateCoreOption(key: String, value: String)
    @JvmStatic external fun nativeSendKeyEvent(retroKey: Int, down: Boolean)
    @JvmStatic external fun nativeSendMouseDelta(dx: Int, dy: Int)
    @JvmStatic external fun nativeSendMouseButton(button: Int, down: Boolean)
    @JvmStatic external fun nativeSendPointer(normX: Int, normY: Int, pressed: Boolean)
    @JvmStatic external fun nativeSendJoypadButton(retroId: Int, down: Boolean)
    @JvmStatic external fun nativeSaveState(): ByteArray?
    @JvmStatic external fun nativeLoadState(data: ByteArray): Boolean
}

class DosboxEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private lateinit var textureRegistry: TextureRegistry

    private var surfaceEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var activeSurface: Surface? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "com.gs.dosbox_engine")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseSession()
        channel.setMethodCallHandler(null)
    }

    private fun releaseSession() {
        DosboxNative.nativeStop()
        activeSurface?.release()
        activeSurface = null
        surfaceEntry?.release()
        surfaceEntry = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startGame" -> {
                val gamePath = call.argument<String>("gamePath")
                val saveDir = call.argument<String>("saveDir")
                val systemDir = call.argument<String>("systemDir")
                val linearFilter = call.argument<Boolean>("linearFilter") ?: false
                @Suppress("UNCHECKED_CAST")
                val coreOptions = call.argument<Map<String, String>>("coreOptions") ?: emptyMap()

                if (gamePath.isNullOrEmpty() || saveDir.isNullOrEmpty() || systemDir.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "gamePath, saveDir, and systemDir are required.", null)
                    return
                }

                val coreFile = File(appContext.applicationInfo.nativeLibraryDir, "libdosbox_pure_libretro_android.so")
                if (!coreFile.exists()) {
                    result.error(
                        "MISSING_CORE",
                        "DOSBox-Pure core not found at ${coreFile.absolutePath}. Please build with CI or place arm64-v8a .so in jniLibs.",
                        null
                    )
                    return
                }

                File(saveDir).mkdirs()
                File(systemDir).mkdirs()

                releaseSession()

                val entry = textureRegistry.createSurfaceTexture()
                val surfaceTexture = entry.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(640, 480)
                val surface = Surface(surfaceTexture)

                surfaceEntry = entry
                activeSurface = surface

                val keys = coreOptions.keys.toTypedArray()
                val values = keys.map { coreOptions[it] ?: "" }.toTypedArray()

                val err = DosboxNative.nativeStartGame(
                    coreFile.absolutePath,
                    gamePath,
                    saveDir,
                    systemDir,
                    surface,
                    linearFilter,
                    keys,
                    values,
                )

                if (err != null) {
                    releaseSession()
                    result.error("START_FAILED", err, null)
                } else {
                    result.success(
                        mapOf(
                            "textureId" to entry.id(),
                            "aspectRatio" to DosboxNative.nativeGetAspectRatio().toDouble(),
                        )
                    )
                }
            }

            "pause" -> {
                DosboxNative.nativePause()
                result.success(null)
            }

            "resume" -> {
                DosboxNative.nativeResume()
                result.success(null)
            }

            "stop" -> {
                releaseSession()
                result.success(null)
            }

            "reset" -> {
                DosboxNative.nativeReset()
                result.success(null)
            }

            "setFastForward" -> {
                val multiplier = call.argument<Int>("multiplier") ?: 1
                DosboxNative.nativeSetFastForward(multiplier)
                result.success(null)
            }

            "setLinearFilter" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                DosboxNative.nativeSetLinearFilter(enabled)
                result.success(null)
            }

            "updateCoreOption" -> {
                val key = call.argument<String>("key") ?: ""
                val value = call.argument<String>("value") ?: ""
                if (key.isNotEmpty()) {
                    DosboxNative.nativeUpdateCoreOption(key, value)
                }
                result.success(null)
            }

            "sendKeyEvent" -> {
                val key = call.argument<Int>("key") ?: 0
                val down = call.argument<Boolean>("down") ?: false
                DosboxNative.nativeSendKeyEvent(key, down)
                result.success(null)
            }

            "sendMouseDelta" -> {
                val dx = call.argument<Int>("dx") ?: 0
                val dy = call.argument<Int>("dy") ?: 0
                DosboxNative.nativeSendMouseDelta(dx, dy)
                result.success(null)
            }

            "sendMouseButton" -> {
                val button = call.argument<Int>("button") ?: 0
                val down = call.argument<Boolean>("down") ?: false
                DosboxNative.nativeSendMouseButton(button, down)
                result.success(null)
            }

            "sendPointer" -> {
                val x = call.argument<Int>("x") ?: 0
                val y = call.argument<Int>("y") ?: 0
                val pressed = call.argument<Boolean>("pressed") ?: false
                DosboxNative.nativeSendPointer(x, y, pressed)
                result.success(null)
            }

            "sendJoypadButton" -> {
                val id = call.argument<Int>("id") ?: 0
                val down = call.argument<Boolean>("down") ?: false
                DosboxNative.nativeSendJoypadButton(id, down)
                result.success(null)
            }

            "saveState" -> {
                result.success(DosboxNative.nativeSaveState())
            }

            "loadState" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.success(false)
                } else {
                    result.success(DosboxNative.nativeLoadState(data))
                }
            }

            else -> result.notImplemented()
        }
    }
}
