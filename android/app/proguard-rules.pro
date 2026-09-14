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

# Secure Storage Proguard Rules
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class android.security.** { *; }

# Permission Handler Proguard Rules
-keep class com.baseflow.permissionhandler.** { *; }

# Connectivity Plus Proguard Rules
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Share Plus Proguard Rules
-keep class dev.fluttercommunity.plus.share.** { *; }

# Path Provider Proguard Rules
-keep class io.flutter.plugins.pathprovider.** { *; }

# OpenFileX Proguard Rules
-keep class com.jnj.myopenfile.** { *; }

# Riverpod Proguard Rules
-keep class com.example.riverpod.** { *; }
-dontwarn com.example.riverpod.**

# Optimize and shrink resource usage
-optimizations !code/simplification/arithmetic,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification

# Performance optimizations for faster app startup
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile