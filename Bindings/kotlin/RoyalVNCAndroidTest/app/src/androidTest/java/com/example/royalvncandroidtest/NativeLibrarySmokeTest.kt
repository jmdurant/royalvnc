package com.example.royalvncandroidtest

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.ServerSocket
import java.net.InetAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import com.royalapps.royalvnc.VncColorDepth
import com.royalapps.royalvnc.VncConnection
import com.royalapps.royalvnc.VncConnectionStatus
import com.royalapps.royalvnc.VncInputMode
import com.royalapps.royalvnc.VncLogLevel
import com.royalapps.royalvnc.VncLogger
import com.royalapps.royalvnc.VncLoggerDelegate
import com.royalapps.royalvnc.VncSettings
import java.lang.ref.WeakReference
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Requires the packaged RoyalVNCKit and Swift runtime libraries for this device ABI. */
@RunWith(AndroidJUnit4::class)
class NativeLibrarySmokeTest {
    @Test fun constructsQueriesAndDestroysNativeObjects() {
        val delegate = object : VncLoggerDelegate {
            override fun log(logger: VncLogger, logLevel: VncLogLevel, message: String) = Unit
        }
        VncLogger(WeakReference(delegate)).use { logger ->
            VncSettings(false, "127.0.0.1", 5900, true, false, false,
                VncInputMode.NONE, false, VncColorDepth.BIT24, null).use { settings ->
                VncConnection(settings, logger).use { connection ->
                    connection.state.use { state ->
                        assertEquals(VncConnectionStatus.DISCONNECTED, state.status)
                        assertFalse(state.isAuthenticationError)
                    }
                }
            }
        }
    }

    @Test fun rejectedSavedCredentialIsDeletedAndReconnectPrompts() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val store = CredentialStore(context)
        val server = ServerSocket(0, 2, InetAddress.getByName("127.0.0.1"))
        val executor = Executors.newSingleThreadExecutor()
        val releaseSecondConnection = CountDownLatch(1)
        val disconnected = CountDownLatch(1)
        val sessions = mutableListOf<VncSession>()
        val worker = executor.submit {
            repeat(2) { attempt ->
                server.accept().use { socket ->
                    socket.soTimeout = 10_000
                    val input = DataInputStream(socket.getInputStream())
                    val output = DataOutputStream(socket.getOutputStream())
                    output.write("RFB 003.008\n".toByteArray(Charsets.US_ASCII))
                    output.flush()
                    val version = ByteArray(12)
                    input.readFully(version)
                    assertEquals("RFB 003.008\n", String(version, Charsets.US_ASCII))
                    output.write(byteArrayOf(1, 2)) // One supported security type: VNC auth.
                    output.flush()
                    assertEquals(2, input.readUnsignedByte())
                    output.write(ByteArray(16) { it.toByte() })
                    output.flush()
                    if (attempt == 0) {
                        input.readFully(ByteArray(16)) // The stored password was actually submitted.
                        val reason = "Wrong password".toByteArray(Charsets.UTF_8)
                        output.writeInt(1)
                        output.writeInt(reason.size)
                        output.write(reason)
                        output.flush()
                    } else {
                        input.readFully(ByteArray(16))
                        assertTrue(releaseSecondConnection.await(10, TimeUnit.SECONDS))
                    }
                }
            }
        }
        try {
            store.saveCredentials("127.0.0.1", server.localPort, "", "wrong")
            assertNotNull(store.loadCredentials("127.0.0.1", server.localPort))
            instrumentation.runOnMainSync {
                sessions += VncSession("127.0.0.1", server.localPort,
                    ConnectionSettings(context), store) { disconnected.countDown() }
                sessions.last().connect()
            }
            assertTrue("Expected typed native authentication failure", disconnected.await(10, TimeUnit.SECONDS))
            assertNull("Rejected saved credential must be deleted", store.loadCredentials("127.0.0.1", server.localPort))
            instrumentation.runOnMainSync {
                sessions += VncSession("127.0.0.1", server.localPort,
                    ConnectionSettings(context), store) {}
                sessions.last().connect()
            }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            var prompting = false
            while (!prompting && System.nanoTime() < deadline) {
                instrumentation.runOnMainSync { prompting = sessions.last().showCredentialPrompt.value }
                if (!prompting) Thread.sleep(50)
            }
            assertTrue("Reconnect must allow password re-entry", prompting)
            instrumentation.runOnMainSync { sessions.last().submitCredentials("", "unverified") }
            assertNull("Submission must not persist before successful authentication",
                store.loadCredentials("127.0.0.1", server.localPort))
            releaseSecondConnection.countDown()
            worker.get(10, TimeUnit.SECONDS)
        } finally {
            instrumentation.runOnMainSync { sessions.forEach { it.close() } }
            store.deleteCredentials("127.0.0.1", server.localPort)
            releaseSecondConnection.countDown()
            server.close()
            executor.shutdownNow()
        }
    }

}
