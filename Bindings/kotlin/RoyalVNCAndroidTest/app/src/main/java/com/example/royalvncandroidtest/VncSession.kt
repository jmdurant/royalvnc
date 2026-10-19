package com.example.royalvncandroidtest

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.royalapps.royalvnc.*
import java.lang.ref.WeakReference

class VncSession(
    private val hostname: String,
    private val port: Int,
    private val settings: ConnectionSettings,
    private val credentialStore: CredentialStore,
    private val onDisconnected: (String?) -> Unit
) : VncLoggerDelegate, VncConnectionDelegate {

    val framebufferImage = mutableStateOf<ImageBitmap?>(null)
    val cursorImage = mutableStateOf<ImageBitmap?>(null)
    val isConnected = mutableStateOf(false)
    val statusText = mutableStateOf("Connecting...")
    val showCredentialPrompt = mutableStateOf(false)
    val framebufferWidth = mutableStateOf(0)
    val framebufferHeight = mutableStateOf(0)
    val cursorX = mutableStateOf(0f)
    val cursorY = mutableStateOf(0f)

    private val logTag = "RVNC"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var logger = VncLogger(WeakReference(this))
    private var vncSettings: VncSettings? = null
    private var connection: VncConnection? = null
    private var pixelBuffer: VncPixelBuffer? = null
    private var pendingAuthRequest: VncAuthenticationRequest? = null
    private var closed = false
    private val credentials = SessionCredentials(
        save = { username, password -> credentialStore.saveCredentials(hostname, port, username, password) },
        delete = { credentialStore.deleteCredentials(hostname, port) }
    )

    fun connect() {
        check(!closed) { "Session is closed" }
        credentials.load(credentialStore.loadCredentials(hostname, port))

        val encodings = settings.frameEncodings.toTypedArray()

        val vncSettings = VncSettings(
            false,
            hostname,
            port.toShort(),
            settings.isShared,
            settings.isScalingEnabled,
            false,
            VncInputMode.NONE,
            settings.isClipboardRedirectionEnabled,
            settings.colorDepth,
            if (encodings.isNotEmpty()) encodings else null
        )

        this.vncSettings = vncSettings

        val connection = VncConnection(vncSettings, logger)
        this.connection = connection

        connection.setDelegate(WeakReference(this))
        connection.connect()
    }

    fun disconnect() {
        cancelAuthentication()
        connection?.disconnect()
    }

    fun submitCredentials(username: String, password: String) {
        val request = pendingAuthRequest ?: return
        pendingAuthRequest = null
        showCredentialPrompt.value = false
        credentials.submit(username, password)
        if (request.requiresUsername) {
            request.completeWithUsernameAndPassword(username, password)
        } else {
            request.completeWithPassword(password)
        }
    }

    fun cancelAuthentication() {
        val request = pendingAuthRequest
        pendingAuthRequest = null
        request?.cancel()
        credentials.clear()
        showCredentialPrompt.value = false
    }

    fun mouseMove(x: Short, y: Short) {
        cursorX.value = x.toFloat()
        cursorY.value = y.toFloat()
        connection?.mouseMove(x, y)
    }

    fun mouseDown(button: VncMouseButton, x: Short, y: Short) {
        connection?.mouseDown(button, x, y)
    }

    fun mouseUp(button: VncMouseButton, x: Short, y: Short) {
        connection?.mouseUp(button, x, y)
    }

    fun click(button: VncMouseButton, x: Short, y: Short) {
        mouseMove(x, y)
        mouseDown(button, x, y)
        mouseUp(button, x, y)
    }

    fun keyDown(key: Int) {
        connection?.keyDown(key)
    }

    fun keyUp(key: Int) {
        connection?.keyUp(key)
    }

    fun sendKey(key: Int) {
        connection?.keyDown(key)
        connection?.keyUp(key)
    }

    fun close() {
        if (closed) return
        closed = true
        cancelAuthentication()
        connection?.setDelegate(null)
        connection?.close()
        connection = null
        vncSettings?.close()
        vncSettings = null
        logger.close()
    }

    // VncLoggerDelegate
    override fun log(logger: VncLogger, logLevel: VncLogLevel, message: String) {
        when (logLevel) {
            VncLogLevel.INFO -> Log.i(logTag, message)
            VncLogLevel.WARNING -> Log.w(logTag, message)
            VncLogLevel.ERROR -> Log.e(logTag, message)
            VncLogLevel.DEBUG -> Log.d(logTag, message)
        }
    }

    // VncConnectionDelegate
    override fun connectionStateDidChange(
        connection: VncConnection,
        connectionState: VncConnectionState
    ) {
        val status = connectionState.status
        val errorDescription = connectionState.errorDescription
        val shouldDisplay = connectionState.shouldDisplayToUser
        val authenticationError = connectionState.isAuthenticationError

        mainHandler.post {
            if (closed || this.connection !== connection) return@post
            when (status) {
                VncConnectionStatus.CONNECTING -> {
                    isConnected.value = true
                    statusText.value = "Connecting..."
                }
                VncConnectionStatus.CONNECTED -> {
                    credentials.connected()
                    isConnected.value = true
                    statusText.value = "Connected"
                }
                VncConnectionStatus.DISCONNECTING -> {
                    statusText.value = "Disconnecting..."
                }
                VncConnectionStatus.DISCONNECTED -> {
                    if (authenticationError) credentials.rejected()
                    cancelAuthentication()
                    isConnected.value = false
                    framebufferImage.value = null
                    cursorImage.value = null

                    this.connection?.close()
                    this.connection = null
                    vncSettings?.close()
                    vncSettings = null

                    onDisconnected(if (shouldDisplay) errorDescription else null)
                }
            }
        }
    }

    override fun authenticate(
        connection: VncConnection,
        authenticationRequest: VncAuthenticationRequest
    ) {
        mainHandler.post {
            if (closed || this.connection !== connection) {
                authenticationRequest.cancel()
                return@post
            }
            credentials.takeSaved()?.let { (username, password) ->
                if (authenticationRequest.requiresUsername) {
                    authenticationRequest.completeWithUsernameAndPassword(username, password)
                } else {
                    authenticationRequest.completeWithPassword(password)
                }
                return@post
            }
            // A repeated challenge must allow correction rather than replaying a rejected pair.
            credentials.rejected()
            pendingAuthRequest?.cancel()
            pendingAuthRequest = authenticationRequest
            showCredentialPrompt.value = true
        }
    }

    override fun didCreateFramebuffer(
        connection: VncConnection,
        framebuffer: VncFramebuffer
    ) {
        pixelBuffer = VncPixelBuffer(framebuffer)
        val w = framebuffer.width.toInt()
        val h = framebuffer.height.toInt()
        mainHandler.post {
            framebufferWidth.value = w
            framebufferHeight.value = h
            cursorX.value = w / 2f
            cursorY.value = h / 2f
        }
    }

    override fun didResizeFramebuffer(
        connection: VncConnection,
        framebuffer: VncFramebuffer
    ) {
        pixelBuffer = VncPixelBuffer(framebuffer)
        val w = framebuffer.width.toInt()
        val h = framebuffer.height.toInt()
        mainHandler.post {
            framebufferWidth.value = w
            framebufferHeight.value = h
        }
    }

    override fun didUpdateFramebuffer(
        connection: VncConnection,
        framebuffer: VncFramebuffer,
        x: Short,
        y: Short,
        width: Short,
        height: Short
    ) {
        pixelBuffer?.let {
            val bitmap = it.getBitmap(framebuffer)
            val imageBitmap = bitmap.asImageBitmap()
            mainHandler.post {
                framebufferImage.value = imageBitmap
            }
        }
    }

    override fun didUpdateCursor(
        connection: VncConnection,
        cursor: VncCursor
    ) {
        if (cursor.empty) {
            mainHandler.post {
                cursorImage.value = null
            }
        } else {
            val bitmap = cursor.getBitmap()
            val imageBitmap = bitmap.asImageBitmap()
            mainHandler.post {
                cursorImage.value = imageBitmap
            }
        }
    }
}
