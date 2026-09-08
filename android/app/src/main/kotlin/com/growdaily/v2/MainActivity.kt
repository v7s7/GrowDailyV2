package com.growdaily.v2

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: the health package's
// Health Connect permission flow launches an androidx ActivityResult
// contract, which needs a FragmentActivity host on Android 14+. Same
// Flutter engine behaviour otherwise.
class MainActivity : FlutterFragmentActivity() {

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

    /**
     * The two ways Health Connect asks an app to explain itself, both
     * declared against this activity in AndroidManifest.xml.
     *
     * ACTION_SHOW_PERMISSIONS_RATIONALE is the "read the app's privacy
     * policy" link inside Health Connect's own permission sheet;
     * ACTION_VIEW_PERMISSION_USAGE is the Android 14+ equivalent reached
     * through the activity-alias. Declaring the filters is what makes Health
     * Connect show those links at all — and until now both of them simply
     * opened the habit grid, which is a dead end for someone who tapped
     * "privacy policy" and a requirement Health Connect states outright.
     */
    private val healthRationaleActions = setOf(
        "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE",
        "android.intent.action.VIEW_PERMISSION_USAGE",
    )

    /**
     * The served copy of the policy, the same URL the paywall links to
     * (see PremiumScreen's privacy link) and the same document as
     * public/privacy.html in this repo.
     */
    private val privacyPolicyUrl = "https://grow-daily-339ef.web.app/privacy.html"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        maybeShowPrivacyPolicy(intent)
    }

    // Health Connect can hand this to an activity that is already running,
    // in which case onCreate never fires again.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        maybeShowPrivacyPolicy(intent)
    }

    /**
     * Opens the policy in a browser when Health Connect asked for it, and
     * does nothing on every ordinary launch.
     *
     * A browser rather than an in-app screen because the policy has no
     * in-app screen to route to — it lives as a hosted page, which is also
     * the copy Play's Data safety form and the App Store listing point at,
     * so there is exactly one document and no second copy to drift.
     */
    private fun maybeShowPrivacyPolicy(intent: Intent?) {
        if (intent?.action !in healthRationaleActions) return
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(privacyPolicyUrl))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            // No browser on the device. The app still opens behind this,
            // which is no worse than the behaviour this replaced.
        }
    }

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
