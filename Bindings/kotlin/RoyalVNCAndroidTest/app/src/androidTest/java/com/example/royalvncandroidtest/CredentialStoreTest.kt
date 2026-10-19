package com.example.royalvncandroidtest

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.security.KeyStore
import java.util.Base64
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CredentialStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val prefs = context.getSharedPreferences("vnc_credentials", Context.MODE_PRIVATE)

    @Before fun reset() { prefs.edit().clear().commit() }
    @After fun cleanup() { prefs.edit().clear().commit() }

    @Test fun encryptsWithFreshNonceAndRoundTripsAcrossInstances() {
        val store = CredentialStore(context)
        store.saveCredentials("host", 5900, "üser", "secret🔐")
        val first = prefs.getString("host:5900_encrypted", null)!!
        assertFalse(first.contains("secret"))
        assertEquals("üser" to "secret🔐", CredentialStore(context).loadCredentials("host", 5900))
        store.saveCredentials("host", 5900, "üser", "secret🔐")
        assertNotEquals(first, prefs.getString("host:5900_encrypted", null))
        assertFalse(prefs.contains("host:5900_pass"))
    }

    @Test fun migratesAllLegacyEntriesAndPurgesMalformedEntries() {
        prefs.edit().putString("host:5900_user", b64("user"))
            .putString("host:5900_pass", b64("secret"))
            .putString("broken:5900_user", "bad!").putString("orphan:5900_pass", b64("password")).commit()
        val store = CredentialStore(context)
        assertEquals("user" to "secret", store.loadCredentials("host", 5900))
        assertEquals(setOf("host:5900_encrypted"), prefs.all.keys)
        assertNull(store.loadCredentials("broken", 5900))
    }

    @Test fun rejectsTamperingAndCiphertextCopiedToAnotherServer() {
        val store = CredentialStore(context)
        store.saveCredentials("host", 5900, "user", "secret")
        val record = prefs.getString("host:5900_encrypted", null)!!
        prefs.edit().putString("other:5900_encrypted", record).commit()
        assertNull(store.loadCredentials("other", 5900))
        val data = Base64.getDecoder().decode(record.substring(3))
        data[data.lastIndex] = (data.last().toInt() xor 1).toByte()
        prefs.edit().putString("host:5900_encrypted", "v1:" + Base64.getEncoder().encodeToString(data)).commit()
        assertNull(store.loadCredentials("host", 5900))
        assertTrue(prefs.all.isEmpty())
    }

    @Test fun missingKeystoreKeyDiscardsUnreadableRecordAndAllowsNewSave() {
        val store = CredentialStore(context)
        store.saveCredentials("host", 5900, "user", "secret")
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry("royalvnc.credentials.v1") }
        assertNull(store.loadCredentials("host", 5900))
        store.saveCredentials("host", 5900, "user", "new")
        assertEquals("user" to "new", store.loadCredentials("host", 5900))
    }

    @Test fun migrationPreservesCurrentRecordAndEmptyCredentials() {
        val store = CredentialStore(context)
        store.saveCredentials("host", 5900, "", "")
        prefs.edit().putString("host:5900_user", b64("stale"))
            .putString("host:5900_pass", b64("stale")).commit()
        val migrated = CredentialStore(context)
        assertEquals("" to "", migrated.loadCredentials("host", 5900))
        assertEquals(setOf("host:5900_encrypted"), prefs.all.keys)
        prefs.edit().putString("host:5900_encrypted", "v2:unsupported").commit()
        assertNull(migrated.loadCredentials("host", 5900))
        assertTrue(prefs.all.isEmpty())
    }

    private fun b64(value: String) = Base64.getEncoder().encodeToString(value.toByteArray())
}
