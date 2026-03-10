package com.example.royalvncandroidtest

import android.content.Context
import android.content.SharedPreferences
import com.royalapps.royalvnc.VncColorDepth
import com.royalapps.royalvnc.VncFrameEncodingType

class ConnectionSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("vnc_settings", Context.MODE_PRIVATE)

    var colorDepth: VncColorDepth
        get() = when (prefs.getInt("color_depth", 24)) {
            8 -> VncColorDepth.BIT8
            16 -> VncColorDepth.BIT16
            else -> VncColorDepth.BIT24
        }
        set(value) {
            prefs.edit().putInt("color_depth", value.rawValue).apply()
        }

    var isShared: Boolean
        get() = prefs.getBoolean("is_shared", true)
        set(value) {
            prefs.edit().putBoolean("is_shared", value).apply()
        }

    var isScalingEnabled: Boolean
        get() = prefs.getBoolean("is_scaling", true)
        set(value) {
            prefs.edit().putBoolean("is_scaling", value).apply()
        }

    var isClipboardRedirectionEnabled: Boolean
        get() = prefs.getBoolean("clipboard", false)
        set(value) {
            prefs.edit().putBoolean("clipboard", value).apply()
        }

    var cursorSpeed: Int
        get() = prefs.getInt("cursor_speed", DEFAULT_CURSOR_SPEED)
        set(value) {
            prefs.edit().putInt("cursor_speed", value.coerceIn(2, 40)).apply()
        }

    var frameEncodings: List<VncFrameEncodingType>
        get() {
            val stored = prefs.getString("encodings", null) ?: return DEFAULT_ENCODINGS
            return stored.split(",").mapNotNull { name ->
                try {
                    VncFrameEncodingType.valueOf(name)
                } catch (_: Exception) {
                    null
                }
            }.ifEmpty { DEFAULT_ENCODINGS }
        }
        set(value) {
            prefs.edit().putString("encodings", value.joinToString(",") { it.name }).apply()
        }

    fun resetToDefaults() {
        prefs.edit().clear().apply()
    }

    companion object {
        const val DEFAULT_CURSOR_SPEED = 10

        val ALL_ENCODINGS = listOf(
            VncFrameEncodingType.TIGHT,
            VncFrameEncodingType.ZLIB,
            VncFrameEncodingType.ZRLE,
            VncFrameEncodingType.HEXTILE,
            VncFrameEncodingType.CORRE,
            VncFrameEncodingType.RRE
        )

        val DEFAULT_ENCODINGS = listOf(
            VncFrameEncodingType.TIGHT,
            VncFrameEncodingType.ZLIB,
            VncFrameEncodingType.ZRLE,
            VncFrameEncodingType.HEXTILE,
            VncFrameEncodingType.CORRE,
            VncFrameEncodingType.RRE
        )
    }
}
