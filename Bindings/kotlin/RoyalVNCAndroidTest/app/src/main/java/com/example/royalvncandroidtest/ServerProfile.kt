package com.example.royalvncandroidtest

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class ServerProfile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val hostname: String,
    val port: Int = 5900
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("name", name)
        put("hostname", hostname)
        put("port", port)
    }

    companion object {
        fun fromJson(json: JSONObject): ServerProfile = ServerProfile(
            id = json.getString("id"),
            name = json.getString("name"),
            hostname = json.getString("hostname"),
            port = json.optInt("port", 5900)
        )
    }
}

class ProfileStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("server_profiles", Context.MODE_PRIVATE)

    fun loadProfiles(): List<ServerProfile> {
        val json = prefs.getString("profiles", null) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { ServerProfile.fromJson(array.getJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveProfiles(profiles: List<ServerProfile>) {
        val array = JSONArray()
        profiles.forEach { array.put(it.toJson()) }
        prefs.edit().putString("profiles", array.toString()).apply()
    }

    fun addProfile(profile: ServerProfile) {
        val profiles = loadProfiles().toMutableList()
        profiles.add(profile)
        saveProfiles(profiles)
    }

    fun removeProfile(id: String) {
        saveProfiles(loadProfiles().filter { it.id != id })
    }
}
