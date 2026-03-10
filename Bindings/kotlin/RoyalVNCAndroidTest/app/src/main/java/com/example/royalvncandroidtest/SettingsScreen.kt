package com.example.royalvncandroidtest

import android.content.pm.PackageManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.royalapps.royalvnc.VncColorDepth
import com.royalapps.royalvnc.VncFrameEncodingType

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settings: ConnectionSettings,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val isTv = remember {
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    var colorDepth by remember { mutableStateOf(settings.colorDepth) }
    var isShared by remember { mutableStateOf(settings.isShared) }
    var isScaling by remember { mutableStateOf(settings.isScalingEnabled) }
    var isClipboard by remember { mutableStateOf(settings.isClipboardRedirectionEnabled) }
    var encodings by remember { mutableStateOf(settings.frameEncodings) }
    var cursorSpeed by remember { mutableIntStateOf(settings.cursorSpeed) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
        ) {
            // Color Depth
            Text("Color Depth", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))

            val depthOptions = listOf(
                VncColorDepth.BIT8 to "8-bit (256 Colors)",
                VncColorDepth.BIT16 to "16-bit",
                VncColorDepth.BIT24 to "24-bit (Full Color)"
            )

            depthOptions.forEach { (depth, label) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                ) {
                    RadioButton(
                        selected = colorDepth == depth,
                        onClick = {
                            colorDepth = depth
                            settings.colorDepth = depth
                        }
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(label, modifier = Modifier.padding(top = 12.dp))
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            // Encodings
            Text("Encodings", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))

            val encodingLabels = mapOf(
                VncFrameEncodingType.TIGHT to "Tight",
                VncFrameEncodingType.ZLIB to "Zlib",
                VncFrameEncodingType.ZRLE to "ZRLE",
                VncFrameEncodingType.HEXTILE to "Hextile",
                VncFrameEncodingType.CORRE to "CoRRE",
                VncFrameEncodingType.RRE to "RRE"
            )

            ConnectionSettings.ALL_ENCODINGS.forEach { encoding ->
                val isEnabled = encodings.contains(encoding)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                ) {
                    Switch(
                        checked = isEnabled,
                        onCheckedChange = { enabled ->
                            encodings = if (enabled) {
                                if (!encodings.contains(encoding)) encodings + encoding else encodings
                            } else {
                                if (encodings.size > 1) encodings - encoding else encodings
                            }
                            settings.frameEncodings = encodings
                        }
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        encodingLabels[encoding] ?: encoding.name,
                        modifier = Modifier.padding(top = 12.dp)
                    )
                }
            }

            // Cursor Speed (TV only)
            if (isTv) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

                Text("Cursor Speed", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedButton(
                        onClick = {
                            cursorSpeed = (cursorSpeed - 2).coerceAtLeast(2)
                            settings.cursorSpeed = cursorSpeed
                        },
                        enabled = cursorSpeed > 2
                    ) {
                        Text("-")
                    }
                    Text(
                        "${cursorSpeed}px",
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )
                    OutlinedButton(
                        onClick = {
                            cursorSpeed = (cursorSpeed + 2).coerceAtMost(40)
                            settings.cursorSpeed = cursorSpeed
                        },
                        enabled = cursorSpeed < 40
                    ) {
                        Text("+")
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            // Connection Options
            Text("Connection", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
            ) {
                Switch(
                    checked = isShared,
                    onCheckedChange = {
                        isShared = it
                        settings.isShared = it
                    }
                )
                Spacer(Modifier.width(8.dp))
                Text("Shared Session", modifier = Modifier.padding(top = 12.dp))
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
            ) {
                Switch(
                    checked = isScaling,
                    onCheckedChange = {
                        isScaling = it
                        settings.isScalingEnabled = it
                    }
                )
                Spacer(Modifier.width(8.dp))
                Text("Server Scaling", modifier = Modifier.padding(top = 12.dp))
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
            ) {
                Switch(
                    checked = isClipboard,
                    onCheckedChange = {
                        isClipboard = it
                        settings.isClipboardRedirectionEnabled = it
                    }
                )
                Spacer(Modifier.width(8.dp))
                Text("Clipboard Sync", modifier = Modifier.padding(top = 12.dp))
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

            // Reset
            OutlinedButton(
                onClick = {
                    settings.resetToDefaults()
                    colorDepth = VncColorDepth.BIT24
                    isShared = true
                    isScaling = true
                    isClipboard = false
                    encodings = ConnectionSettings.DEFAULT_ENCODINGS
                    cursorSpeed = ConnectionSettings.DEFAULT_CURSOR_SPEED
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Reset to Defaults")
            }
        }
    }
}
