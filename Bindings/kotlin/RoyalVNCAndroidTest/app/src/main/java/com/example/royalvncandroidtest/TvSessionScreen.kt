package com.example.royalvncandroidtest

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.royalapps.royalvnc.VncMouseButton
import com.royalapps.royalvnc.X11KeySymbol

@Composable
fun TvSessionScreen(
    session: VncSession,
    settings: ConnectionSettings,
    onDisconnected: () -> Unit
) {
    val framebuffer by session.framebufferImage
    val cursor by session.cursorImage
    val isConnected by session.isConnected
    val statusText by session.statusText
    val fbWidth by session.framebufferWidth
    val fbHeight by session.framebufferHeight
    val showCredentialPrompt by session.showCredentialPrompt
    val cursorX by session.cursorX
    val cursorY by session.cursorY

    var showActions by remember { mutableStateOf(false) }
    var viewSize by remember { mutableStateOf(IntSize.Zero) }
    val focusRequester = remember { FocusRequester() }
    val cursorSpeed = settings.cursorSpeed

    // Calculate display metrics
    val displayScale = if (fbWidth > 0 && viewSize.width > 0) {
        viewSize.width.toFloat() / fbWidth.toFloat()
    } else 1f

    val displayHeight = fbHeight * displayScale
    val verticalOffset = if (viewSize.height > displayHeight) {
        (viewSize.height - displayHeight) / 2f
    } else 0f

    // Request focus on the main box for key events
    LaunchedEffect(framebuffer) {
        if (framebuffer != null) {
            try {
                focusRequester.requestFocus()
            } catch (_: Exception) {}
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onSizeChanged { viewSize = it }
            .focusRequester(focusRequester)
            .focusable()
            .onPreviewKeyEvent { keyEvent ->
                if (showActions) return@onPreviewKeyEvent false

                if (keyEvent.type == KeyEventType.KeyDown) {
                    handleTvKeyDown(keyEvent, session, cursorSpeed, fbWidth, fbHeight, cursorX, cursorY) {
                        showActions = true
                    }
                } else {
                    false
                }
            }
    ) {
        if (framebuffer != null && fbWidth > 0) {
            // Framebuffer display
            Image(
                bitmap = framebuffer!!,
                contentDescription = "Remote Screen",
                contentScale = ContentScale.Fit,
                alignment = Alignment.Center,
                modifier = Modifier.fillMaxSize()
            )

            // Cursor overlay
            cursor?.let { cursorBitmap ->
                Image(
                    bitmap = cursorBitmap,
                    contentDescription = "Cursor",
                    modifier = Modifier.offset {
                        IntOffset(
                            (cursorX * displayScale).toInt(),
                            (verticalOffset + cursorY * displayScale).toInt()
                        )
                    }
                )
            }

            // Controls hint at bottom
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 24.dp)
            ) {
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = Color.Black.copy(alpha = 0.6f)
                ) {
                    Text(
                        "D-Pad: Move  |  Select: Click  |  Back: Menu",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 14.sp,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                    )
                }
            }
        } else {
            // Loading state
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                CircularProgressIndicator(color = Color.White)
                Spacer(Modifier.height(16.dp))
                Text(statusText, color = Color.White)
            }
        }
    }

    // Credential prompt dialog
    if (showCredentialPrompt) {
        var username by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { session.cancelAuthentication() },
            title = { Text("Authentication Required") },
            text = {
                Column {
                    OutlinedTextField(
                        value = username,
                        onValueChange = { username = it },
                        label = { Text("Username") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Password") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { session.submitCredentials(username, password) }) {
                    Text("Login")
                }
            },
            dismissButton = {
                TextButton(onClick = { session.cancelAuthentication() }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Actions menu
    if (showActions) {
        AlertDialog(
            onDismissRequest = {
                showActions = false
                try { focusRequester.requestFocus() } catch (_: Exception) {}
            },
            title = { Text("Actions") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TvActionButton("Right Click") {
                        session.click(
                            VncMouseButton.RIGHT,
                            cursorX.toInt().toShort(),
                            cursorY.toInt().toShort()
                        )
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Double Click") {
                        val cx = cursorX.toInt().toShort()
                        val cy = cursorY.toInt().toShort()
                        session.click(VncMouseButton.LEFT, cx, cy)
                        session.click(VncMouseButton.LEFT, cx, cy)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    TvActionButton("Escape") {
                        session.sendKey(X11KeySymbol.XK_Escape)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Return") {
                        session.sendKey(X11KeySymbol.XK_Return)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Tab") {
                        session.sendKey(X11KeySymbol.XK_Tab)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Backspace") {
                        session.sendKey(X11KeySymbol.XK_BackSpace)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Delete") {
                        session.sendKey(X11KeySymbol.XK_Delete)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Space") {
                        session.sendKey(X11KeySymbol.XK_space)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    TvActionButton("Ctrl+Alt+Del") {
                        session.keyDown(X11KeySymbol.XK_Control_L)
                        session.keyDown(X11KeySymbol.XK_Alt_L)
                        session.sendKey(X11KeySymbol.XK_Delete)
                        session.keyUp(X11KeySymbol.XK_Alt_L)
                        session.keyUp(X11KeySymbol.XK_Control_L)
                        showActions = false
                        try { focusRequester.requestFocus() } catch (_: Exception) {}
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    TvActionButton("Disconnect", isDestructive = true) {
                        session.disconnect()
                        showActions = false
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    showActions = false
                    try { focusRequester.requestFocus() } catch (_: Exception) {}
                }) {
                    Text("Close")
                }
            }
        )
    }

    // Handle disconnection
    LaunchedEffect(isConnected) {
        if (!isConnected && framebuffer == null && statusText != "Connecting...") {
            onDisconnected()
        }
    }
}

private fun handleTvKeyDown(
    keyEvent: KeyEvent,
    session: VncSession,
    cursorSpeed: Int,
    fbWidth: Int,
    fbHeight: Int,
    cursorX: Float,
    cursorY: Float,
    onShowActions: () -> Unit
): Boolean {
    return when (keyEvent.key) {
        Key.DirectionUp -> {
            val newY = (cursorY - cursorSpeed).coerceAtLeast(0f)
            session.mouseMove(cursorX.toInt().toShort(), newY.toInt().toShort())
            true
        }
        Key.DirectionDown -> {
            val newY = (cursorY + cursorSpeed).coerceAtMost((fbHeight - 1).toFloat())
            session.mouseMove(cursorX.toInt().toShort(), newY.toInt().toShort())
            true
        }
        Key.DirectionLeft -> {
            val newX = (cursorX - cursorSpeed).coerceAtLeast(0f)
            session.mouseMove(newX.toInt().toShort(), cursorY.toInt().toShort())
            true
        }
        Key.DirectionRight -> {
            val newX = (cursorX + cursorSpeed).coerceAtMost((fbWidth - 1).toFloat())
            session.mouseMove(newX.toInt().toShort(), cursorY.toInt().toShort())
            true
        }
        Key.DirectionCenter, Key.Enter -> {
            session.click(VncMouseButton.LEFT, cursorX.toInt().toShort(), cursorY.toInt().toShort())
            true
        }
        Key.Back, Key.Menu -> {
            onShowActions()
            true
        }
        // Game controller buttons
        Key.ButtonA -> {
            session.click(VncMouseButton.LEFT, cursorX.toInt().toShort(), cursorY.toInt().toShort())
            true
        }
        Key.ButtonB -> {
            session.click(VncMouseButton.RIGHT, cursorX.toInt().toShort(), cursorY.toInt().toShort())
            true
        }
        Key.ButtonX -> {
            session.sendKey(X11KeySymbol.XK_Escape)
            true
        }
        Key.ButtonY -> {
            onShowActions()
            true
        }
        else -> false
    }
}

@Composable
private fun TvActionButton(
    label: String,
    isDestructive: Boolean = false,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = if (isDestructive) {
            ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
        } else {
            ButtonDefaults.buttonColors()
        }
    ) {
        Text(label)
    }
}
