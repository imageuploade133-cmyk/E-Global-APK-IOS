package com.eglobal.wallet

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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
        }
    }

    private val CHANNEL = "com.eglobal.wallet/mediastore"
    private val HAPTICS_CHANNEL = "com.eglobal.wallet/haptics"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HAPTICS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "vibrate") {
                try {
                    val vibrator = getSystemService(android.content.Context.VIBRATOR_SERVICE) as android.os.Vibrator
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        vibrator.vibrate(
                            android.os.VibrationEffect.createOneShot(
                                60L,
                                android.os.VibrationEffect.DEFAULT_AMPLITUDE
                            )
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(60L)
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
            if (tempFile.exists()) {
                tempFile.delete()
            }
            return null
        }
    }
}
