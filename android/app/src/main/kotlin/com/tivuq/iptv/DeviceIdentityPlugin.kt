package com.tivuq.iptv

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.KeyPairGeneratorSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.provider.Settings
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Calendar
import javax.security.auth.x500.X500Principal

class DeviceIdentityPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "com.tivuq.iptv/device_identity"
        private const val KEY_ALIAS = "tivuq_device_identity_v1"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getIdentity" -> result.success(identity())
                "signChallenge" -> {
                    val nonce = call.argument<String>("nonce")
                        ?: return result.error("MISSING_NONCE", "Nonce is required", null)
                    result.success(signChallenge(nonce))
                }
                "verifyServerToken" -> {
                    val token = call.argument<String>("token")
                        ?: return result.error("MISSING_TOKEN", "Token is required", null)
                    val publicKey = call.argument<String>("publicKey")
                        ?: return result.error("MISSING_PUBLIC_KEY", "Public key is required", null)
                    result.success(verifyServerToken(token, publicKey))
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("DEVICE_IDENTITY_ERROR", error.message, error.javaClass.simpleName)
        }
    }

    private fun identity(): Map<String, Any> {
        val keyPair = getOrCreateKeyPair()
        val publicKey = keyPair.certificate.publicKey.encoded
        val binding = deviceBinding()
        val hex = binding.take(12).uppercase()
        val deviceCode = "${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}"
        return mapOf(
            "deviceCode" to deviceCode,
            "publicKey" to encode(publicKey),
            "algorithm" to "RSA-SHA256",
            "platform" to "android_tv",
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            "hardwareBacked" to isHardwareBacked(),
            "signingCertificateSha256" to signingCertificateSha256(),
            "deviceBinding" to binding,
        )
    }

    private fun deviceBinding(): String {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID,
        ) ?: throw IllegalStateException("Android device binding is unavailable")
        return MessageDigest.getInstance("SHA-256")
            .digest("$androidId:${signingCertificateSha256()}".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    private fun signingCertificateSha256(): String {
        @Suppress("DEPRECATION")
        val certificates = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            ).signingInfo?.apkContentsSigners
        } else {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNATURES,
            ).signatures
        }
        val certificate = certificates?.firstOrNull()
            ?: throw IllegalStateException("Application signing certificate is missing")
        return MessageDigest.getInstance("SHA-256")
            .digest(certificate.toByteArray())
            .joinToString("") { "%02X".format(it) }
    }

    private fun signChallenge(nonce: String): String {
        val key = getOrCreateKeyPair().privateKey
        val signer = Signature.getInstance("SHA256withRSA")
        signer.initSign(key)
        signer.update(decode(nonce))
        return encode(signer.sign())
    }

    private fun verifyServerToken(token: String, publicKeyText: String): Boolean {
        val parts = token.split('.')
        if (parts.size != 3) return false
        val publicKey = KeyFactory.getInstance("RSA").generatePublic(
            X509EncodedKeySpec(decode(publicKeyText)),
        )
        val verifier = Signature.getInstance("SHA256withRSA")
        verifier.initVerify(publicKey)
        verifier.update("${parts[0]}.${parts[1]}".toByteArray(Charsets.UTF_8))
        return verifier.verify(decode(parts[2]))
    }

    private fun getOrCreateKeyPair(): KeyStore.PrivateKeyEntry {
        val store = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (store.getEntry(KEY_ALIAS, null) as? KeyStore.PrivateKeyEntry)?.let { return it }

        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEYSTORE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            generator.initialize(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                    .setUserAuthenticationRequired(false)
                    .build(),
            )
        } else {
            @Suppress("DEPRECATION")
            val start = Calendar.getInstance()
            val end = Calendar.getInstance().apply { add(Calendar.YEAR, 30) }
            @Suppress("DEPRECATION")
            generator.initialize(
                KeyPairGeneratorSpec.Builder(context)
                    .setAlias(KEY_ALIAS)
                    .setSubject(X500Principal("CN=TIVUQIPTV Device Identity"))
                    .setSerialNumber(BigInteger.ONE)
                    .setStartDate(start.time)
                    .setEndDate(end.time)
                    .build(),
            )
        }
        generator.generateKeyPair()
        store.load(null)
        return store.getEntry(KEY_ALIAS, null) as KeyStore.PrivateKeyEntry
    }

    private fun isHardwareBacked(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return runCatching {
            val key = getOrCreateKeyPair().privateKey
            val factory = KeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
            val keyInfo = factory.getKeySpec(
                key,
                android.security.keystore.KeyInfo::class.java,
            )
            @Suppress("DEPRECATION")
            keyInfo.isInsideSecureHardware
        }.getOrDefault(false)
    }

    private fun encode(value: ByteArray): String = Base64.encodeToString(
        value,
        Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
    )

    private fun decode(value: String): ByteArray {
        val standard = value.replace('-', '+').replace('_', '/')
        val padded = standard + "=".repeat((4 - standard.length % 4) % 4)
        return Base64.decode(padded, Base64.DEFAULT)
    }
}
