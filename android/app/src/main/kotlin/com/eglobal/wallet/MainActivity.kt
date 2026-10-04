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
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

class MainActivity: FlutterFragmentActivity() {
    private val BIOMETRIC_KEY_ALIAS = "eglobal_biometric_auth_key"
    private val BIOMETRIC_CHANNEL = "com.eglobal.wallet/biometric_key"
    private var activeBiometricPrompt: BiometricPrompt? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Disable Android Autofill for the entire app view hierarchy.
            window.decorView.importantForAutofill =
                android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS

            createHighImportanceNotificationChannel()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cancelActiveBiometricPrompt()
    }

    // Note: Do NOT cancel activeBiometricPrompt on onStop/onPause because Android BiometricPrompt
    // system UI overlay causes onPause/onStop on the host Activity!

    private fun cancelActiveBiometricPrompt() {
        try {
            activeBiometricPrompt?.cancelAuthentication()
            activeBiometricPrompt = null
        } catch (_: Exception) {}
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "createBiometricKey" -> {
                    try {
                        createKeystoreKey()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("KEY_CREATION_FAILED", e.localizedMessage, null)
                    }
                }
                "authenticateWithCryptoObject" -> {
                    val title = call.argument<String>("title") ?: "Biometric Authentication"
                    val subtitle = call.argument<String>("subtitle") ?: "Authenticate to access E-Global Pay"
                    val createIfMissing = call.argument<Boolean>("createIfMissing") ?: false
                    authenticateWithCryptoObject(title, subtitle, createIfMissing, result)
                }
                "validateBiometricKey" -> {
                    try {
                        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                        if (!keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val key = keyStore.getKey(BIOMETRIC_KEY_ALIAS, null) as? SecretKey
                        if (key == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val cipher = Cipher.getInstance("${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_CBC}/${KeyProperties.ENCRYPTION_PADDING_PKCS7}")
                        cipher.init(Cipher.ENCRYPT_MODE, key)
                        result.success(true)
                    } catch (e: KeyPermanentlyInvalidatedException) {
                        // Biometric enrollment changed! KeyStore automatically invalidated key.
                        deleteKeystoreKey()
                        result.success(false)
                    } catch (e: UserNotAuthenticatedException) {
                        // Key exists and is valid, but requires biometric auth
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "deleteBiometricKey" -> {
                    deleteKeystoreKey()
                    result.success(true)
                }
                "cancelBiometricPrompt" -> {
                    cancelActiveBiometricPrompt()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

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

    private fun authenticateWithCryptoObject(
        title: String,
        subtitle: String,
        createIfMissing: Boolean,
        methodResult: MethodChannel.Result
    ) {
        cancelActiveBiometricPrompt()

        val biometricManager = BiometricManager.from(this)
        val canAuth = biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            methodResult.success(mapOf("success" to false, "error" to "Biometrics not available or strong biometrics missing", "code" to "BIOMETRIC_UNAVAILABLE"))
            return
        }

        val cipher: Cipher
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val keyExists = keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)

            if (!keyExists) {
                if (!createIfMissing) {
                    methodResult.success(mapOf("success" to false, "error" to "Biometric key missing", "code" to "KEY_MISSING"))
                    return
                } else {
                    createKeystoreKey()
                    keyStore.load(null)
                }
            }

            val key = keyStore.getKey(BIOMETRIC_KEY_ALIAS, null) as? SecretKey
            if (key == null) {
                methodResult.success(mapOf("success" to false, "error" to "Biometric key missing", "code" to "KEY_MISSING"))
                return
            }

            cipher = Cipher.getInstance("${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_CBC}/${KeyProperties.ENCRYPTION_PADDING_PKCS7}")
            cipher.init(Cipher.ENCRYPT_MODE, key)
        } catch (e: KeyPermanentlyInvalidatedException) {
            deleteKeystoreKey()
            methodResult.success(mapOf("success" to false, "error" to "Biometric enrollment changed", "code" to "KEY_INVALIDATED"))
            return
        } catch (e: Exception) {
            methodResult.success(mapOf("success" to false, "error" to e.localizedMessage, "code" to "KEY_INIT_FAILED"))
            return
        }

        val cryptoObject = BiometricPrompt.CryptoObject(cipher)
        val executor = ContextCompat.getMainExecutor(this)

        var completed = false

        val prompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                super.onAuthenticationSucceeded(authResult)
                if (completed) return
                completed = true
                activeBiometricPrompt = null

                activeBiometricPrompt = null
                methodResult.success(mapOf("success" to true))
            }

            override fun onAuthenticationFailed() {
                super.onAuthenticationFailed()
                // Fingerprint not recognized: System prompt displays retry message.
                // Do NOT mark completed or return failure so user can retry on native prompt.
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                super.onAuthenticationError(errorCode, errString)
                if (completed) return
                completed = true
                activeBiometricPrompt = null

                val codeStr = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON -> "USER_CANCELED"
                    BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "LOCKOUT"
                    BiometricPrompt.ERROR_TIMEOUT -> "TIMEOUT"
                    else -> "ERROR_$errorCode"
                }
                methodResult.success(mapOf("success" to false, "error" to errString.toString(), "code" to codeStr))
            }
        })

        activeBiometricPrompt = prompt

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        prompt.authenticate(promptInfo, cryptoObject)
    }

    private fun createKeystoreKey(): SecretKey {
        deleteKeystoreKey()

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val builder = KeyGenParameterSpec.Builder(
            BIOMETRIC_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
            .setUserAuthenticationRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setInvalidatedByBiometricEnrollment(true)
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }

    private fun deleteKeystoreKey() {
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)) {
                keyStore.deleteEntry(BIOMETRIC_KEY_ALIAS)
            }
        } catch (_: Exception) {}
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