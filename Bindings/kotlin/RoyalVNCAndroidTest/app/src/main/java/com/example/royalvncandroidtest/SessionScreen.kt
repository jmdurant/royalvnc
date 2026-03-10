package com.example.royalvncandroidtest

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.royalapps.royalvnc.VncMouseButton
import com.royalapps.royalvnc.X11KeySymbol
import kotlin.math.max

enum class InputMode(val label: String) {
    DIRECT("Direct Touch"),
    TRACKPAD("Trackpad")
}

@Composable
fun SessionScreen(
    session: VncSession,
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

    var inputMode by remember { mutableStateOf(InputMode.DIRECT) }
    var showToolbar by remember { mutableStateOf(true) }
    var showActions by remember { mutableStateOf(false) }
    var showKeyboard by remember { mutableStateOf(false) }
    var zoom by remember { mutableFloatStateOf(1f) }
    var panOffset by remember { mutableStateOf(Offset.Zero) }
    var viewSize by remember { mutableStateOf(IntSize.Zero) }
    var tapCount by remember { mutableIntStateOf(0) }
    var lastTapTime by remember { mutableLongStateOf(0L) }

    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    val keyboardFocusRequester = remember { FocusRequester() }

    // Calculate display metrics
    val displayScale = if (fbWidth > 0 && viewSize.width > 0) {
        viewSize.width.toFloat() / fbWidth.toFloat()
    } else 1f

    val displayHeight = fbHeight * displayScale
    val verticalOffset = if (viewSize.height > displayHeight) {
        (viewSize.height - displayHeight) / 2f
    } else 0f

    fun screenToFramebuffer(screenX: Float, screenY: Float): Pair<Short, Short> {
        val adjustedX = (screenX - panOffset.x) / zoom
        val adjustedY = (screenY - verticalOffset - panOffset.y) / zoom
        val fbX = (adjustedX / displayScale).toInt().coerceIn(0, max(fbWidth - 1, 0))
        val fbY = (adjustedY / displayScale).toInt().coerceIn(0, max(fbHeight - 1, 0))
        return Pair(fbX.toShort(), fbY.toShort())
    }

    fun handleTripleTap() {
        val now = System.currentTimeMillis()
        if (now - lastTapTime < 400) {
            tapCount++
            if (tapCount >= 3) {
                showToolbar = !showToolbar
                tapCount = 0
            }
        } else {
            tapCount = 1
        }
        lastTapTime = now
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onSizeChanged { viewSize = it }
    ) {
        if (framebuffer != null && fbWidth > 0) {
            // Framebuffer with zoom/pan
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer(
                        scaleX = zoom,
                        scaleY = zoom,
                        translationX = panOffset.x * zoom,
                        translationY = panOffset.y * zoom
                    )
            ) {
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
            }

            // Touch input layer
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(inputMode) {
                        detectTapGestures(
                            onTap = { offset ->
                                handleTripleTap()
                                if (inputMode == InputMode.DIRECT) {
                                    val (x, y) = screenToFramebuffer(offset.x, offset.y)
                                    session.click(VncMouseButton.LEFT, x, y)
                                } else {
                                    session.click(
                                        VncMouseButton.LEFT,
                                        cursorX.toInt().toShort(),
                                        cursorY.toInt().toShort()
                                    )
                                }
                            },
                            onLongPress = { offset ->
                                if (inputMode == InputMode.DIRECT) {
                                    val (x, y) = screenToFramebuffer(offset.x, offset.y)
                                    session.click(VncMouseButton.RIGHT, x, y)
                                } else {
                                    session.click(
                                        VncMouseButton.RIGHT,
                                        cursorX.toInt().toShort(),
                                        cursorY.toInt().toShort()
                                    )
                                }
                            },
                            onDoubleTap = { offset ->
                                if (inputMode == InputMode.DIRECT) {
                                    if (zoom > 1f) {
                                        zoom = 1f
                                        panOffset = Offset.Zero
                                    } else {
                                        zoom = 2f
                                    }
                                } else {
                                    val cx = cursorX.toInt().toShort()
                                    val cy = cursorY.toInt().toShort()
                                    session.click(VncMouseButton.LEFT, cx, cy)
                                    session.click(VncMouseButton.LEFT, cx, cy)
                                }
                            }
                        )
                    }
                    .pointerInput(inputMode, zoom) {
                        detectDragGestures { _, dragAmount ->
                            if (inputMode == InputMode.DIRECT) {
                                if (zoom > 1f) {
                                    panOffset = Offset(
                                        panOffset.x + dragAmount.x / zoom,
                                        panOffset.y + dragAmount.y / zoom
                                    )
                                } else {
                                    // In direct mode at 1x zoom, drag moves mouse
                                    val newX = (cursorX + dragAmount.x / displayScale)
                                        .coerceIn(0f, fbWidth.toFloat() - 1f)
                                    val newY = (cursorY + dragAmount.y / displayScale)
                                        .coerceIn(0f, fbHeight.toFloat() - 1f)
                                    session.mouseMove(newX.toInt().toShort(), newY.toInt().toShort())
                                }
                            } else {
                                // Trackpad mode: relative cursor movement
                                val sensitivity = 1.5f
                                val newX = (cursorX + dragAmount.x * sensitivity / displayScale)
                                    .coerceIn(0f, fbWidth.toFloat() - 1f)
                                val newY = (cursorY + dragAmount.y * sensitivity / displayScale)
                                    .coerceIn(0f, fbHeight.toFloat() - 1f)
                                session.mouseMove(newX.toInt().toShort(), newY.toInt().toShort())
                            }
                        }
                    }
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, gestureZoom, _ ->
                            zoom = (zoom * gestureZoom).coerceIn(1f, 5f)
                            if (zoom > 1f) {
                                panOffset = Offset(
                                    panOffset.x + pan.x / zoom,
                                    panOffset.y + pan.y / zoom
                                )
                            } else {
                                panOffset = Offset.Zero
                            }
                        }
                    }
            )
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

        // Input mode indicator
        if (framebuffer != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = if (showToolbar) 72.dp else 16.dp)
            ) {
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = Color.Black.copy(alpha = 0.6f)
                ) {
                    Text(
                        inputMode.label,
                        color = Color.White,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
                    )
                }
            }
        }

        // Floating toolbar
        if (showToolbar && framebuffer != null) {
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 16.dp),
                shape = RoundedCornerShape(28.dp),
                color = Color.Black.copy(alpha = 0.7f),
                shadowElevation = 8.dp
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Disconnect
                    IconButton(onClick = { session.disconnect() }) {
                        Icon(Icons.Default.Close, "Disconnect", tint = Color.Red)
                    }

                    // Input mode toggle
                    IconButton(onClick = {
                        inputMode = if (inputMode == InputMode.DIRECT) InputMode.TRACKPAD else InputMode.DIRECT
                    }) {
                        Text(
                            if (inputMode == InputMode.DIRECT) "D" else "T",
                            color = Color.White,
                            fontSize = 16.sp
                        )
                    }

                    // Keyboard
                    IconButton(onClick = {
                        showKeyboard = !showKeyboard
                        if (showKeyboard) {
                            try {
                                keyboardFocusRequester.requestFocus()
                            } catch (_: Exception) {}
                            keyboardController?.show()
                        } else {
                            keyboardController?.hide()
                            focusManager.clearFocus()
                        }
                    }) {
                        Icon(Icons.Default.Create, "Keyboard", tint = Color.White)
                    }

                    // Actions menu
                    IconButton(onClick = { showActions = true }) {
                        Icon(Icons.Default.MoreVert, "Actions", tint = Color.White)
                    }
                }
            }
        }

        // Swipe-up grab bar (when toolbar hidden)
        if (!showToolbar && framebuffer != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 8.dp)
                    .pointerInput(Unit) {
                        detectDragGestures { _, dragAmount ->
                            if (dragAmount.y < -20) {
                                showActions = true
                            }
                        }
                    }
            ) {
                Surface(
                    shape = RoundedCornerShape(2.dp),
                    color = Color.White.copy(alpha = 0.5f)
                ) {
                    Spacer(Modifier.size(width = 40.dp, height = 4.dp))
                }
            }
        }

        // Hidden keyboard input field
        if (showKeyboard) {
            var textFieldValue by remember {
                mutableStateOf(TextFieldValue(" ", TextRange(1)))
            }

            BasicTextField(
                value = textFieldValue,
                onValueChange = { newValue ->
                    val oldText = textFieldValue.text
                    val newText = newValue.text

                    if (newText.length > oldText.length) {
                        // Character added
                        val added = newText.removePrefix(oldText.take(1))
                        if (added.isNotEmpty()) {
                            for (char in added) {
                                sendCharAsKey(session, char)
                            }
                        }
                    } else if (newText.length < oldText.length) {
                        // Backspace
                        session.sendKey(X11KeySymbol.XK_BackSpace)
                    }

                    // Reset to single space to keep the field usable
                    textFieldValue = TextFieldValue(" ", TextRange(1))
                },
                modifier = Modifier
                    .size(1.dp)
                    .offset(x = (-100).dp)
                    .focusRequester(keyboardFocusRequester)
            )
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

    // Actions bottom sheet
    if (showActions) {
        AlertDialog(
            onDismissRequest = { showActions = false },
            title = { Text("Actions") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    ActionButton("Escape") {
                        session.sendKey(X11KeySymbol.XK_Escape)
                        showActions = false
                    }
                    ActionButton("Return") {
                        session.sendKey(X11KeySymbol.XK_Return)
                        showActions = false
                    }
                    ActionButton("Tab") {
                        session.sendKey(X11KeySymbol.XK_Tab)
                        showActions = false
                    }
                    ActionButton("Backspace") {
                        session.sendKey(X11KeySymbol.XK_BackSpace)
                        showActions = false
                    }
                    ActionButton("Delete") {
                        session.sendKey(X11KeySymbol.XK_Delete)
                        showActions = false
                    }
                    ActionButton("Space") {
                        session.sendKey(X11KeySymbol.XK_space)
                        showActions = false
                    }
                    ActionButton("Ctrl+Alt+Del") {
                        session.keyDown(X11KeySymbol.XK_Control_L)
                        session.keyDown(X11KeySymbol.XK_Alt_L)
                        session.sendKey(X11KeySymbol.XK_Delete)
                        session.keyUp(X11KeySymbol.XK_Alt_L)
                        session.keyUp(X11KeySymbol.XK_Control_L)
                        showActions = false
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                    ActionButton("Toggle Toolbar") {
                        showToolbar = !showToolbar
                        showActions = false
                    }
                    ActionButton("Disconnect", isDestructive = true) {
                        session.disconnect()
                        showActions = false
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showActions = false }) {
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

@Composable
private fun ActionButton(
    label: String,
    isDestructive: Boolean = false,
    onClick: () -> Unit
) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            label,
            color = if (isDestructive) MaterialTheme.colorScheme.error
            else MaterialTheme.colorScheme.onSurface
        )
    }
}

private fun sendCharAsKey(session: VncSession, char: Char) {
    // VNC uses X11 keysyms — ASCII 0x20-0x7E map directly to their keysym values
    // For uppercase/symbols, the keysym already encodes the character (e.g. 'A' = 0x41)
    // so the server handles it correctly without needing explicit shift
    val keysym = when {
        char.code in 0x20..0x7E -> char.code
        char == '\n' -> X11KeySymbol.XK_Return
        char == '\t' -> X11KeySymbol.XK_Tab
        else -> char.code or 0x01000000 // Unicode to X11 keysym
    }
    session.sendKey(keysym)
}
