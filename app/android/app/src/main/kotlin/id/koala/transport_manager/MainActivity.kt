package id.koala.transport_manager

import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // TextureView: frame Flutter ikut jalur render Android biasa. Dengan
    // SurfaceView, HP uji (MIUI, Android 16) menahan vsync saat layar statis
    // sehingga ketukan baru tampil setelah puluhan detik.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Jam untuk validasi waktu offline: elapsedRealtime tidak bisa diubah
        // pengguna; BOOT_COUNT membedakan sesi boot.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "transport_manager/clock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sample" -> {
                        val bootCount = try {
                            Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT)
                        } catch (e: Settings.SettingNotFoundException) {
                            -1
                        }
                        result.success(
                            mapOf(
                                "wallClockMs" to System.currentTimeMillis(),
                                "monotonicMs" to SystemClock.elapsedRealtime(),
                                "bootId" to bootCount.toString(),
                            )
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
