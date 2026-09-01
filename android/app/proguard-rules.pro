# R8 keep rules for the release build (isMinifyEnabled = true in
# build.gradle.kts).
#
# Everything here exists because the class is reached by REFLECTION or from
# native code, which R8's static analysis cannot see. A missing rule does not
# fail the build - it fails at runtime, in release only, which is precisely
# the failure mode a debug-build test pass will never surface.

# ── flutter_local_notifications ──────────────────────────────────────────
# The plugin serialises scheduled notifications to disk with Gson so they
# survive a reboot (RECEIVE_BOOT_COMPLETED in the manifest). Gson reads the
# model classes' field names reflectively, so R8 renaming them makes every
# already-scheduled reminder fail to deserialise after an update or restart -
# the reminders simply stop arriving, with no crash to point at.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
# Gson keeps generic type information in signatures.
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# -keepattributes Signature above is necessary but NOT sufficient under R8's
# full mode, which is the default from AGP 8. Full mode still strips the
# generic signature from TypeToken subclasses unless they are named
# explicitly, and the plugin builds one as an anonymous inner class
# (FlutterLocalNotificationsPlugin$1) to deserialise the scheduled-reminder
# list. Without these two rules the release build throws on first use:
#
#   IllegalStateException: TypeToken must be created with a type argument:
#   new TypeToken<...>() {}; When using code shrinkers (ProGuard, R8, ...)
#   make sure that generic signatures are preserved.
#
# It surfaces through loadScheduledNotifications, so cancelling, rescheduling
# or restoring ANY reminder fails. Caught on an API 33 emulator with the
# release APK; a debug build never shows it because R8 does not run.
# These two lines are Gson's own documented R8 requirement.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# ── RevenueCat / Google Play Billing ─────────────────────────────────────
# purchases_flutter talks to the Play Billing Library, whose callback
# interfaces are invoked by the Play Store app across a process boundary.
-keep class com.revenuecat.purchases.** { *; }
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.api.** { *; }
-dontwarn com.revenuecat.purchases.**

# ── Firebase / Crashlytics ───────────────────────────────────────────────
# The Firebase SDKs ship their own consumer rules, so this is deliberately
# thin. These two only preserve what makes a CRASH REPORT readable: line
# numbers, and the original source file name in the stack trace.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── Flutter engine ───────────────────────────────────────────────────────
# Referenced from the engine's C++ side via JNI.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
