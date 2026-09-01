package com.growdaily.v2

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Opens this app's own system notification settings.
     *
     * Exists because there is no Dart-side way to do it. The notification
     * settings screen's "notifications are off" banner used to call
     * `launchUrl('app-settings:')`, which is an iOS-only scheme: on Android
     * url_launcher builds a plain ACTION_VIEW with `Uri.parse("app-settings:")`
     * (see UrlLauncher.java - it does NOT use Intent.parseUri with
     * URI_INTENT_SCHEME, so an `intent:` URI is no help either), nothing
     * resolves it, and the button silently did nothing. Verified on an
     * Android 13 emulator: the intent was dispatched and the foreground
     * activity never changed.
     *
     * ACTION_APP_NOTIFICATION_SETTINGS only exists from API 26. Below that,
     * fall back to the app-info page, which is where notification controls
     * lived then anyway.
     */
    private val channelName = "com.growdaily.v2/system_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        result.success(openNotificationSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationSettings(): Boolean {
        val intents = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intents.add(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
            )
        }
        // Always available, and the right destination pre-API 26.
        intents.add(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null)),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try the next one rather than surfacing a crash for what is
                // only ever a convenience shortcut.
            }
        }
        return false
    }
}
