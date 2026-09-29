package com.eglobal.wallet

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

class MainActivity: FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Disable Android Autofill for the entire app view hierarchy.
            window.decorView.importantForAutofill =
                android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS

            createHighImportanceNotificationChannel()
        }
    }

    private fun createHighImportanceNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "eglobal_wallet_high_channel"
            val channelName = "E-Global Wallet Notifications"
            val channelDescription = "This channel is used for important wallet updates."
            val importance = NotificationManager.IMPORTANCE_HIGH

            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                enableVibration(true)
                enableLights(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                setSound(Settings.System.DEFAULT_NOTIFICATION_URI, audioAttributes)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private val CHANNEL = "com.eglobal.wallet/mediastore"
    private val HAPTICS_CHANNEL = "com.eglobal.wallet/haptics"
    private val SECURITY_CHANNEL = "com.eglobal.wallet/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isDeveloperModeEnabled") {
                try {
                    val devMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                        Settings.Global.getInt(contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) != 0
                    } else {
                        @Suppress("DEPRECATION")
                        Settings.Secure.getInt(contentResolver, Settings.Secure.DEVELOPMENT_SETTINGS_ENABLED, 0) != 0
                    }
                    result.success(devMode)
                } catch (e: Exception) {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HAPTICS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "vibrate") {
                try {
                    val vibrator = getSystemService(android.content.Context.VIBRATOR_SERVICE) as android.os.Vibrator
                    val type = call.argument<String>("type") ?: "default"
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        val effect = when (type) {
                            "keypress", "pin" -> {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                    android.os.VibrationEffect.createPredefined(android.os.VibrationEffect.EFFECT_CLICK)
                                } else {
                                    android.os.VibrationEffect.createOneShot(40L, 180)
                                }
                            }
                            "heavy", "impact" -> {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                    android.os.VibrationEffect.createPredefined(android.os.VibrationEffect.EFFECT_HEAVY_CLICK)
                                } else {
                                    android.os.VibrationEffect.createOneShot(70L, 255)
                                }
                            }
                            else -> android.os.VibrationEffect.createOneShot(60L, android.os.VibrationEffect.DEFAULT_AMPLITUDE)
                        }
                        vibrator.vibrate(effect)
                    } else {
                        val duration = when (type) {
                            "keypress", "pin" -> 35L
                            "heavy", "impact" -> 70L
                            else -> 60L
                        }
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(duration)
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("HAPTIC_FAILED", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                val tempFilePath = call.argument<String>("tempFilePath")
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType")

                if (tempFilePath == null || fileName == null) {
                    result.error("INVALID_ARGUMENTS", "Missing tempFilePath or fileName", null)
                    return@setMethodCallHandler
                }

                try {
                    val publicPath = saveFileToPublicDownloads(tempFilePath, fileName, mimeType ?: "*/*")
                    if (publicPath != null) {
                        result.success(publicPath)
                    } else {
                        result.error("SAVE_FAILED", "Failed to save file to MediaStore Downloads", null)
                    }
                } catch (e: Exception) {
                    result.error("EXCEPTION", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveFileToPublicDownloads(tempFilePath: String, fileName: String, mimeType: String): String? {
        val tempFile = File(tempFilePath)
        if (!tempFile.exists()) return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/E-Global Pay")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val itemUri: Uri = resolver.insert(collection, contentValues) ?: return null

            try {
                resolver.openOutputStream(itemUri)?.use { outputStream ->
                    FileInputStream(tempFile).use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                }

                contentValues.clear()
                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(itemUri, contentValues, null, null)

                return itemUri.toString()
            } catch (e: Exception) {
                resolver.delete(itemUri, null, null)
                throw e
            } finally {
                tempFile.delete()
            }
        } else {
            try {
                @Suppress("DEPRECATION")
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = File(downloadsDir, "E-Global Pay")
                if (!targetDir.exists()) {
                    targetDir.mkdirs()
                }
                val targetFile = File(targetDir, fileName)
                FileInputStream(tempFile).use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                tempFile.delete()
                return targetFile.absolutePath
            } catch (e: Exception) {
                if (tempFile.exists()) {
                    tempFile.delete()
                }
                return null
            }
        }
    }
}
