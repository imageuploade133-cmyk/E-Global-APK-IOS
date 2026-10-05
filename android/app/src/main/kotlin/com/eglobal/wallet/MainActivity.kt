package com.eglobal.wallet

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.annotation.NonNull
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
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

class MainActivity : FlutterFragmentActivity() {
    private val BIOMETRIC_CHANNEL = "com.eglobal.wallet/biometric_key"
    private val HAPTIC_CHANNEL = "com.eglobal.wallet/haptics"
    private val CHANNEL = "com.eglobal.wallet/native"
    private val BIOMETRIC_KEY_ALIAS = "eglobal_biometric_auth_key"

    private var activeBiometricPrompt: BiometricPrompt? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
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
                        deleteKeystoreKey()
                        result.success(false)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "deleteBiometricKey" -> {
                    deleteKeystoreKey()
                    result.success(true)
                }
                "authenticateWithCryptoObject" -> {
                    val title = call.argument<String>("title") ?: "Your Fingerprint"
                    val subtitle = call.argument<String>("subtitle") ?: "Scan your enrolled fingerprint or face to verify your identity"
                    val createIfMissing = call.argument<Boolean>("createIfMissing") ?: true
                    authenticateWithCryptoObject(title, subtitle, createIfMissing, result)
                }
                "cancelBiometricPrompt" -> {
                    cancelActiveBiometricPrompt()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HAPTIC_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "vibrate") {
                val type = call.argument<String>("type") ?: "medium"
                try {
                    val vibrator = getSystemService(VIBRATOR_SERVICE) as? android.os.Vibrator
                    if (vibrator == null || !vibrator.hasVibrator()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val effect = when (type) {
                            "keypress", "pin" -> android.os.VibrationEffect.createOneShot(35, android.os.VibrationEffect.DEFAULT_AMPLITUDE)
                            "heavy", "impact" -> android.os.VibrationEffect.createOneShot(70, android.os.VibrationEffect.DEFAULT_AMPLITUDE)
                            else -> android.os.VibrationEffect.createOneShot(50, android.os.VibrationEffect.DEFAULT_AMPLITUDE)
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

    private fun cancelActiveBiometricPrompt() {
        try {
            activeBiometricPrompt?.cancelAuthentication()
            activeBiometricPrompt = null
        } catch (_: Exception) {}
    }

    private fun authenticateWithCryptoObject(
        title: String,
        subtitle: String,
        createIfMissing: Boolean,
        methodResult: MethodChannel.Result
    ) {
        cancelActiveBiometricPrompt()

        val biometricManager = BiometricManager.from(this)
        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.BIOMETRIC_WEAK
        val canAuth = biometricManager.canAuthenticate(authenticators)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            val (errMsg, errCode) = when (canAuth) {
                BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                    Pair("Too many attempts. Please try again later.", "LOCKOUT")
                BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED ->
                    Pair("No biometrics enrolled on this device.", "NONE_ENROLLED")
                else ->
                    Pair("Biometrics not available on device.", "BIOMETRIC_UNAVAILABLE")
            }
            methodResult.success(mapOf("success" to false, "error" to errMsg, "code" to errCode))
            return
        }

        var cipher: Cipher? = null
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            var keyExists = keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)

            if (!keyExists && createIfMissing) {
                createKeystoreKey()
                keyStore.load(null)
                keyExists = keyStore.containsAlias(BIOMETRIC_KEY_ALIAS)
            }

            if (keyExists) {
                val key = keyStore.getKey(BIOMETRIC_KEY_ALIAS, null) as? SecretKey
                if (key != null) {
                    cipher = Cipher.getInstance("${KeyProperties.KEY_ALGORITHM_AES}/${KeyProperties.BLOCK_MODE_CBC}/${KeyProperties.ENCRYPTION_PADDING_PKCS7}")
                    cipher.init(Cipher.ENCRYPT_MODE, key)
                }
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            deleteKeystoreKey()
        } catch (_: Exception) {}

        val executor = ContextCompat.getMainExecutor(this)
        var completed = false

        val prompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                super.onAuthenticationSucceeded(authResult)
                if (completed) return
                completed = true
                activeBiometricPrompt = null
                methodResult.success(mapOf("success" to true))
            }

            override fun onAuthenticationFailed() {
                super.onAuthenticationFailed()
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                super.onAuthenticationError(errorCode, errString)
                if (completed) return
                completed = true
                activeBiometricPrompt = null

                val (codeStr, messageStr) = when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_NEGATIVE_BUTTON -> Pair("USER_CANCELED", errString.toString())
                    BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> Pair("LOCKOUT", "Too many attempts. Please try again later.")
                    BiometricPrompt.ERROR_TIMEOUT -> Pair("TIMEOUT", errString.toString())
                    else -> Pair("ERROR_$errorCode", errString.toString())
                }
                methodResult.success(mapOf("success" to false, "error" to messageStr, "code" to codeStr))
            }
        })

        activeBiometricPrompt = prompt

        val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)

        if (cipher != null) {
            promptInfoBuilder.setNegativeButtonText("Cancel")
            promptInfoBuilder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            prompt.authenticate(promptInfoBuilder.build(), BiometricPrompt.CryptoObject(cipher))
        } else {
            promptInfoBuilder.setNegativeButtonText("Cancel")
            promptInfoBuilder.setAllowedAuthenticators(authenticators)
            prompt.authenticate(promptInfoBuilder.build())
        }
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
