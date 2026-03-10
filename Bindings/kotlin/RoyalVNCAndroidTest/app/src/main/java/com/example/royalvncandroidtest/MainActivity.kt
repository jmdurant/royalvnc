package com.example.royalvncandroidtest

import android.os.*
import android.widget.Toast
import androidx.activity.compose.*
import androidx.activity.*
import androidx.compose.runtime.*
import com.example.royalvncandroidtest.ui.theme.*

enum class Screen {
    CONNECT,
    SESSION,
    SETTINGS
}

class MainActivity : ComponentActivity() {
    private var nsdBrowser: NsdBrowser? = null
    private var vncSession: VncSession? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val context = this
        val profileStore = ProfileStore(context)
        val credentialStore = CredentialStore(context)
        val connectionSettings = ConnectionSettings(context)
        nsdBrowser = NsdBrowser(context)

        enableEdgeToEdge()

        setContent {
            var currentScreen by remember { mutableStateOf(Screen.CONNECT) }

            RoyalVNCAndroidTestTheme {
                when (currentScreen) {
                    Screen.CONNECT -> {
                        DisposableEffect(Unit) {
                            nsdBrowser?.startDiscovery()
                            onDispose { nsdBrowser?.stopDiscovery() }
                        }
                        ConnectScreen(
                            discoveredServers = nsdBrowser!!.servers,
                            profileStore = profileStore,
                            onConnect = { hostname, port ->
                                nsdBrowser?.stopDiscovery()

                                vncSession?.close()
                                vncSession = VncSession(
                                    hostname = hostname,
                                    port = port,
                                    settings = connectionSettings,
                                    credentialStore = credentialStore,
                                    onDisconnected = { errorMessage ->
                                        Handler(Looper.getMainLooper()).post {
                                            errorMessage?.let {
                                                Toast.makeText(context, it, Toast.LENGTH_LONG).show()
                                            }
                                            currentScreen = Screen.CONNECT
                                        }
                                    }
                                )
                                vncSession?.connect()
                                currentScreen = Screen.SESSION
                            },
                            onSettings = {
                                currentScreen = Screen.SETTINGS
                            }
                        )
                    }

                    Screen.SESSION -> {
                        vncSession?.let { session ->
                            SessionScreen(
                                session = session,
                                onDisconnected = {
                                    vncSession?.close()
                                    vncSession = null
                                    currentScreen = Screen.CONNECT
                                }
                            )
                        } ?: run {
                            currentScreen = Screen.CONNECT
                        }
                    }

                    Screen.SETTINGS -> {
                        SettingsScreen(
                            settings = connectionSettings,
                            onBack = {
                                currentScreen = Screen.CONNECT
                            }
                        )
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        nsdBrowser?.stopDiscovery()
        vncSession?.close()
        vncSession = null
    }
}
