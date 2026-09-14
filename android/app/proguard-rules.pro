# Flutter Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.embedding.**  { *; }
-keep class io.flutter.provider.**  { *; }
-keep class io.flutter.plugin.editing.** { *; }

# InAppWebView Proguard Rules - CRITICAL for WebView performance
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# local_auth Proguard Rules
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# Play Core Proguard Rules
-dontwarn com.google.android.play.core.**
