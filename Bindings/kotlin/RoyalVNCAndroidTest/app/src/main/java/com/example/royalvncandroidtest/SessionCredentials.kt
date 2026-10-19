package com.example.royalvncandroidtest

/** Single-attempt credentials: persist only after CONNECTED, discard after rejection or teardown. */
internal class SessionCredentials(
    private val save: (String, String) -> Unit,
    private val delete: () -> Unit
) {
    private var saved: Pair<String, String>? = null
    private var submitted: Pair<String, String>? = null
    private var attempted = false

    fun load(credentials: Pair<String, String>?) {
        clear()
        saved = credentials
    }

    fun takeSaved(): Pair<String, String>? = saved.also {
        saved = null
        if (it != null) attempted = true
    }

    fun submit(username: String, password: String) {
        submitted = username to password
        attempted = true
    }

    fun connected() {
        submitted?.let { (username, password) -> save(username, password) }
        clear()
    }

    fun rejected() {
        if (attempted) delete()
        clear()
    }

    fun clear() {
        saved = null
        submitted = null
        attempted = false
    }
}
