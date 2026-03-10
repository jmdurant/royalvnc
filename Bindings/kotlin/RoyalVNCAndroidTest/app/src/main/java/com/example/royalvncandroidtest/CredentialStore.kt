package com.example.royalvncandroidtest

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64

class CredentialStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("vnc_credentials", Context.MODE_PRIVATE)

    fun saveCredentials(hostname: String, port: Int, username: String, password: String) {
        val key = "${hostname}:${port}"
        prefs.edit()
            .putString("${key}_user", Base64.encodeToString(username.toByteArray(), Base64.NO_WRAP))
            .putString("${key}_pass", Base64.encodeToString(password.toByteArray(), Base64.NO_WRAP))
            .apply()
    }

    fun loadCredentials(hostname: String, port: Int): Pair<String, String>? {
        val key = "${hostname}:${port}"
        val userB64 = prefs.getString("${key}_user", null) ?: return null
        val passB64 = prefs.getString("${key}_pass", null) ?: return null
        return try {
            Pair(
                String(Base64.decode(userB64, Base64.NO_WRAP)),
                String(Base64.decode(passB64, Base64.NO_WRAP))
            )
        } catch (_: Exception) {
            null
        }
    }

    fun deleteCredentials(hostname: String, port: Int) {
        val key = "${hostname}:${port}"
        prefs.edit()
            .remove("${key}_user")
            .remove("${key}_pass")
            .apply()
    }
}
