package com.example.royalvncandroidtest

import org.junit.Assert.*
import org.junit.Test

class SessionCredentialsTest {
    private val saved = mutableListOf<Pair<String, String>>()
    private var deletions = 0
    private val credentials = SessionCredentials({ user, pass -> saved.add(user to pass) }, { deletions++ })

    @Test fun savesOnlyAfterSuccess() {
        credentials.submit("user", "password")
        assertTrue(saved.isEmpty())
        credentials.connected()
        assertEquals(listOf("user" to "password"), saved)
        credentials.connected()
        assertEquals(1, saved.size)
    }

    @Test fun rejectedSavedPasswordIsNotRetriedAndReplacementCanSucceed() {
        credentials.load("user" to "wrong")
        assertEquals("user" to "wrong", credentials.takeSaved())
        assertNull(credentials.takeSaved())
        credentials.rejected()
        assertEquals(1, deletions)
        credentials.submit("user", "correct")
        credentials.connected()
        assertEquals(listOf("user" to "correct"), saved)
    }

    @Test fun rejectionDoesNotPersistSubmittedPassword() {
        credentials.submit("user", "wrong")
        credentials.rejected()
        credentials.connected()
        assertTrue(saved.isEmpty())
        assertEquals(1, deletions)
    }

    @Test fun transportFailureOrCancellationKeepsStoredPasswordAndDiscardsPendingSave() {
        credentials.load("user" to "stored")
        credentials.takeSaved()
        credentials.submit("user", "pending")
        credentials.clear()
        credentials.connected()
        assertEquals(0, deletions)
        assertTrue(saved.isEmpty())
        assertNull(credentials.takeSaved())
    }

    @Test fun emptyCredentialsStillGetOneAttempt() {
        credentials.load("" to "")
        assertEquals("" to "", credentials.takeSaved())
        assertNull(credentials.takeSaved())
        credentials.rejected()
        assertEquals(1, deletions)
    }
}
