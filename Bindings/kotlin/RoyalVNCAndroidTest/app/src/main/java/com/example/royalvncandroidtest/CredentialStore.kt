package com.example.royalvncandroidtest

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.nio.ByteBuffer
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Credentials never leave this store without authenticated, device-bound encryption at rest. */
class CredentialStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("vnc_credentials", Context.MODE_PRIVATE)

    init {
        migrateLegacyCredentials()
    }

    @Synchronized
    fun saveCredentials(hostname: String, port: Int, username: String, password: String) {
        val endpoint = "$hostname:$port"
        try {
            val encrypted = encrypt(endpoint, username, password)
            prefs.edit().putString("${endpoint}_encrypted", encrypted)
                .remove("${endpoint}_user").remove("${endpoint}_pass").commit()
        } catch (_: Exception) {
            // An unavailable/invalidated key must never cause plaintext fallback.
            deleteCredentials(hostname, port)
        }
    }

    @Synchronized
    fun loadCredentials(hostname: String, port: Int): Pair<String, String>? {
        val endpoint = "$hostname:$port"
        return try {
            prefs.getString("${endpoint}_encrypted", null)?.let { decrypt(endpoint, it) }
        } catch (_: Exception) {
            // Corrupt records and records restored without their key require re-entry.
            deleteCredentials(hostname, port)
            null
        }
    }

    @Synchronized
    fun deleteCredentials(hostname: String, port: Int) {
        val endpoint = "$hostname:$port"
        prefs.edit().remove("${endpoint}_encrypted")
            .remove("${endpoint}_user").remove("${endpoint}_pass").commit()
    }

    private fun migrateLegacyCredentials() {
        val entries = prefs.all
        val endpoints = entries.keys.filter { it.endsWith("_user") || it.endsWith("_pass") }
            .map { it.substringBeforeLast('_') }.toSet()
        if (endpoints.isEmpty()) return
        val editor = prefs.edit()
        for (endpoint in endpoints) {
            try {
                // Never replace a current record with a stale legacy copy.
                if (!entries.containsKey("${endpoint}_encrypted")) {
                    val username = String(Base64.getDecoder().decode(entries["${endpoint}_user"] as String), Charsets.UTF_8)
                    val password = String(Base64.getDecoder().decode(entries["${endpoint}_pass"] as String), Charsets.UTF_8)
                    editor.putString("${endpoint}_encrypted", encrypt(endpoint, username, password))
                }
            } catch (_: Exception) {
                // Malformed/incomplete legacy data or key failures require fresh credentials.
            }
            editor.remove("${endpoint}_user").remove("${endpoint}_pass")
        }
        editor.commit()
    }

    private fun key(): SecretKey = synchronized(KEY_ALIAS) {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey) ?: KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        ).apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
        }.generateKey()
    }

    private fun encrypt(endpoint: String, username: String, password: String): String {
        val user = username.toByteArray(Charsets.UTF_8)
        val pass = password.toByteArray(Charsets.UTF_8)
        val plaintext = ByteBuffer.allocate(4 + user.size + pass.size)
            .putInt(user.size).put(user).put(pass).array()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(endpoint.toByteArray(Charsets.UTF_8))
        return "v1:" + Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(plaintext))
    }

    private fun decrypt(endpoint: String, record: String): Pair<String, String> {
        require(record.startsWith("v1:"))
        val bytes = Base64.getDecoder().decode(record.substring(3))
        require(bytes.size >= 12 + 16 + 4)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(endpoint.toByteArray(Charsets.UTF_8))
        val plaintext = ByteBuffer.wrap(cipher.doFinal(bytes, 12, bytes.size - 12))
        val userLength = plaintext.int
        require(userLength >= 0 && userLength <= plaintext.remaining())
        val user = ByteArray(userLength).also { plaintext.get(it) }
        val pass = ByteArray(plaintext.remaining()).also { plaintext.get(it) }
        return String(user, Charsets.UTF_8) to String(pass, Charsets.UTF_8)
    }

    private companion object {
        const val KEY_ALIAS = "royalvnc.credentials.v1"
    }
}
