package com.tivuq.iptv

import android.os.Bundle
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.CookieHandler
import java.net.CookieManager
import java.net.CookiePolicy

@UnstableApi
class MainActivity : FlutterActivity() {
    lateinit var displayRefreshRateManager: DisplayRefreshRateManager
        private set
    private var localCompanionPlugin: LocalCompanionPlugin? = null

    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        // Bazı IPTV sunucuları ilk yönlendirmede oturum çerezi üretir ve
        // manifest/segment isteklerinde aynı çerezi bekler. İki yerel motorun
        // aynı HTTP oturumunu kullanması redirect döngüsünü ve 403'leri önler.
        CookieHandler.setDefault(CookieManager(null, CookiePolicy.ACCEPT_ALL))
        displayRefreshRateManager = DisplayRefreshRateManager(this)
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        localCompanionPlugin?.stop()
        localCompanionPlugin = null
        if (::displayRefreshRateManager.isInitialized) {
            displayRefreshRateManager.restoreImmediately()
        }
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        pausePlaybackForBackground()
        super.onUserLeaveHint()
    }

    override fun onStop() {
        pausePlaybackForBackground()
        super.onStop()
    }

    private fun pausePlaybackForBackground() {
        Exo2PlayerPlugin.instance?.pauseForBackground()
        Media3PlayerView.activeInstance?.pauseForBackground()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AutoLaunchService.METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    AutoLaunchService.configure(this, enabled)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        DeviceIdentityPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        Media3PlayerPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        Exo2PlayerPlugin(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )
        NativeLiveTvPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
        localCompanionPlugin = LocalCompanionPlugin(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.tivuq.iptv/media3_view",
            Media3Factory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
